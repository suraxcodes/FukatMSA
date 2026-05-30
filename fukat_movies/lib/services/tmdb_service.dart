import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class TmdbService {
  // Base URL for TMDB API
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  // Private helper to fetch and decode JSON responses with retry & timeout
  static Future<Map<String, dynamic>> _fetchAndDecode(String path) async {
    final apiKey = dotenv.env['TMDB_API_KEY'];
    if (apiKey == null) {
      throw Exception('TMDB_API_KEY not set in .env');
    }
    final rawUri = Uri.parse('$_baseUrl$path');
    final uri = rawUri.replace(queryParameters: {
      ...rawUri.queryParameters,
      'api_key': apiKey,
    });
    if (kDebugMode) {
      print('TMDB request URI: $uri');
    }

    const int maxAttempts = 3;
    int attempt = 0;
    while (true) {
      try {
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 12), onTimeout: () {
          throw TimeoutException('TMDB request timed out');
        });
        if (response.statusCode != 200) {
          throw Exception('Failed to load TMDB data: ${response.statusCode}');
        }
        return json.decode(response.body) as Map<String, dynamic>;
      } on SocketException catch (_) {
        if (kDebugMode) {
          print('TMDB network error: No internet connection (attempt ${attempt + 1})');
        }
        if (attempt >= maxAttempts - 1) return {};
      } on TimeoutException catch (_) {
        if (kDebugMode) {
          print('TMDB request timed out (attempt ${attempt + 1})');
        }
        if (attempt >= maxAttempts - 1) return {};
      } catch (e) {
        if (kDebugMode) {
          print('TMDB unexpected error: $e');
        }
        return {};
      }
      attempt++;
      await Future.delayed(Duration(seconds: attempt * 2 + 2));
    }
  }

  // Get external IMDB ID for a TMDB record
  static Future<String?> getImdbId(int tmdbId, bool isMovie) async {
    final type = isMovie ? 'movie' : 'tv';
    try {
      final data = await _fetchAndDecode('/$type/$tmdbId/external_ids');
      return data['imdb_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  // Get TV series details
  static Future<Map<String, dynamic>?> getSeriesDetails(int tmdbId) async {
    try {
      final data = await _fetchAndDecode('/tv/$tmdbId');
      return data;
    } catch (_) {
      return null;
    }
  }

  // Get episodes for a season of a TV series
  static Future<List<dynamic>> getSeasonEpisodes(int tmdbId, int seasonNumber) async {
    try {
      final data = await _fetchAndDecode('/tv/$tmdbId/season/$seasonNumber');
      return (data['episodes'] as List<dynamic>?) ?? [];
    } catch (_) {
      return [];
    }
  }

  // Get Trending Movies (weekly)
  static Future<List<dynamic>> getTrendingMovies() async {
    final data = await _fetchAndDecode('/trending/movie/week');
    return (data['results'] as List<dynamic>?) ?? [];
  }

  // Get Trending TV Shows (weekly)
  static Future<List<dynamic>> getTrendingTvShows() async {
    final data = await _fetchAndDecode('/trending/tv/week');
    return (data['results'] as List<dynamic>?) ?? [];
  }
  // Get Trending Anime (weekly)
  static Future<List<dynamic>> getTrendingAnime() async {
    // TMDB does not have a direct anime trending endpoint.
    // Use discover TV with the Animation genre (id 16) sorted by popularity.
    final data = await _fetchAndDecode('/discover/tv?with_genres=16&sort_by=popularity.desc');
    return (data['results'] as List<dynamic>?) ?? [];
  }

  // Search Media (movies & TV) by query string
  static Future<List<dynamic>> searchMedia(String query) async {
    final encoded = Uri.encodeComponent(query);
    final data = await _fetchAndDecode('/search/multi?query=$encoded');
    return (data['results'] as List<dynamic>?) ?? [];
  }
  // Simple internet connectivity check
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }
}

