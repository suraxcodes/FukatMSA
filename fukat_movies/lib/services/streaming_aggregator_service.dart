import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamingAggregatorService {
  // Replace these with your deployed Vercel/Render URLs!
  static String miruroApiUrl = 'https://miruro-apimsa.onrender.com';
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
      final query = Uri.encodeComponent(title);
      final searchUrl = Uri.parse('$miruroApiUrl/search?query=$query');
      print("Aggregator: Miruro fetching search url: $searchUrl");
      final searchRes = await http.get(searchUrl, headers: {'Referer': 'https://fukatmovies.com'}).timeout(const Duration(seconds: 60));

      print("Aggregator: Miruro search status: ${searchRes.statusCode}");
      if (searchRes.statusCode == 200) {
        final data = json.decode(searchRes.body);
        final results = data['results'] ?? [];
        if (results.isEmpty) {
          print("Aggregator: Miruro search returned no results.");
          return null;
        }
        
        final anilistId = results[0]['id'];
        print("Aggregator: Miruro Anilist ID: $anilistId");
        
        if (anilistId != null) {
          final epUrl = Uri.parse('$miruroApiUrl/episodes/$anilistId');
          print("Aggregator: Miruro fetching episodes list: $epUrl");
          final epRes = await http.get(epUrl, headers: {'Referer': 'https://fukatmovies.com'}).timeout(const Duration(seconds: 60));
          
          print("Aggregator: Miruro episodes status: ${epRes.statusCode}");
          if (epRes.statusCode == 200) {
            final epData = json.decode(epRes.body);
            final providers = epData['providers'] as Map<String, dynamic>? ?? {};
            
            // Try each provider until we get a valid HLS stream
            for (var providerName in providers.keys) {
              final provData = providers[providerName];
              final subEps = provData?['episodes']?['sub'] as List<dynamic>? ?? [];
              
              String? targetWatchId;
              try {
                final match = subEps.firstWhere((e) => e['number'] == ep);
                targetWatchId = match['id'];
              } catch (_) {
                // not found in this provider
                continue;
              }
              
              print("Aggregator: Miruro found match in provider $providerName -> $targetWatchId");
              
              // Fetch stream for this specific provider's episode
              final streamUrl = Uri.parse('$miruroApiUrl/$targetWatchId');
              print("Aggregator: Miruro fetching stream from: $streamUrl");
              
              try {
                final streamRes = await http.get(streamUrl, headers: {'Referer': 'https://fukatmovies.com'}).timeout(const Duration(seconds: 20));
                print("Aggregator: Miruro stream status ($providerName): ${streamRes.statusCode}");
                
                if (streamRes.statusCode == 200) {
                  final streamData = json.decode(streamRes.body);
                  final streams = streamData['streams'] as List<dynamic>? ?? [];
                  
                  // Filter for valid HLS streams
                  for (var s in streams) {
                    if (s['type'] == 'hls' && s['url'] != null && s['url'].toString().isNotEmpty) {
                      print("Aggregator: Miruro successfully extracted HLS url from $providerName!");
                      return s['url'];
                    }
                  }
                  print("Aggregator: Miruro no valid HLS streams found in $providerName, trying next...");
                } else {
                  print("Aggregator: Miruro stream body ($providerName): ${streamRes.body}");
                }
              } catch (e) {
                print("Aggregator: Miruro error fetching stream from $providerName: $e");
              }
            }
            
            print("Aggregator: Miruro exhausted all providers, no valid HLS stream found.");
            
          } else {
             print("Aggregator: Miruro episodes body: ${epRes.body}");
          }
        }
      } else {
        print("Miruro API Error: Status Code ${searchRes.statusCode} Body: ${searchRes.body}");
      }
    } catch (e) {
      print("Miruro API Exception: $e");
    }
    return null;
  }

  static Future<String?> _getKuudereStream(String title, int ep) async {
    try {
      final query = Uri.encodeComponent(title);
      final searchUrl = Uri.parse('$kuudereApiUrl/api/v1/search?query=$query');
      print("Aggregator: Fetching $searchUrl");
      final searchRes = await http.get(searchUrl).timeout(const Duration(seconds: 60));

      print("Aggregator: Kuudere Search Response Code: ${searchRes.statusCode}");
      print("Aggregator: Kuudere Search Response Body: ${searchRes.body}");

      if (searchRes.statusCode == 200) {
        final data = json.decode(searchRes.body);
        final results = data['data'] ?? data;
        final animeId = results.isNotEmpty ? results[0]['id'] : null;

        if (animeId != null) {
          final epUrl = Uri.parse('$kuudereApiUrl/api/v1/episodes/$animeId');
          final epRes = await http.get(epUrl).timeout(const Duration(seconds: 60));
          
          if (epRes.statusCode == 200) {
            final epDataRaw = json.decode(epRes.body);
            final epData = epDataRaw['data'] ?? epDataRaw;
            
            final targetEpId = epData.firstWhere((e) => e['number'] == ep, orElse: () => epData[0])['id'];
            
            final streamUrl = Uri.parse('$kuudereApiUrl/api/v1/sources?id=$targetEpId');
            final streamRes = await http.get(streamUrl).timeout(const Duration(seconds: 60));
            if (streamRes.statusCode == 200) {
              final streamData = json.decode(streamRes.body);
              final sources = streamData['data'] ?? streamData;
              final sourceList = sources['sources'] ?? sources;
              return sourceList[0]?['url'];
            }
          }
        }
      } else {
        print("Kuudere API Error: Status Code ${searchRes.statusCode}");
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
