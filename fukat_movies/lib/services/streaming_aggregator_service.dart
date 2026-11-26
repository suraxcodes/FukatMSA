/// Bridges the resolver to the native/external engines.
///
/// ## What was wrong before
///
/// `_getProxifyStream` called `$PROXIFY/api/stream?title=…&ep=…` and read
/// `data['stream_url']`. That route **does not exist** (verified 404) — the
/// service it pointed at is a *proxy generator*, not a resolver. Its real
/// endpoint is `GET /proxy?data={hlsUrl}|{referer}`, which returns encoded
/// mirrors of a stream you *already have*.
///
/// So proxify is not a provider. It is a **post-processing step**: when a
/// provider hands back an m3u8 whose CDN rejects you for a missing Referer,
/// we can rewrite it through the proxy. This file now reflects that.
library;

import 'dart:async';

import '../core/app_config.dart';
import '../core/errors.dart';
import '../core/http_json.dart';
import '../core/log.dart';
import 'stremio_addon_service.dart';

class StreamingAggregatorService {
  StreamingAggregatorService._();

  static const String _tag = 'Aggregator';

  /// Engine ids that resolve a stream server-side.
  static const Set<String> nativeEngines = {'native_stremio', 'native_proxify'};

  /// Engine ids that run the headless-WebView extractor on the client.
  static const Set<String> extractorEngines = {'native_extractor'};

  /// The last provider that actually played something. Used to try the
  /// winner first on the next episode instead of re-racing all of them.
  static String? preferredProvider;

  static Future<Map<String, dynamic>?> getNativeStreamingUrl({
    required String title,
    required String engine,
    String? tmdbId,
    bool isMovie = true,
    int season = 1,
    int episodeNumber = 1,
    bool isDub = false,
  }) async {
    Log.d(_tag, 'resolve "$title" S$season E$episodeNumber via $engine');

    switch (engine) {
      case 'native_stremio':
        if (tmdbId == null || tmdbId.isEmpty) {
          throw const AppError(
            AppErrorKind.badRequest,
            'native_stremio needs a tmdbId',
          );
        }
        return StremioAddonService.getStream(
          type: isMovie ? 'movie' : 'series',
          tmdbId: tmdbId,
          season: season,
          episode: episodeNumber,
        );

      case 'native_proxify':
        // Proxify cannot resolve by title. Refuse loudly instead of silently
        // firing a request that is guaranteed to 404.
        throw const AppError(
          AppErrorKind.badRequest,
          'native_proxify is a URL rewriter, not a provider — remove it from '
          'remote_config.json (see docs/PROVIDERS.md).',
        );

      default:
        throw AppError(
          AppErrorKind.badRequest,
          'unknown native engine "$engine"',
        );
    }
  }

  // ------------------------------------------------------------- proxify

  /// Rewrites an HLS URL through the self-hosted proxy so a strict CDN
  /// Referer check passes. Returns the original URL unchanged when no proxy
  /// is configured or the proxy fails — playback must never depend on it.
  static Future<String> proxyHlsIfConfigured(
    String hlsUrl, {
    String? referer,
  }) async {
    final base = AppConfig.proxifyStreamsUrl;
    if (base.isEmpty) return hlsUrl;

    final ref = referer ?? _refererFor(hlsUrl);
    try {
      final uri = Uri.parse(
        '$base/proxy',
      ).replace(queryParameters: {'data': '$hlsUrl|$ref'});
      final data = await HttpJson.getJson(
        uri,
        headers: {
          if (AppConfig.proxifySharedSecret.isNotEmpty)
            'X-Api-Key': AppConfig.proxifySharedSecret,
        },
        timeout: const Duration(seconds: 12),
        context: 'proxify',
      );

      final source = (data is Map ? data['proxifiedSource'] : null);
      if (source is Map && source.isNotEmpty) {
        // Prefer the mirror most likely to allow CORS/range requests.
        for (final key in const [
          'animanga',
          'lunaranime',
          'anikuro',
          'miruro',
        ]) {
          final url = source[key];
          if (url is String && url.isNotEmpty) {
            Log.i(_tag, 'proxied via $key');
            return url;
          }
        }
      }
    } on AppError catch (e) {
      Log.w(_tag, 'proxy rewrite failed, using direct url', e);
    }
    return hlsUrl;
  }

  static String _refererFor(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    // CDNs in this space generally accept the origin site as referer.
    if (host.contains('owocdn')) return 'https://kwik.cx/';
    if (host.contains('code29wave')) return 'https://megaup.nl/';
    return 'https://$host/';
  }
}
