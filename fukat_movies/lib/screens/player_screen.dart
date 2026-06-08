import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/remote_config_service.dart';
import '../services/tmdb_service.dart';
import '../services/ad_block_service.dart';
import '../services/streaming_aggregator_service.dart';
import '../widgets/episode_side_panel.dart';
import '../services/continue_watching_service.dart';

class PlayerScreen extends StatefulWidget {
  final String tmdbId;
  final bool isMovie;
  final String title;

  PlayerScreen({
    required this.tmdbId,
    required this.isMovie,
    required this.title,
  });

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  InAppWebViewController? webViewController;
  int currentProviderIndex = 0;
  String? currentImdbId;
  bool isInitializing = true;
  String currentUrl = "";
  String currentSeason = "1";
  String currentEpisode = "1";
  bool _isPlaying = false;
  String _bannerUrl =
      'https://via.placeholder.com/800x450'; // Placeholder, you can update with real TMDB backdrop
  // New state for dynamic season lists
  List<String> _seasons = [];
  // GlobalKey prevents the WebView from being destroyed when rotating the phone
  final GlobalKey _playerKey = GlobalKey();

  // Native Player State
  Player? _mediaPlayer;
  VideoController? _videoController;
  Map<String, String>? currentHeaders;
  List<Map<String, dynamic>> _availableQualities = [];
  List<SubtitleTrack> _embeddedSubtitles = [];
  String? _selectedQuality;
  SubtitleTrack _selectedSubtitleTrack = SubtitleTrack.no();
  bool _isDub = false;
  bool _hasDubAvailable = false;
  bool _isMappingEpisode = false;
  String _currentEngine = 'webview';

  @override
  void initState() {
    super.initState();
    _initializePlaybackData();
  }

  @override
  void dispose() {
    _mediaPlayer?.dispose();
    super.dispose();
  }

  Future<void> _initializePlaybackData() async {
    // Fetch IMDB ID since some providers require it
    final imdbId = await TmdbService.getImdbId(
      int.parse(widget.tmdbId),
      widget.isMovie,
    );

    // Attempt to get banner/backdrop and season data if series
    if (!widget.isMovie) {
      final seriesData = await TmdbService.getSeriesDetails(
        int.parse(widget.tmdbId),
      );
      if (seriesData != null && seriesData['backdrop_path'] != null) {
        _bannerUrl =
            'https://image.tmdb.org/t/p/w1280${seriesData['backdrop_path']}';
      }
      // Load seasons list only
      if (seriesData != null && seriesData['seasons'] != null) {
        final seasonList = seriesData['seasons'] as List<dynamic>;
        List<String> seasons = [];
        for (var season in seasonList) {
          seasons.add(season['season_number'].toString());
        }
        setState(() {
          _seasons = seasons;
          if (_seasons.isNotEmpty) {
            currentSeason = _seasons.first;
          }
        });
      }
    } else {
      // Movie banner logic could be added here
    }

    setState(() {
      currentImdbId =
          imdbId ?? widget.tmdbId; // Fallback to TMDB if IMDB not found
      isInitializing = false;
      _preparePlaybackUrl();
    });
  }

  Future<void> _preparePlaybackUrl() async {
    final providersList = RemoteConfigService.activeProviders;
    if (currentProviderIndex >= providersList.length) {
      setState(() {
        currentUrl = "";
        currentHeaders = null;
      });
      return;
    }

    var activeProvider = providersList[currentProviderIndex];
    _currentEngine = activeProvider['engine'] ?? 'webview';

    setState(() {
      _isMappingEpisode = _currentEngine.startsWith('native_');
    });

    final playbackData = await _buildPlaybackUrl(activeProvider);

    if (!mounted) return;

    setState(() {
      _isMappingEpisode = false;
    });

    if (playbackData == null || playbackData['url'] == null) {
      _triggerFailover();
    } else {
      setState(() {
        currentUrl = playbackData['url'] as String;
        if (playbackData['headers'] != null) {
          currentHeaders = Map<String, String>.from(playbackData['headers'] as Map);
        } else {
          currentHeaders = null;
        }

        if (playbackData['streams'] != null) {
          try {
            _availableQualities = List<Map<String, dynamic>>.from(playbackData['streams']);
            if (_availableQualities.isNotEmpty) {
              _selectedQuality = _availableQualities.first['quality']?.toString();
            }
          } catch (e) {
            print("Error parsing streams: $e");
          }
        } else {
          _availableQualities = [];
          _selectedQuality = null;
        }

        _selectedSubtitleTrack = SubtitleTrack.no(); // Reset subtitle on new video load
        _hasDubAvailable = playbackData['hasDub'] == true;
      });
      if (_isPlaying) {
        if (_currentEngine == 'webview' && webViewController != null) {
          webViewController!.loadUrl(
            urlRequest: URLRequest(url: WebUri(currentUrl)),
          );
        } else if (_currentEngine.startsWith('native_')) {
          _initializeNativePlayer(currentUrl, headers: currentHeaders);
        }
      }
    }
  }

  Future<void> _initializeNativePlayer(String url, {Map<String, String>? headers}) async {
    print("PlayerScreen: Initializing MediaKit player with URL: $url");
    
    _mediaPlayer?.dispose();

    _mediaPlayer = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 1024 * 1024 * 32, // 32MB buffer for fast seeking
      ),
    );

    _videoController = VideoController(_mediaPlayer!);

    _mediaPlayer!.stream.tracks.listen((tracks) {
      if (mounted) {
        setState(() {
          // Filter out the 'no()' track if it's in the list, we add it manually
          _embeddedSubtitles = tracks.subtitle.where((t) => t.id != 'no' && t.id != 'auto').toList();
        });
      }
    });

    await _mediaPlayer!.open(
      Media(url, httpHeaders: headers),
      play: true,
    );

    setState(() {});
  }

  void _changeQuality(Map<String, dynamic> stream) async {
    if (_mediaPlayer == null) return;
    
    final position = _mediaPlayer!.state.position;
    
    setState(() {
      _selectedQuality = stream['quality'];
      currentUrl = stream['url'];
      if (stream['headers'] != null) {
        currentHeaders = Map<String, String>.from(stream['headers']);
      }
    });

    await _mediaPlayer!.open(
      Media(currentUrl, httpHeaders: currentHeaders),
      play: true,
    );
    await _mediaPlayer!.seek(position);
  }

  void _changeSubtitle(SubtitleTrack track) {
    if (_mediaPlayer == null) return;
    
    setState(() {
      _selectedSubtitleTrack = track;
    });

    _mediaPlayer!.setSubtitleTrack(track);
  }

  Future<Map<String, dynamic>?> _buildPlaybackUrl(Map<String, dynamic> provider) async {
    final String engine = provider['engine'] ?? 'webview';
    
    if (engine.startsWith('native_')) {
      if (widget.isMovie) return null; // These aggregators are mostly anime (TV)
      return await StreamingAggregatorService.getNativeStreamingUrl(
        title: widget.title,
        engine: engine,
        season: int.tryParse(currentSeason) ?? 1,
        episodeNumber: int.tryParse(currentEpisode) ?? 1,
        isDub: _isDub,
      );
    }

    final String idType = provider['id_type'];
    final String formatStyle = provider['format_style'];
    final String baseUrl = widget.isMovie
        ? provider['movie_url']
        : provider['tv_url'];

    // 1. Resolve Core Identifier Type (Convert TMDB to IMDb if requested)
    String targetId = widget.tmdbId.toString();
    if (idType == 'imdb') {
      final imdbId = await TmdbService.getImdbId(
        int.parse(widget.tmdbId),
        widget.isMovie,
      );
      if (imdbId == null || imdbId.isEmpty)
        return null; // Abort provider if translation fails
      targetId = imdbId;
    }

    // 2. Compile URL based on Format Styles
    String finalUrl = '';
    if (widget.isMovie) {
      if (formatStyle == 'slash' || formatStyle == 'query_mix') {
        finalUrl = '$baseUrl$targetId';
      } else if (formatStyle == 'query') {
        finalUrl = '$baseUrl$targetId';
      } else if (formatStyle == 'dash') {
        finalUrl = '$baseUrl$targetId';
      } else {
        finalUrl = '$baseUrl$targetId'; // Fallback for movies
      }
    } else {
      // TV Show Format Implementations
      switch (formatStyle) {
        case 'slash': // Videasy & NontonGo Style: base/tv/id/season/episode
          finalUrl = '$baseUrl$targetId/$currentSeason/$currentEpisode';
          break;
        case 'query': // VidSrcMe RU Style: base/tv?imdb=id&s=season&e=episode
          finalUrl = '$baseUrl$targetId&s=$currentSeason&e=$currentEpisode';
          break;
        case 'query_mix': // 2Embed Style: base/id&s=season&e=episode
          finalUrl = '$baseUrl$targetId&s=$currentSeason&e=$currentEpisode';
          break;
        case 'dash': // AutoEmbed Style: base/id-season-episode
          finalUrl = '$baseUrl$targetId-$currentSeason-$currentEpisode';
          break;
        default:
          finalUrl = '$baseUrl$targetId/$currentSeason/$currentEpisode'; // Fallback
      }
    }
    return {'url': finalUrl};
  }

  void _startPlayback() {
    setState(() {
      _isPlaying = true;
    });

    if (currentUrl.isNotEmpty) {
      if (_currentEngine == 'webview' && webViewController != null) {
        webViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(currentUrl)),
        );
      } else if (_currentEngine.startsWith('native_')) {
        _initializeNativePlayer(currentUrl, headers: currentHeaders);
      }
    }

    ContinueWatchingService.saveItem(
      tmdbId: widget.tmdbId,
      title: widget.title,
      posterPath: null,
      isMovie: widget.isMovie,
      lastSeason: widget.isMovie ? null : int.tryParse(currentSeason),
      lastEpisode: widget.isMovie ? null : int.tryParse(currentEpisode),
    );
  }

  void _triggerFailover() {
    print("Provider failed, triggering failover to next provider...");
    setState(() {
      currentProviderIndex++;
    });
    _preparePlaybackUrl();
  }

  Widget _buildVideoPlayerArea() {
    if (currentProviderIndex >= RemoteConfigService.activeProviders.length) {
      return Center(
        child: Text(
          "No streams available.",
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    if (_isMappingEpisode) {
      return Stack(
        alignment: Alignment.center,
        children: [
          CachedNetworkImage(
            imageUrl: _bannerUrl,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            color: Colors.black54,
            colorBlendMode: BlendMode.darken,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.redAccent),
              SizedBox(height: 16),
              Text(
                "Searching for anime stream...",
                style: TextStyle(color: Colors.white),
              ),
            ],
          )
        ],
      );
    }

    if (!_isPlaying) {
      return Stack(
        alignment: Alignment.center,
        children: [
          CachedNetworkImage(
            imageUrl: _bannerUrl,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            placeholder: (context, url) => Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
            ),
            errorWidget: (context, url, error) =>
                Icon(Icons.broken_image, size: 64, color: Colors.grey),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black87],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: _startPlayback,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8A2BE2).withOpacity(0.8),
                ),
                child: const Icon(
                  Icons.play_arrow,
                  size: 64,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_currentEngine.startsWith('native_')) {
      if (_videoController != null) {
        return Stack(
          children: [
            Container(
              color: Colors.black,
              child: Video(
                controller: _videoController!,
                controls: MaterialVideoControls,
              ),
            ),
            if (_availableQualities.length > 1 || _embeddedSubtitles.isNotEmpty)
              Positioned(
                top: 16,
                right: 16,
                child: SafeArea(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_embeddedSubtitles.isNotEmpty)
                        PopupMenuButton<SubtitleTrack>(
                          icon: const Icon(Icons.closed_caption, color: Colors.white),
                          color: Colors.grey[900],
                          onSelected: (track) {
                            _changeSubtitle(track);
                          },
                          itemBuilder: (context) {
                            List<PopupMenuEntry<SubtitleTrack>> items = [];
                            
                            items.add(
                              PopupMenuItem<SubtitleTrack>(
                                value: SubtitleTrack.no(),
                                child: Text(
                                  'Off',
                                  style: TextStyle(
                                    color: _selectedSubtitleTrack.id == 'no' ? Colors.redAccent : Colors.white,
                                    fontWeight: _selectedSubtitleTrack.id == 'no' ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );

                            items.addAll(_embeddedSubtitles.map((sub) {
                              return PopupMenuItem<SubtitleTrack>(
                                value: sub,
                                child: Text(
                                  sub.language ?? sub.title ?? sub.id,
                                  style: TextStyle(
                                    color: _selectedSubtitleTrack.id == sub.id ? Colors.redAccent : Colors.white,
                                    fontWeight: _selectedSubtitleTrack.id == sub.id ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              );
                            }));
                            
                            return items;
                          },
                        ),
                      if (_availableQualities.length > 1)
                        PopupMenuButton<dynamic>(
                          icon: const Icon(Icons.settings, color: Colors.white),
                          color: Colors.grey[900],
                    onSelected: (value) {
                      if (value == 'sub') {
                        if (_isDub) {
                          setState(() { _isDub = false; });
                          _preparePlaybackUrl();
                        }
                      } else if (value == 'dub') {
                        if (!_isDub) {
                          setState(() { _isDub = true; });
                          _preparePlaybackUrl();
                        }
                      } else if (value is Map<String, dynamic>) {
                        _changeQuality(value);
                      }
                    },
                    itemBuilder: (context) {
                      List<PopupMenuEntry<dynamic>> items = [];
                      
                      if (_availableQualities.isNotEmpty) {
                        items.addAll(_availableQualities.map((stream) {
                          return PopupMenuItem<dynamic>(
                            value: stream,
                            child: Text(
                              stream['quality'] ?? 'Auto',
                              style: TextStyle(
                                color: _selectedQuality == stream['quality']
                                    ? Colors.redAccent
                                    : Colors.white,
                                fontWeight: _selectedQuality == stream['quality']
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        }));
                      }
                      return items;
                    },
                  ),
                ],
              ),
                ),
              ),
          ],
        );
      } else {
        return Center(
          child: CircularProgressIndicator(color: Colors.redAccent),
        );
      }
    }

    return Stack(
      children: [
        // LAYER 1: Core Web Rendering Viewport
        InAppWebView(
          initialUrlRequest: currentUrl.isNotEmpty
              ? URLRequest(url: WebUri(currentUrl))
              : null,
          initialSettings: InAppWebViewSettings(
            mediaPlaybackRequiresUserGesture: false,
            javaScriptEnabled: true,
            supportZoom: false,
            disableContextMenu: true,
            useShouldOverrideUrlLoading: true,
            javaScriptCanOpenWindowsAutomatically: false,
            supportMultipleWindows: false,
            userAgent:
                "Mozilla/5.0 (Linux; Android 13; SM-S911B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36",
            allowsInlineMediaPlayback: true,
            iframeAllowFullscreen: true,
            thirdPartyCookiesEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          ),
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              source: "",
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
              forMainFrameOnly: false, // Injects into all nested iframes!
            ),
          ]),
          onWebViewCreated: (controller) {
            webViewController = controller;
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            var url = navigationAction.request.url?.toString() ?? '';
            if (navigationAction.isForMainFrame) {
              bool blocked = await AdBlockService.isAdDomain(url);
              if (blocked) {
                print('Blocked navigation to ad domain: $url');
                return NavigationActionPolicy.CANCEL;
              }
            }
            return NavigationActionPolicy.ALLOW;
          },
          onLoadStop: (controller, url) async {
            if (url != null) {
              final script = await AdBlockService.getUiCleanerScript(
                url.toString(),
              );
              await controller.evaluateJavascript(source: script);
              await Future.delayed(const Duration(milliseconds: 1500));
              await controller.evaluateJavascript(source: script);
            }
          },
          onReceivedError: (controller, request, error) {
            print(
              "WebView Error: ${error.description} for URL: ${request.url}",
            );
            // We disabled automatic failover here because ad-blockers canceling
            // popups often trigger harmless 'net::ERR_ABORTED' errors.
          },
          onReceivedHttpError: (controller, request, errorResponse) {
            print(
              "WebView HTTP Error: ${errorResponse.statusCode} for URL: ${request.url}",
            );
            // Disabled automatic failover for HTTP errors as well to prevent false positives.
          },
        ),
      ],
    );
  }

  Widget _buildServerSelector() {
    final providers = RemoteConfigService.activeProviders;
    if (providers.isEmpty) return SizedBox.shrink();

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.dns, color: Colors.white70, size: 20),
          SizedBox(width: 8),
          Text(
            "Server:",
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                dropdownColor: Colors.grey[900],
                value: currentProviderIndex < providers.length
                    ? currentProviderIndex
                    : null,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                items: List.generate(providers.length, (index) {
                  return DropdownMenuItem<int>(
                    value: index,
                    child: Text(
                      'Server ${index + 1}: ${providers[index]['name']}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }),
                onChanged: (int? newIndex) {
                  if (newIndex != null && newIndex != currentProviderIndex) {
                    setState(() {
                      currentProviderIndex = newIndex;
                      _isPlaying = false;
                      webViewController = null;
                      _preparePlaybackUrl();
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSection() {
    return Container(
      key: _playerKey,
      child: Column(
        children: [
          Flexible(child: _buildVideoPlayerArea()),
          _buildServerSelector(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isInitializing) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth > 700;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: isWide
          ? null
          : AppBar(
              title: Text(
                widget.title,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              backgroundColor: Colors.black,
              iconTheme: IconThemeData(color: Colors.white),
            ),
      body: SafeArea(
        child: isWide
            ? Row(
                children: [
                  // Left Side: Player Section (Takes maximum space)
                  Expanded(flex: 3, child: _buildPlayerSection()),
                  // Right Side: Episode Picker (Pinned to the right)
                  if (!widget.isMovie)
                    Container(
                      width: 320,
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: Colors.white12, width: 1),
                        ),
                      ),
                      child: EpisodeSidePanel(
                        tmdbId: widget.tmdbId,
                        currentSeason: currentSeason,
                        currentEpisode: currentEpisode,
                        seasons: _seasons,
                        onEpisodeSelected: (season, episode) {
                          setState(() {
                            currentSeason = season;
                            currentEpisode = episode;
                            currentProviderIndex = 0;
                            _isPlaying = false;
                            webViewController = null;
                          });
                          _preparePlaybackUrl().then((_) {
                            _startPlayback();
                          });
                        },
                        isDub: _isDub,
                        hasDub: _hasDubAvailable,
                        onAudioChanged: (isDub) {
                          if (_isDub != isDub) {
                            setState(() {
                              _isDub = isDub;
                            });
                            _preparePlaybackUrl();
                          }
                        },
                      ),
                    ),
                ],
              )
            : Column(
                children: [
                  // Top Side: Player Section
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.45,
                    width: double.infinity,
                    child: _buildPlayerSection(),
                  ),
                  // Bottom Side: Episode Picker (if not a movie)
                  if (!widget.isMovie)
                    Expanded(
                      child: EpisodeSidePanel(
                        tmdbId: widget.tmdbId,
                        currentSeason: currentSeason,
                        currentEpisode: currentEpisode,
                        seasons: _seasons,
                        onEpisodeSelected: (season, episode) {
                          setState(() {
                            currentSeason = season;
                            currentEpisode = episode;
                            currentProviderIndex = 0;
                            _isPlaying = false;
                            webViewController = null;
                          });
                          _preparePlaybackUrl().then((_) {
                            _startPlayback();
                          });
                        },
                        isDub: _isDub,
                        hasDub: _hasDubAvailable,
                        onAudioChanged: (isDub) {
                          if (_isDub != isDub) {
                            setState(() {
                              _isDub = isDub;
                            });
                            _preparePlaybackUrl();
                          }
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
