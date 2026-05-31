import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class TmdbService {
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  // Background Isolate JSON parser to eliminate UI frame jank
  static Map<String, dynamic> _parseJson(String responseBody) {
    return json.decode(responseBody) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _fetchAndDecode(String path) async {
    final token = dotenv.env['TMDB_API_TOKEN'];
    final apiKey = dotenv.env['TMDB_API_KEY'];

    if ((token == null || token.isEmpty) && (apiKey == null || apiKey.isEmpty)) {
      throw Exception('Missing configuration values: Configure TMDB keys in your .env file.');
    }

    // 🚀 THE CRITICAL FIX: Extract inline parameters cleanly to prevent broken URI formatting
    final cleanPath = path.contains('?') ? path.split('?')[0] : path;
    final inlineQueryString = path.contains('?') ? path.split('?')[1] : '';
    
    // Parse the base path safely
    Uri uri = Uri.parse('$_baseUrl$cleanPath');
    
    // Extract any existing query parameters from the path string
    Map<String, String> mergedQueryParameters = Map.from(uri.queryParameters);
    if (inlineQueryString.isNotEmpty) {
      final parsedQuery = Uri.splitQueryString(inlineQueryString);
      mergedQueryParameters.addAll(parsedQuery);
    }

    // Assign fallback v3 API key ONLY if the primary v4 Bearer Token is missing
    final bool useV4Token = token != null && token.isNotEmpty;
    if (!useV4Token && apiKey != null) {
      mergedQueryParameters['api_key'] = apiKey;
    }

    // Reconstruct the clean, unified Uri structure
    uri = uri.replace(queryParameters: mergedQueryParameters.isNotEmpty ? mergedQueryParameters : null);

    if (kDebugMode) {
      print('TMDB request URI: $uri');
      print(useV4Token ? 'Authentication Strategy: TMDB v4 Bearer Token' : 'Authentication Strategy: TMDB v3 URL Parameter');
    }

    // Build Request Headers
    final Map<String, String> headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json;charset=utf-8',
    };
    if (useV4Token) {
      headers['Authorization'] = 'Bearer $token';
    }

    const int maxAttempts = 3;
    int attempt = 0;

    while (true) {
      try {
        final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException('Network latency threshold exceeded.'),
        );

        if (response.statusCode != 200) {
          if (kDebugMode) {
            print('❌ TMDB Server Rejection [Status ${response.statusCode}]: ${response.body}');
          }
          throw Exception('Failed TMDB request (${response.statusCode})');
        }

        // Returns clean decoded objects parsed inside a background Isolate worker thread
        return await compute(_parseJson, response.body);

      } on SocketException catch (se) {
        if (kDebugMode) {
          print('⚠️ TMDB Socket Exception (Attempt ${attempt + 1}): ${se.message}');
        }
        if (attempt >= maxAttempts - 1) rethrow;
      } on TimeoutException catch (_) {
        if (kDebugMode) {
          print('⚠️ TMDB request timed out (Attempt ${attempt + 1})');
        }
        if (attempt >= maxAttempts - 1) rethrow;
      } catch (e, stack) {
        if (kDebugMode) {
          print('❌ Unhandled Exception Context: $e\nStack: $stack');
        }
        rethrow;
      }

      attempt++;
      // Exponential backoff strategy to reduce server hammer penalties
      await Future.delayed(Duration(seconds: attempt * 2 + 1));
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
      return await _fetchAndDecode('/tv/$tmdbId');
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