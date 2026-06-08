import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamingAggregatorService {
  // Replace these with your deployed Vercel/Render URLs!
  static String miruroApiUrl = 'https://your-miruro-api.onrender.com';
  static String kuudereApiUrl = 'https://kuudere-apimsa.onrender.com';
  static String proxifyStreamsUrl = 'https://proxify-streamsmsa.onrender.com';

  /// Fetch the native streaming URL (.m3u8) using the selected next-gen API
  static Future<String?> getNativeStreamingUrl({
    required String title,
    required String engine,
    required int season,
    required int episodeNumber,
  }) async {
    print("Aggregator: Resolving $title (S$season E$episodeNumber) via $engine");

    if (engine == 'native_miruro') {
      return await _getMiruroStream(title, episodeNumber);
    } else if (engine == 'native_kuudere') {
      return await _getKuudereStream(title, episodeNumber);
    } else if (engine == 'native_proxify') {
      return await _getProxifyStream(title, episodeNumber);
    }

    return null;
  }

  static Future<String?> _getMiruroStream(String title, int ep) async {
    try {
      // Miruro-API typically uses anilist search or title search
      final query = Uri.encodeComponent(title);
      final searchUrl = Uri.parse('$miruroApiUrl/search?query=$query');
      final searchRes = await http.get(searchUrl).timeout(const Duration(seconds: 15));

      if (searchRes.statusCode == 200) {
        final data = json.decode(searchRes.body);
        final anilistId = data['results']?[0]?['id'];

        if (anilistId != null) {
          final streamUrl = Uri.parse('$miruroApiUrl/watch?id=$anilistId&ep=$ep');
          final streamRes = await http.get(streamUrl).timeout(const Duration(seconds: 15));
          if (streamRes.statusCode == 200) {
            final streamData = json.decode(streamRes.body);
            return streamData['sources']?[0]?['url']; // Returns .m3u8
          }
        }
      }
    } catch (e) {
      print("Miruro API Error: $e");
    }
    return null;
  }

  static Future<String?> _getKuudereStream(String title, int ep) async {
    try {
      final query = Uri.encodeComponent(title);
      final searchUrl = Uri.parse('$kuudereApiUrl/api/v1/search?query=$query');
      final searchRes = await http.get(searchUrl).timeout(const Duration(seconds: 15));

      if (searchRes.statusCode == 200) {
        final data = json.decode(searchRes.body);
        // data could be directly the array, but Kuudere uses a standard success format maybe?
        // Wait, kuuderSearch returns an array of results. In v1.routes.ts: `createSuccessResponse(results)`
        // createSuccessResponse usually wraps in { success: true, data: results }
        // Let's assume `data['data'][0]['id']` or fallback to `data[0]?['id']`
        final results = data['data'] ?? data;
        final animeId = results.isNotEmpty ? results[0]['id'] : null;

        if (animeId != null) {
          final epUrl = Uri.parse('$kuudereApiUrl/api/v1/episodes/$animeId');
          final epRes = await http.get(epUrl).timeout(const Duration(seconds: 15));
          
          if (epRes.statusCode == 200) {
            final epDataRaw = json.decode(epRes.body);
            final epData = epDataRaw['data'] ?? epDataRaw;
            
            final targetEpId = epData.firstWhere((e) => e['number'] == ep, orElse: () => epData[0])['id'];
            
            final streamUrl = Uri.parse('$kuudereApiUrl/api/v1/sources?id=$targetEpId');
            final streamRes = await http.get(streamUrl).timeout(const Duration(seconds: 15));
            if (streamRes.statusCode == 200) {
              final streamData = json.decode(streamRes.body);
              final sources = streamData['data'] ?? streamData;
              // Sources is usually { sources: [{url: "..."}] } or [{url: "..."}]
              final sourceList = sources['sources'] ?? sources;
              return sourceList[0]?['url'];
            }
          }
        }
      }
    } catch (e) {
      print("Kuudere API Error: $e");
    }
    return null;
  }

  static Future<String?> _getProxifyStream(String title, int ep) async {
    try {
      final query = Uri.encodeComponent(title);
      final url = Uri.parse('$proxifyStreamsUrl/stream?title=$query&ep=$ep');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['url']; // Direct stream URL returned by proxy
      }
    } catch (e) {
      print("Proxify API Error: $e");
    }
    return null;
  }
}
