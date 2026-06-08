import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamingAggregatorService {
  // Replace these with your deployed Vercel/Render URLs!
  static String miruroApiUrl = 'https://miruro-apimsa.onrender.com';
  static String kuudereApiUrl = 'https://kuudere-apimsa.onrender.com';
  static String proxifyStreamsUrl = 'https://proxify-streamsmsa.onrender.com';

  /// Fetch the native streaming URL (.m3u8) using the selected next-gen API
  static Future<Map<String, dynamic>?> getNativeStreamingUrl({
    required String title,
    required String engine,
    int season = 1,
    int episodeNumber = 1,
    bool isDub = false,
  }) async {
    print("Aggregator: Resolving $title (S$season E$episodeNumber) via $engine");

    if (engine == 'native_miruro') {
      return await _getMiruroStream(title, season, episodeNumber, isDub);
    } else if (engine == 'native_proxify') {
      return await _getProxifyStream(title, episodeNumber);
    }

    return null;
  }

  static Future<Map<String, dynamic>?> _getMiruroStream(String title, int s, int ep, bool isDub) async {
    try {
      final query = Uri.encodeComponent(title);
      final searchUrl = Uri.parse('$miruroApiUrl/search?query=$query');
      print("Aggregator: Miruro fetching search url: $searchUrl");

      final searchRes = await http.get(searchUrl, headers: {'Referer': 'https://fukatmovies.com'}).timeout(const Duration(seconds: 15));
      print("Aggregator: Miruro search status: ${searchRes.statusCode}");

      if (searchRes.statusCode == 200) {
        final searchData = json.decode(searchRes.body);
        final results = searchData['results'] as List<dynamic>? ?? [];
        if (results.isNotEmpty) {
          final anilistId = results.first['id'];
          print("Aggregator: Miruro Anilist ID: $anilistId");
          
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
              final dubEps = provData?['episodes']?['dub'] as List<dynamic>? ?? [];
              
              bool hasSub = subEps.any((e) => e['number'] == ep);
              bool hasDub = dubEps.any((e) => e['number'] == ep);
              
              String? targetWatchId;
              try {
                final targetList = isDub ? dubEps : subEps;
                final match = targetList.firstWhere((e) => e['number'] == ep);
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
                  
                  List<Map<String, dynamic>> extractedStreams = [];

                  // Filter for valid HLS streams
                  for (var s in streams) {
                    if (s['type'] == 'hls' && s['url'] != null && s['url'].toString().isNotEmpty) {
                      extractedStreams.add({
                        'quality': s['quality']?.toString() ?? 'Auto',
                        'url': s['url'].toString(),
                        'headers': {
                          if (s['referer'] != null) 'Referer': s['referer'].toString(),
                          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                        }
                      });
                    }
                  }
                  
                  List<Map<String, dynamic>> extractedSubtitles = [];
                  if (streamData['subtitles'] != null) {
                    final subs = streamData['subtitles'] as List<dynamic>;
                    for (var sub in subs) {
                      if (sub['url'] != null) {
                        extractedSubtitles.add({
                          'url': sub['url'].toString(),
                          'lang': sub['lang']?.toString() ?? 'Unknown',
                        });
                      }
                    }
                  }
                  
                  if (extractedStreams.isNotEmpty) {
                    print("Aggregator: Miruro successfully extracted HLS urls from $providerName!");
                    final resultData = {
                      'streams': extractedStreams, // We return multiple streams now!
                      'url': extractedStreams.first['url'], // Fallback legacy
                      'headers': extractedStreams.first['headers'], // Fallback legacy
                      'hasSub': hasSub,
                      'hasDub': hasDub,
                      'subtitles': extractedSubtitles,
                    };
                    print("Aggregator: Returning from Miruro: ${extractedStreams.length} qualities, ${extractedSubtitles.length} subtitles found. Dub: $hasDub, Sub: $hasSub");
                    return resultData;
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

  static Future<Map<String, dynamic>?> _getProxifyStream(String title, int ep) async {
    try {
      final query = Uri.encodeComponent(title);
      final url = Uri.parse('$proxifyStreamsUrl/stream?title=$query&ep=$ep');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'url': data['url'].toString(),
          'headers': {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
          }
        }; // Direct stream URL returned by proxy
      }
    } catch (e) {
      print("Proxify API Error: $e");
    }
    return null;
  }
}
