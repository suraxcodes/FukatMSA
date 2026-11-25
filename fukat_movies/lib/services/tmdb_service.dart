/// Thin backwards-compatible façade over [TmdbClient].
///
/// The screens were written against a static `TmdbService`; rather than touch
/// every call site at once, this file forwards to the cached client. New code
/// should import `tmdb_client.dart` directly and use its typed errors.
library;

import 'dart:io';

import 'package:http/http.dart' as http;

import 'tmdb_client.dart';

export 'tmdb_client.dart' show HomeFeed;

class TmdbService {
  static Future<String?> getImdbId(int tmdbId, bool isMovie) =>
      TmdbClient.getImdbId(tmdbId, isMovie);

  static Future<Map<String, dynamic>?> getMovieDetails(int tmdbId) =>
      TmdbClient.getMovieDetails(tmdbId);

  static Future<Map<String, dynamic>?> getSeriesDetails(int tmdbId) =>
      TmdbClient.getSeriesDetails(tmdbId);

  static Future<List<dynamic>> getSeasonEpisodes(
    int tmdbId,
    int seasonNumber,
  ) => TmdbClient.getSeasonEpisodes(tmdbId, seasonNumber);

  static Future<List<dynamic>> getTrendingMovies() =>
      TmdbClient.getTrendingMovies();

  static Future<List<dynamic>> getTrendingTvShows() =>
      TmdbClient.getTrendingTvShows();

  static Future<List<dynamic>> getTrendingAnime() =>
      TmdbClient.getTrendingAnime();

  static Future<List<dynamic>> searchMedia(String query) =>
      TmdbClient.searchMedia(query);

  static Future<List<dynamic>> getSimilarMovies(int tmdbId) =>
      TmdbClient.getSimilarMovies(tmdbId);

  static Future<List<dynamic>> getSimilarTvShows(int tmdbId) =>
      TmdbClient.getSimilarTvShows(tmdbId);

  /// Cheap DNS check used by the home screen's offline banner.
  /// Prefer [TmdbClient.fetchHomeFeed] for real requests — it surfaces typed
  /// [AppErrorKind.offline] instead of guessing from a DNS lookup.
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'one.one.one.one',
      ).timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Kept for the legacy ad-block / provider test paths that still use it.
  static http.Client get client => http.Client();
}
