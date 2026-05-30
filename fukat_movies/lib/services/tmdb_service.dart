import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TmdbService {
  static String get _apiKey => dotenv.env['TMDB_API_KEY'] ?? '';
  static const String _baseUrl = "https://api.themoviedb.org/3";

  // Fetch trending movies
  static Future<List<dynamic>> getTrendingMovies() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/trending/movie/day?api_key=$_apiKey'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'];
      }
    } catch (e) {
      print("Error fetching trending movies: $e");
    }
    return [];
  }

  // Fetch trending TV shows
  static Future<List<dynamic>> getTrendingTvShows() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/trending/tv/day?api_key=$_apiKey'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'];
      }
    } catch (e) {
      print("Error fetching trending TV shows: $e");
    }
    return [];
  }

  // Search for movies/tv
  static Future<List<dynamic>> searchMedia(String query) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/search/multi?api_key=$_apiKey&query=$query'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'].where((item) => item['media_type'] == 'movie' || item['media_type'] == 'tv').toList();
      }
    } catch (e) {
      print("Error searching media: $e");
    }
    return [];
  }

  // Get external IDs (IMDB ID) for a movie/tv show given its TMDB ID
  static Future<String?> getImdbId(int tmdbId, bool isMovie) async {
    try {
      final type = isMovie ? 'movie' : 'tv';
      final response = await http.get(Uri.parse('$_baseUrl/$type/$tmdbId/external_ids?api_key=$_apiKey'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['imdb_id'];
      }
    } catch (e) {
      print("Error fetching IMDB ID: $e");
    }
    return null;
  }
}
