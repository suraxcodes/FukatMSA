import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tmdb_service.dart';

class StremioScraperService {
  // Add multiple Stremio Addon URLs here.
  // Note: For Torrentio to return HTTP streams (playable in Flutter), you need to configure it with a Debrid service.
  // e.g., 'https://torrentio.strem.fun/realdebrid=YOUR_KEY'
  // For now, we add public ones that might return direct HTTP streams or can be configured later.
  static final List<String> addonUrls = [
    'https://mediafusion.elfhosted.com', // MediaFusion supports tmdb IDs
    // 'https://torrentio.strem.fun', // Torrentio returns infoHashes (torrents) unless Debrid is configured
  ];

  /// Fetch streams from Stremio addons
  static Future<Map<String, dynamic>?> getStream({
    required String type, // 'movie', 'series', or 'tv'
    required String tmdbId,
    String? imdbId, // Some addons prefer IMDB
    int? season,
    int? episode,
  }) async {
    List<Map<String, dynamic>> aggregatedStreams = [];

    // Fetch IMDB ID if missing because most standard Stremio addons require it
    if (imdbId == null) {
      imdbId = await TmdbService.getImdbId(int.parse(tmdbId), type == 'movie');
      print("StremioScraper: Fetched IMDB ID $imdbId for TMDB $tmdbId");
    }

    for (String addon in addonUrls) {
      try {
        String queryId;
        
        // MediaFusion has good support for tmdb prefix
        if (addon.contains('mediafusion')) {
          if (type == 'movie') {
            queryId = 'tmdb:$tmdbId';
          } else {
            queryId = 'tmdb:$tmdbId:$season:$episode';
          }
        } else {
          // Standard Stremio addons (like Torrentio) usually require IMDB ID
          if (imdbId == null) {
            print("StremioScraper: Skipping $addon because IMDB ID is required but missing.");
            continue;
          }
          if (type == 'movie') {
            queryId = imdbId;
          } else {
            queryId = '$imdbId:$season:$episode';
          }
        }

        // Standard Stremio stream URL format
        final url = Uri.parse('$addon/stream/$type/$queryId.json');
        print("StremioScraper: Fetching $url");
        
        final response = await http.get(url).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final streams = data['streams'] as List<dynamic>? ?? [];

          for (var s in streams) {
            // We only want streams that have a direct HTTP 'url'.
            // Flutter VideoPlayer cannot play magnet links or infoHashes directly.
            if (s['url'] != null && s['url'].toString().startsWith('http')) {
              String name = s['name'] ?? 'Stremio';
              String title = s['title'] ?? 'Auto';
              
              aggregatedStreams.add({
                'quality': '$name - $title'.replaceAll('\n', ' '),
                'url': s['url'].toString(),
                'headers': {
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)',
                }
              });
            }
          }
        }
      } catch (e) {
        print("StremioScraper: Failed to fetch from $addon - $e");
      }
    }

    if (aggregatedStreams.isNotEmpty) {
      print("StremioScraper: Found ${aggregatedStreams.length} direct streams.");
      return {
        'streams': aggregatedStreams,
        'url': aggregatedStreams.first['url'],
        'headers': aggregatedStreams.first['headers'],
        'hasSub': false,
        'hasDub': false,
        'subtitles': [],
      };
    }

    return null;
  }
}
