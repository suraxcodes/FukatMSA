import 'dart:convert';
import 'package:http/http.dart' as http;
import 'remote_config_service.dart';
import 'miruro_scraper_service.dart';

class StreamingAggregatorService {
  static String get proxifyStreamsUrl => RemoteConfigService.remoteEnv['PROXIFY_STREAMS_URL'] ?? 'https://proxify-streamsmsa.onrender.com';
  static String get omssApiUrl => RemoteConfigService.remoteEnv['OMSS_API_URL'] ?? 'http://127.0.0.1:3000'; // Replace with deployed backend URL later
  static String get flyxApiUrl => RemoteConfigService.remoteEnv['FLYX_API_URL'] ?? 'http://127.0.0.1:3001';

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
    print("Aggregator: Resolving $title (S$season E$episodeNumber) via $engine");

    if (engine == 'native_omss' && tmdbId != null) {
      return await _getOmssStream(tmdbId, isMovie, season, episodeNumber);
    } else if (engine == 'native_flyx' && tmdbId != null) {
      return await _getFlyxStream(tmdbId, isMovie, season, episodeNumber, isDub);
    } else if (engine == 'native_miruro') {
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
          
          try {
            // 2. Fetch episodes list from Miruro natively
            print("Aggregator: Miruro fetching episodes list natively");
            
            final epData = await MiruroScraperService.fetchRawEpisodes(anilistId);
            
            if (epData != null) {
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
                
                try {
                  final streamData = await MiruroScraperService.fetchStreamSources(
                    targetWatchId!,
                    providerName,
                    isDub ? 'dub' : 'sub', // But we might have fallen back, need to be careful
                    anilistId
                  );
                  
                  if (streamData != null) {
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
               print("Aggregator: Miruro native extraction returned null");
            }
          } catch (e) {
            print("Aggregator: Error with Miruro Scraper: $e");
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

  static Future<Map<String, dynamic>?> _getOmssStream(String tmdbId, bool isMovie, int season, int episode) async {
    try {
      final url = isMovie 
          ? Uri.parse('$omssApiUrl/v1/movies/$tmdbId')
          : Uri.parse('$omssApiUrl/v1/tv/$tmdbId/seasons/$season/episodes/$episode');

      print("Aggregator: Fetching OMSS stream from $url");
      final response = await http.get(url).timeout(const Duration(seconds: 40));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final sources = data['sources'] as List<dynamic>? ?? [];

        if (sources.isNotEmpty) {
          List<Map<String, dynamic>> allStreams = sources.map((s) {
            String streamUrl = s['url'].toString();
            Map<String, String> finalHeaders = {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            };

            // BYPASS OMSS PROXY FOR FLUTTER: native players don't need CORS bypass
            // and going through the proxy breaks video `Range: bytes=0-` headers
            if (streamUrl.contains('/v1/proxy?data=')) {
              try {
                final uri = Uri.parse(streamUrl.startsWith('/v1') ? '$omssApiUrl$streamUrl' : streamUrl);
                final dataStr = uri.queryParameters['data'];
                if (dataStr != null) {
                  final decoded = json.decode(dataStr);
                  if (decoded['url'] != null) {
                    streamUrl = decoded['url'].toString();
                    if (decoded['headers'] != null) {
                      final Map<String, dynamic> proxyHeaders = decoded['headers'];
                      proxyHeaders.forEach((k, v) {
                        if (v != null && v.toString().isNotEmpty) {
                          finalHeaders[k] = v.toString();
                        }
                      });
                    }
                  }
                }
              } catch (e) {
                print("Failed to unwrap OMSS proxy URL: $e");
                if (streamUrl.startsWith('/v1')) streamUrl = '$omssApiUrl$streamUrl';
              }
            } else if (streamUrl.startsWith('/v1')) {
              streamUrl = '$omssApiUrl$streamUrl';
            }

            return {
              'quality': '${s['quality'] ?? 'Auto'} (${s['name'] ?? 'OMSS'})',
              'url': streamUrl,
              'headers': finalHeaders
            };
          }).toList();

          return {
            'streams': allStreams,
            'url': allStreams.first['url'],
            'headers': allStreams.first['headers'],
            'hasSub': true,
            'hasDub': true,
            'subtitles': [], 
          };
        }
      } else {
        print("Aggregator: OMSS failed with status ${response.statusCode}");
      }
    } catch (e) {
      print("OMSS API Error: $e");
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _getFlyxStream(String tmdbId, bool isMovie, int season, int episode, bool isDub) async {
    try {
      final url = isMovie 
          ? Uri.parse('$flyxApiUrl/api/stream/extract?tmdbId=$tmdbId&type=movie')
          : Uri.parse('$flyxApiUrl/api/stream/extract?tmdbId=$tmdbId&type=tv&season=$season&episode=$episode');

      print("✅ [Flyx Aggregator] Fetching Flyx stream from $url");
      final response = await http.get(url).timeout(const Duration(seconds: 40));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final sources = data['sources'] as List<dynamic>? ?? [];
        
        print("✅ [Flyx Aggregator] SUCCESS (200 OK) - Found ${sources.length} stream(s)");

        if (sources.isNotEmpty) {
          List<Map<String, dynamic>> allStreams = sources.map((s) {
            String qualityLabel = '${s['quality'] ?? 'Auto'} (${s['title'] ?? 'Flyx'})';
            if (s['language'] != null) {
              qualityLabel += ' [${s['language'].toString().toUpperCase()}]';
            }
            
            // We MUST use the local proxy to bypass ISP blocking.
            // 1. If we use directUrl, the ISP in India blocks the TikTok CDN video segments.
            // 2. If we use the Cloudflare proxy (s['url']), Cloudflare blocks the master playlist fetch (403).
            // 3. Solution: Use localhost proxy. Local proxy fetches master playlist (succeeds via residential IP),
            //    and rewrites segment URLs to use Cloudflare proxy (succeeds bypassing ISP block).
            String rawDirectUrl = s['directUrl'] != null ? s['directUrl'].toString() : s['url'].toString();
            String referer = s['referer'] != null ? s['referer'].toString() : 'https://hexa.su/';
            String streamUrl = '$flyxApiUrl/api/stream-proxy?url=${Uri.encodeComponent(rawDirectUrl)}&referer=${Uri.encodeComponent(referer)}';
            
            print("🎥 [Flyx Aggregator] Stream parsed: $qualityLabel -> URL: $streamUrl");
            
            return {
              'quality': qualityLabel,
              'url': streamUrl,
              'language': s['language']?.toString().toLowerCase(),
              'headers': {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                if (s['referer'] != null) 'Referer': s['referer'].toString(),
                if (s['referer'] != null) 'Origin': s['referer'].toString(),
              }
            };
          }).toList();
          
          // Sort streams so that if isDub is true, dub streams appear first
          allStreams.sort((a, b) {
            bool aIsDub = a['quality'].toString().toLowerCase().contains('dub') || a['language'] == 'en';
            bool bIsDub = b['quality'].toString().toLowerCase().contains('dub') || b['language'] == 'en';
            
            if (isDub) {
              if (aIsDub && !bIsDub) return -1;
              if (!aIsDub && bIsDub) return 1;
            } else {
              if (!aIsDub && bIsDub) return -1;
              if (aIsDub && !bIsDub) return 1;
            }
            return 0;
          });
          
          print("✅ [Flyx Aggregator] Returning ${allStreams.length} processed streams back to player!");

          return {
            'streams': allStreams,
            'url': allStreams.first['url'],
            'headers': allStreams.first['headers'],
            'hasSub': true,
            'hasDub': true,
            'subtitles': [], 
          };
        } else {
           print("❌ [Flyx Aggregator] Response returned 0 sources.");
        }
      } else {
        print("❌ [Flyx Aggregator] Flyx failed with status ${response.statusCode}");
        print("❌ [Flyx Aggregator] Error body: ${response.body}");
      }
    } catch (e) {
      print("❌ [Flyx Aggregator] API Exception: $e");
    }
    return null;
  }
}
