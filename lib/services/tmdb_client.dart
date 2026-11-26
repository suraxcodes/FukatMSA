/// TMDB access layer.
///
/// Replaces the old all-static [TmdbService] which:
///  * built a Uri by string-splitting the path (fragile),
///  * used a fresh `http.get` per call (no pooling, no cache),
///  * refetched `external_ids` for every provider on every episode switch,
///  * and swallowed every failure into `null`.
///
/// This version: typed errors, TTL cache per endpoint, in-flight request
/// de-duplication, and concurrent batch helpers for the home screen.
library;

import '../core/app_config.dart';
import '../core/errors.dart';
import '../core/http_json.dart';
import '../core/log.dart';

class TmdbClient {
  TmdbClient._();

  static const String _tag = 'TMDB';

  // Cache lifetimes. Long for immutable-ish ids, short for "trending".
  static const Duration _ttlImdbId = Duration(hours: 24 * 7);
  static const Duration _ttlDetails = Duration(hours: 24);
  static const Duration _ttlSeason = Duration(hours: 6);
  static const Duration _ttlTrending = Duration(minutes: 15);
  static const Duration _ttlSearch = Duration(minutes: 10);
  static const Duration _ttlSimilar = Duration(hours: 6);

  /// De-duplicates identical in-flight requests. If the home screen and a
  /// detail screen ask for the same movie at the same time, one HTTP call
  /// happens, not two.
  static final Map<String, Future<dynamic>> _inflight = {};

  static Map<String, String> get _headers {
    final headers = <String, String>{};
    if (AppConfig.tmdbReadToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${AppConfig.tmdbReadToken}';
    }
    return headers;
  }

  /// Single entry point for every TMDB GET.
  ///
  /// [path] is a clean path such as `/movie/550` plus an optional query map —
  /// the caller never has to hand-assemble query strings.
  static Future<dynamic> _get(
    String path, {
    Map<String, String>? query,
    required Duration cacheFor,
  }) async {
    if (!AppConfig.hasTmdbCredentials) {
      throw const AppError(
        AppErrorKind.badRequest,
        'TMDB credentials missing. Set TMDB_API_TOKEN via --dart-define or assets/.env.',
      );
    }

    final params = <String, String>{
      if (AppConfig.tmdbReadToken.isEmpty && AppConfig.tmdbApiKey.isNotEmpty)
        'api_key': AppConfig.tmdbApiKey,
      ...?query,
    };

    final uri = Uri.parse(
      '${AppConfig.tmdbBaseUrl}$path',
    ).replace(queryParameters: params.isEmpty ? null : params);

    final key = uri.toString();
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = HttpJson.getJson(
      uri,
      headers: _headers,
      cacheFor: cacheFor,
      context: 'TMDB $path',
    ).whenComplete(() => _inflight.remove(key));

    _inflight[key] = future;
    return future;
  }

  static List<dynamic> _results(dynamic data) =>
      (data is Map && data['results'] is List)
      ? data['results'] as List
      : const [];

  // ------------------------------------------------------------- public API

  /// IMDB id for a TMDB record. Returns null when TMDB has none (common for
  /// obscure titles) — callers must fall back to the TMDB id.
  static Future<String?> getImdbId(int tmdbId, bool isMovie) async {
    try {
      final data = await _get(
        '/${isMovie ? 'movie' : 'tv'}/$tmdbId/external_ids',
        cacheFor: _ttlImdbId,
      );
      final id = (data is Map ? data['imdb_id'] : null) as String?;
      return (id != null && id.isNotEmpty) ? id : null;
    } on AppError catch (e) {
      Log.w(_tag, 'imdb id lookup failed for $tmdbId', e);
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getMovieDetails(int tmdbId) =>
      _details('/movie/$tmdbId', 'movie $tmdbId');

  static Future<Map<String, dynamic>?> getSeriesDetails(int tmdbId) =>
      _details('/tv/$tmdbId', 'tv $tmdbId');

  static Future<Map<String, dynamic>?> _details(
    String path,
    String label,
  ) async {
    try {
      final data = await _get(path, cacheFor: _ttlDetails);
      return data is Map<String, dynamic> ? data : null;
    } on AppError catch (e) {
      Log.w(_tag, 'details failed for $label', e);
      return null;
    }
  }

  /// Episodes that have actually aired (7-day buffer for timezone leaks).
  /// Throws nothing: an unreadable season is an empty season.
  static Future<List<dynamic>> getSeasonEpisodes(
    int tmdbId,
    int seasonNumber,
  ) async {
    try {
      final data = await _get(
        '/tv/$tmdbId/season/$seasonNumber',
        cacheFor: _ttlSeason,
      );
      final episodes =
          (data is Map ? data['episodes'] : null) as List<dynamic>? ?? const [];
      final cutoff = DateTime.now().add(const Duration(days: 7));

      return episodes
          .where((ep) {
            if (ep is! Map || ep['episode_number'] == null) return false;
            final rawDate = ep['air_date'];
            if (rawDate is! String || rawDate.trim().isEmpty) return true;
            final airDate = DateTime.tryParse(rawDate.trim());
            if (airDate == null) return true; // unparseable → keep it
            return !airDate.isAfter(cutoff);
          })
          .toList(growable: false);
    } on AppError catch (e) {
      Log.w(_tag, 'season $seasonNumber of $tmdbId failed', e);
      return const [];
    }
  }

  static Future<List<dynamic>> getTrendingMovies() async =>
      _results(await _get('/trending/movie/day', cacheFor: _ttlTrending));

  static Future<List<dynamic>> getTrendingTvShows() async =>
      _results(await _get('/trending/tv/day', cacheFor: _ttlTrending));

  /// Anime specifically: Japanese origin + animation genre + not adult.
  /// The old `with_genres=16` alone pulled in every western cartoon.
  static Future<List<dynamic>> getTrendingAnime() async => _results(
    await _get(
      '/discover/tv',
      query: const {
        'with_genres': '16',
        'with_origin_country': 'JP',
        'without_genres': '10762', // kids
        'include_adult': 'false',
        'sort_by': 'popularity.desc',
      },
      cacheFor: _ttlTrending,
    ),
  );

  static Future<List<dynamic>> searchMedia(String query) async {
    if (query.trim().isEmpty) return const [];
    return _results(
      await _get(
        '/search/multi',
        query: {'query': query.trim(), 'include_adult': 'false'},
        cacheFor: _ttlSearch,
      ),
    );
  }

  static Future<List<dynamic>> getSimilarMovies(int tmdbId) async => _results(
    await _get('/movie/$tmdbId/recommendations', cacheFor: _ttlSimilar),
  );

  static Future<List<dynamic>> getSimilarTvShows(int tmdbId) async => _results(
    await _get('/tv/$tmdbId/recommendations', cacheFor: _ttlSimilar),
  );

  // --------------------------------------------------- concurrent home feed
  /// Fetches the whole home screen in parallel instead of the old
  /// sequential `await … Future.delayed(300ms) await …` chain.
  ///
  /// Returns partial data on partial failure: one broken row must not blank
  /// the entire screen.
  static Future<HomeFeed> fetchHomeFeed() async {
    final results = await Future.wait<List<dynamic>>([
      getTrendingMovies().catchError((Object e) {
        Log.w(_tag, 'trending movies failed', e);
        return const <dynamic>[];
      }),
      getTrendingTvShows().catchError((Object e) {
        Log.w(_tag, 'trending tv failed', e);
        return const <dynamic>[];
      }),
      getTrendingAnime().catchError((Object e) {
        Log.w(_tag, 'trending anime failed', e);
        return const <dynamic>[];
      }),
    ]).timeout(
      const Duration(seconds: 30),
      onTimeout: () => const [<dynamic>[], <dynamic>[], <dynamic>[]],
    );

    return HomeFeed(
      movies: results[0] as List<dynamic>,
      tvShows: results[1] as List<dynamic>,
      anime: results[2] as List<dynamic>,
    );
  }

  static void clearCache() => HttpJson.clearCache();
}

class HomeFeed {
  final List<dynamic> movies;
  final List<dynamic> tvShows;
  final List<dynamic> anime;

  const HomeFeed({
    required this.movies,
    required this.tvShows,
    required this.anime,
  });

  bool get isEmpty => movies.isEmpty && tvShows.isEmpty && anime.isEmpty;
}
