import 'dart:convert';
import 'package:http/http.dart' as http;
import 'remote_config_service.dart';
import 'stremio_scraper_service.dart';

class StreamingAggregatorService {
  static String get proxifyStreamsUrl =>
      RemoteConfigService.remoteEnv['PROXIFY_STREAMS_URL'] ??
      'https://proxify-streamsmsa.onrender.com';

  static String? preferredProvider; // Added to remember the working provider

  /// Fetch the native streaming URL (.m3u8) using the selected next-gen API
  static Future<Map<String, dynamic>?> getNativeStreamingUrl({
    required String title,
    required String engine,
    String? tmdbId,
    bool isMovie = true,
    int season = 1,
    int episodeNumber = 1,
    bool isDub = false,
  }) async {
    print(
      "Aggregator: Resolving $title (S$season E$episodeNumber) via $engine",
    );

    if (engine == 'native_proxify') {
      return await _getProxifyStream(title, episodeNumber);
    } else if (engine == 'native_stremio' && tmdbId != null) {
      return await _getStremioStream(tmdbId, isMovie, season, episodeNumber);
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _getProxifyStream(
    String title,
    int ep,
  ) async {
    try {
      final url = Uri.parse(
        '$proxifyStreamsUrl/api/stream?title=${Uri.encodeComponent(title)}&ep=$ep',
      );
      print("Aggregator: Fetching Proxify stream from $url");
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['stream_url'] != null) {
          String streamUrl = data['stream_url'].toString();

          return {
            'streams': [
              {
                'quality': 'Auto',
                'url': streamUrl,
                'headers': {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Origin': 'https://vidsrc.to',
                  'Referer': 'https://vidsrc.to/',
                },
              },
            ],
            'url': streamUrl,
            'headers': {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Origin': 'https://vidsrc.to',
              'Referer': 'https://vidsrc.to/',
            },
            'hasSub': true,
            'hasDub': false,
            'subtitles': [],
          };
        }
      } else {
        print("Aggregator: Proxify failed with status ${response.statusCode}");
      }
    } catch (e) {
      print("Proxify API Error: $e");
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _getStremioStream(String tmdbId, bool isMovie, int season, int ep) async {
    print("Aggregator: Fetching stream from Stremio addons...");
    try {
      return await StremioScraperService.getStream(
        type: isMovie ? 'movie' : 'series',
        tmdbId: tmdbId,
        season: season,
        episode: ep,
      );
    } catch(e) {
      print("Stremio Scraper Error: $e");
    }
    return null;
  }
}
