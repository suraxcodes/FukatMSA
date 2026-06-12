import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamingAggregatorService {
  // Replace these with your deployed Vercel/Render URLs!
  static String miruroApiUrl = 'https://miruro-apimsa.onrender.com';
  static String kuudereApiUrl = 'https://kuudere-apimsa.onrender.com';
  static String proxifyStreamsUrl = 'https://proxify-streamsmsa.onrender.com';

  static String? preferredProvider; // Added to remember the working provider

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
      // 1. Resolve Anilist ID via official GraphQL API (Reliable)
      final anilistUrl = Uri.parse('https://graphql.anilist.co');
      final anilistQuery = '''
        query (\$search: String) {
          Media(search: \$search, type: ANIME, sort: SEARCH_MATCH) {
            id
          }
        }
      ''';
      
      print("Aggregator: Fetching Anilist ID for $title");
      final anilistRes = await http.post(
        anilistUrl,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        },
        body: json.encode({
          'query': anilistQuery,
          'variables': {'search': title},
        }),
      ).timeout(const Duration(seconds: 15));

      if (anilistRes.statusCode == 200) {
        final anilistData = json.decode(anilistRes.body);
        final media = anilistData['data']?['Media'];
        
        if (media != null && media['id'] != null) {
          final anilistId = media['id'];
          print("Aggregator: Anilist ID resolved: $anilistId");
          
          // 2. Fetch episodes list from Miruro
          final epUrl = Uri.parse('$miruroApiUrl/episodes/$anilistId');
          print("Aggregator: Miruro fetching episodes list: $epUrl");
          
          final epRes = await http.get(epUrl, headers: {'Referer': 'https://fukatmovies.com'}).timeout(const Duration(seconds: 60));
          
          print("Aggregator: Miruro episodes status: ${epRes.statusCode}");
          if (epRes.statusCode == 200) {
            final epData = json.decode(epRes.body);
            final providers = epData['providers'] as Map<String, dynamic>? ?? {};
            
            List<String> providerKeys = providers.keys.toList();
            // Prioritize reliable providers like 'ally' (Zoro) and 'kiwi' (Gogo)
            providerKeys.sort((a, b) {
              // Priority 0: The user's preferred provider from the last successfully played episode
              if (preferredProvider != null) {
                if (a == preferredProvider) return -1;
                if (b == preferredProvider) return 1;
              }
              
              const priority = {'ally': 1, 'kiwi': 2, 'bonk': 3, 'ANIMEDUNYA': 4};
              final pA = priority[a] ?? 99;
              final pB = priority[b] ?? 99;
              return pA.compareTo(pB);
            });
            
            List<Map<String, dynamic>> allStreams = [];
            List<Map<String, dynamic>> allSubtitles = [];
            bool overallHasSub = false;
            bool overallHasDub = false;
            
            // Try each provider and aggregate all valid HLS/MP4 streams
            for (var providerName in providerKeys) {
              final provData = providers[providerName];
              final subEps = provData?['episodes']?['sub'] as List<dynamic>? ?? [];
              final dubEps = provData?['episodes']?['dub'] as List<dynamic>? ?? [];
              
              if (subEps.isNotEmpty) overallHasSub = true;
              if (dubEps.isNotEmpty) overallHasDub = true;
              
              String? targetWatchId;
              try {
                final targetList = isDub ? dubEps : subEps;
                final match = targetList.firstWhere((e) => e['number'] == ep);
                targetWatchId = match['id'];
              } catch (_) {
                if (isDub) {
                  print("Aggregator: Dub not found in $providerName for ep $ep. Falling back to Sub!");
                  try {
                    final match = subEps.firstWhere((e) => e['number'] == ep);
                    targetWatchId = match['id'];
                  } catch (__) {
                    continue;
                  }
                } else {
                  continue;
                }
              }
              
              print("Aggregator: Miruro found match in provider $providerName -> $targetWatchId");
              
              final streamUrl = Uri.parse('$miruroApiUrl/$targetWatchId');
              print("Aggregator: Miruro fetching stream from: $streamUrl");
              
              try {
                final streamRes = await http.get(streamUrl, headers: {'Referer': 'https://fukatmovies.com'}).timeout(const Duration(seconds: 20));
                print("Aggregator: Miruro stream status ($providerName): ${streamRes.statusCode}");
                
                if (streamRes.statusCode == 200) {
                  final streamData = json.decode(streamRes.body);
                  final streams = streamData['streams'] as List<dynamic>? ?? [];
                  
                  for (var s in streams) {
                    if ((s['type'] == 'hls' || s['type'] == 'mp4') && s['url'] != null && s['url'].toString().isNotEmpty) {
                      allStreams.add({
                        'quality': '${s['quality']?.toString() ?? 'Auto'} ($providerName)',
                        'url': s['url'].toString(),
                        'headers': {
                          if (s['referer'] != null) 'Referer': s['referer'].toString(),
                          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                        }
                      });
                    }
                  }
                  
                  if (streamData['subtitles'] != null) {
                    final subs = streamData['subtitles'] as List<dynamic>;
                    for (var sub in subs) {
                      if (sub['url'] != null) {
                        allSubtitles.add({
                          'url': sub['url'].toString(),
                          'lang': '${sub['lang']?.toString() ?? 'Unknown'} ($providerName)',
                        });
                      }
                    }
                  }
                } else {
                  print("Aggregator: Miruro stream body ($providerName): ${streamRes.body}");
                }
              } catch (e) {
                print("Aggregator: Miruro error fetching stream from $providerName: $e");
              }
            }
            
            if (allStreams.isNotEmpty) {
              print("Aggregator: Returning from Miruro: ${allStreams.length} qualities aggregated from multiple providers. Dub: $overallHasDub, Sub: $overallHasSub");
              return {
                'streams': allStreams,
                'url': allStreams.first['url'], // Fallback legacy
                'headers': allStreams.first['headers'], // Fallback legacy
                'hasSub': overallHasSub,
                'hasDub': overallHasDub,
                'subtitles': allSubtitles,
              };
            }
            
            print("Aggregator: Miruro exhausted all providers, no valid stream found.");
            
          } else {
             print("Aggregator: Miruro episodes body: ${epRes.body}");
          }
        }
      } else {
        print("Miruro API Error: Status Code ${anilistRes.statusCode} Body: ${anilistRes.body}");
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
