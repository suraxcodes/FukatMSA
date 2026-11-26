/// Stremio addon client (the `native_stremio` engine).
///
/// Renamed from `StremioScraperService` and rewritten because the old version:
///  * hard-coded the addon list with no way to configure it,
///  * silently swallowed every error and returned null,
///  * and could not be reached at all from `PlaybackManager` (which dropped
///    the `tmdbId` argument).
///
/// The addon URL is configurable via `MEDIAFUSION_URL` / `--dart-define`.
/// Note that public addons frequently answer `{"streams":[]}` — that is a
/// valid answer, not an error, so it is surfaced as "no streams" rather than
/// a failure you can retry into success.
library;

import '../core/app_config.dart';
import '../core/errors.dart';
import '../core/http_json.dart';
import '../core/log.dart';
import 'tmdb_client.dart';

class StremioAddonService {
  StremioAddonService._();

  static const String _tag = 'Stremio';

  /// Addons to query, in order. Configured via `STREMIO_ADDON_URL`
  /// (e.g. a Torrentio instance with a debrid key) or appended here.
  /// Empty by default — see [AppConfig.stremioAddonUrl] for why.
  static List<String> get addonBaseUrls => [
    AppConfig.stremioAddonUrl,
  ].where((u) => u.isNotEmpty).toList(growable: false);

  static Future<Map<String, dynamic>?> getStream({
    required String type, // 'movie' | 'series'
    required String tmdbId,
    int? season,
    int? episode,
  }) async {
    final parsedId = int.tryParse(tmdbId);
    if (parsedId == null) {
      throw AppError(AppErrorKind.badRequest, 'bad tmdbId "$tmdbId"');
    }

    final isMovie = type == 'movie';

    // MediaFusion accepts the `tmdb:` prefix; generic addons need an IMDb id.
    final imdbId = await TmdbClient.getImdbId(parsedId, isMovie);

    final collected = <Map<String, dynamic>>[];

    for (final base in addonBaseUrls) {
      final candidates = <String>[
        isMovie ? 'tmdb:$tmdbId' : 'tmdb:$tmdbId:$season:$episode',
        if (imdbId != null) isMovie ? imdbId : '$imdbId:$season:$episode',
      ];

      for (final queryId in candidates) {
        final uri = Uri.parse('$base/stream/$type/$queryId.json');
        try {
          final data = await HttpJson.getJson(
            uri,
            timeout: const Duration(seconds: 15),
            context: 'stremio $queryId',
          );
          final streams = (data is Map ? data['streams'] : null) as List? ?? [];
          if (streams.isEmpty) continue;

          for (final s in streams) {
            if (s is! Map) continue;
            final url = s['url']?.toString();
            // Magnet links / infoHashes are not playable by media_kit.
            if (url == null || !url.startsWith('http')) continue;

            final name = (s['name'] ?? 'Stremio').toString().replaceAll(
              '\n',
              ' ',
            );
            final title = (s['title'] ?? 'Auto').toString().replaceAll(
              '\n',
              ' ',
            );
            collected.add({
              'quality': '$name - $title'.trim(),
              'url': url,
              'headers': const {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
              },
            });
          }
        } on AppError catch (e) {
          // A sleeping addon or a 404 id is expected; try the next candidate.
          Log.d(_tag, 'addon $base rejected $queryId (${e.kind.name})');
        }
      }
    }

    if (collected.isEmpty) {
      Log.i(_tag, 'no direct streams found for $type $tmdbId');
      return null;
    }

    Log.i(_tag, 'found ${collected.length} direct streams');
    return {
      'streams': collected,
      'url': collected.first['url'],
      'headers': collected.first['headers'],
      'hasSub': false,
      'hasDub': false,
      'subtitles': const <Map<String, String>>[],
    };
  }
}
