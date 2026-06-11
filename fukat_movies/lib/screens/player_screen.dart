import 'dart:collection';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:window_manager/window_manager.dart';
import '../services/remote_config_service.dart';
import '../services/tmdb_service.dart';
import '../services/ad_block_service.dart';
import '../services/streaming_aggregator_service.dart';
import '../services/network_service.dart';
import '../widgets/episode_side_panel.dart';
import '../services/continue_watching_service.dart';
import '../widgets/watchlist_icon_button.dart';

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
  // UI State
  bool _showControls = true;
  bool _isFirstSubtitleLoad = true;
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
  List<Map<String, dynamic>> _apiSubtitles = [];
  String? _selectedQuality;
  SubtitleTrack _selectedSubtitleTrack = SubtitleTrack.no();
  bool _isDub = false;
  bool _hasDubAvailable = false;
  bool _isMappingEpisode = false;
  String _currentEngine = 'webview';
  bool _userForcedQuality = false;
  StreamSubscription<NetworkSpeed>? _networkSub;

  @override
  void initState() {
    super.initState();
    NetworkService().initialize();
    _networkSub = NetworkService().onSpeedChange.listen((speed) {
      if (mounted) _handleNetworkSpeedChange(speed);
    });
    _initializePlaybackData();
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    _saveProgress();
    _mediaPlayer?.dispose();
    super.dispose();
  }

  void _saveProgress() {
    if (_mediaPlayer == null) return;
    try {
      final position = _mediaPlayer!.state.position.inSeconds;
      final duration = _mediaPlayer!.state.duration.inSeconds;

      bool isCompleted = false;
      if (duration > 0 && position >= duration * 0.9) {
        isCompleted = true; // Mark as watched if 90% completed
      }

      ContinueWatchingService.saveItem(
        tmdbId: widget.tmdbId,
        title: widget.title,
        posterPath: null,
        isMovie: widget.isMovie,
        lastSeason: widget.isMovie ? null : int.tryParse(currentSeason),
        lastEpisode: widget.isMovie ? null : int.tryParse(currentEpisode),
        position: position,
        duration: duration,
        isCompleted: isCompleted,
      );
    } catch (e) {
      print('Error saving progress: $e');
    }
  }

  void _handleNetworkSpeedChange(NetworkSpeed speed) {
    if (_mediaPlayer == null || _availableQualities.isEmpty) return;

    // User explicitly chose a quality, don't override them
    if (_userForcedQuality) return;

    if (speed == NetworkSpeed.slow) {
      // Find a lower quality stream (e.g. 360p or 480p)
      final lowQualityStream = _availableQualities.firstWhere(
        (s) =>
            s['quality'] == '360p' ||
            s['quality'] == '480p' ||
            s['quality'].toString().contains('360') ||
            s['quality'].toString().contains('480'),
        orElse: () =>
            _availableQualities.last, // Usually last is lowest if sorted
      );

      if (_selectedQuality != lowQualityStream['quality']) {
        Fluttertoast.showToast(msg: "Network slow, adjusting quality");
        _changeQuality(lowQualityStream, isAuto: true);
      }
    }
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
        final now = DateTime.now();
        for (var season in seasonList) {
          final sNum = season['season_number'];
          if (sNum != null && sNum > 0) {
            // Check air_date to avoid showing unreleased seasons
            final airDateStr = season['air_date'];
            if (airDateStr != null) {
              try {
                final airDate = DateTime.parse(airDateStr);
                if (airDate.isAfter(now)) continue;
              } catch (_) {}
            }
            seasons.add(sNum.toString());
          }
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
          currentHeaders = Map<String, String>.from(
            playbackData['headers'] as Map,
          );
        } else {
          currentHeaders = null;
        }

        if (playbackData['streams'] != null) {
          try {
            _availableQualities = List<Map<String, dynamic>>.from(
              playbackData['streams'],
            );
            if (_availableQualities.isNotEmpty) {
              _selectedQuality = _availableQualities.first['quality']
                  ?.toString();
            }
          } catch (e) {
            print("Error parsing streams: $e");
          }
        } else {
          _availableQualities = [];
          _selectedQuality = null;
        }

        if (playbackData['subtitles'] != null) {
          try {
            _apiSubtitles = List<Map<String, dynamic>>.from(
              playbackData['subtitles'],
            );
          } catch (e) {
            print("Error parsing API subtitles: $e");
          }
        } else {
          _apiSubtitles = [];
        }

        _selectedSubtitleTrack =
            SubtitleTrack.no(); // Reset subtitle on new video load
        _isFirstSubtitleLoad = true;
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

  Future<void> _initializeNativePlayer(
    String url, {
    Map<String, String>? headers,
  }) async {
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
          final subs = tracks.subtitle
              .where((t) => t.id != 'no' && t.id != 'auto')
              .toList();
          _embeddedSubtitles = subs;

          if (_isFirstSubtitleLoad && subs.isNotEmpty) {
            _isFirstSubtitleLoad = false;
            _mediaPlayer!.setSubtitleTrack(SubtitleTrack.no());
          }
        });
      }
    });

    await _mediaPlayer!.open(Media(url, httpHeaders: headers), play: true);

    setState(() {});
  }

  void _changeQuality(
    Map<String, dynamic> stream, {
    bool isAuto = false,
  }) async {
    if (_mediaPlayer == null) return;

    if (!isAuto) {
      _userForcedQuality =
          true; // User manually selected, disable auto-downgrade
    }

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
    // Restore the selected subtitle track when quality changes
    _mediaPlayer!.setSubtitleTrack(_selectedSubtitleTrack);

    await _mediaPlayer!.seek(position);
  }

  void _changeSubtitle(SubtitleTrack track) {
    if (_mediaPlayer == null) return;

    setState(() {
      _selectedSubtitleTrack = track;
    });

    _mediaPlayer!.setSubtitleTrack(track);
  }

  Future<Map<String, dynamic>?> _buildPlaybackUrl(
    Map<String, dynamic> provider,
  ) async {
    final String engine = provider['engine'] ?? 'webview';

    if (engine.startsWith('native_')) {
      if (widget.isMovie)
        return null; // These aggregators are mostly anime (TV)
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
          finalUrl =
              '$baseUrl$targetId/$currentSeason/$currentEpisode'; // Fallback
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
          ),
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
              child: MaterialVideoControlsTheme(
                normal: MaterialVideoControlsThemeData(
                  bottomButtonBar: [
                    IconButton(
                      icon: const Icon(Icons.replay_10, color: Colors.white),
                      onPressed: () {
                        if (_mediaPlayer != null) {
                          final pos = _mediaPlayer!.state.position;
                          _mediaPlayer!.seek(pos - const Duration(seconds: 10));
                        }
                      },
                    ),
                    MaterialPlayOrPauseButton(),
                    IconButton(
                      icon: const Icon(Icons.forward_10, color: Colors.white),
                      onPressed: () {
                        if (_mediaPlayer != null) {
                          final pos = _mediaPlayer!.state.position;
                          _mediaPlayer!.seek(pos + const Duration(seconds: 10));
                        }
                      },
                    ),
                    MaterialPositionIndicator(),
                    const Spacer(),
                    MaterialFullscreenButton(),
                  ],
                ),
                fullscreen: MaterialVideoControlsThemeData(
                  bottomButtonBar: [
                    IconButton(
                      icon: const Icon(Icons.replay_10, color: Colors.white),
                      onPressed: () {
                        if (_mediaPlayer != null) {
                          final pos = _mediaPlayer!.state.position;
                          _mediaPlayer!.seek(pos - const Duration(seconds: 10));
                        }
                      },
                    ),
                    MaterialPlayOrPauseButton(),
                    IconButton(
                      icon: const Icon(Icons.forward_10, color: Colors.white),
                      onPressed: () {
                        if (_mediaPlayer != null) {
                          final pos = _mediaPlayer!.state.position;
                          _mediaPlayer!.seek(pos + const Duration(seconds: 10));
                        }
                      },
                    ),
                    MaterialPositionIndicator(),
                    const Spacer(),
                    MaterialFullscreenButton(),
                  ],
                ),
                child: Video(
                  controller: _videoController!,
                  controls: MaterialVideoControls,
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
            javaScriptCanOpenWindowsAutomatically: true,
            supportMultipleWindows: true,
            userAgent:
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            allowsInlineMediaPlayback: true,
            iframeAllowFullscreen: true,
            thirdPartyCookiesEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          ),
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              source: """
                // Prevent all forms of Main Frame redirection
                window.onbeforeunload = function() { return "Prevent redirect"; };
                
                // Override location methods
                var originalAssign = window.location.assign;
                var originalReplace = window.location.replace;
                window.location.assign = function(url) { console.log("Blocked assign:", url); };
                window.location.replace = function(url) { console.log("Blocked replace:", url); };
                
                // Override window.open
                window.open = function(url, name, specs) { 
                  console.log("Mocked popup opened"); 
                  return { closed: false, focus: function(){}, close: function(){} }; 
                };
              """,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: false,
            ),
          ]),
          onWebViewCreated: (controller) {
            webViewController = controller;
          },
          onEnterFullscreen: (controller) async {
            FocusManager.instance.primaryFocus?.unfocus();
            await windowManager.setFullScreen(true);
          },
          onExitFullscreen: (controller) async {
            FocusManager.instance.primaryFocus?.unfocus();
            await windowManager.setFullScreen(false);
          },
          onCreateWindow: (controller, createWindowAction) async {
            // We return true to handle the window creation, but we DON'T actually
            // create or show a new window! This effectively swallows the popup
            // silently in the background, making the ad invisible.
            print("Swallowed popup window creation in background");
            return true;
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
      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: Colors.black, // Main row background matches app background
      child: Row(
        children: [
          Icon(Icons.dns, color: Colors.white70, size: 20),
          SizedBox(width: 8),
          Text(
            'Server:',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color.fromARGB(
                  255,
                  14,
                  13,
                  13,
                ), // Match user's black
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  dropdownColor: const Color.fromARGB(
                    255,
                    14,
                    13,
                    13,
                  ), // Match user's black
                  value: currentProviderIndex < providers.length
                      ? currentProviderIndex
                      : null,
                  isExpanded: true,
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.white70,
                  ),
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
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.fullscreen, color: Colors.white70),
            tooltip: 'Toggle Fullscreen',
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              bool isFull = await windowManager.isFullScreen();
              await windowManager.setFullScreen(!isFull);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSection() {
    return Container(key: _playerKey, child: _buildVideoPlayerArea());
  }

  Widget _buildSeriesInfo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              WatchlistIconButton(
                tmdbId: widget.tmdbId.toString(),
                title: widget.title,
                posterPath: _bannerUrl,
                isMovie: widget.isMovie,
                showText: true,
                text: 'SAVE',
              ),
              IconButton(
                icon: Column(
                  children: [
                    Icon(Icons.thumb_up_alt_outlined, color: Colors.white),
                    Text(
                      'RATE',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
                onPressed: () {},
              ),
            ],
          ),
          SizedBox(height: 8),
          if (!widget.isMovie)
            Text(
              'Season $currentSeason : Episode $currentEpisode',
              style: TextStyle(
                color: Colors.cyanAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          SizedBox(height: 12),
          Text(
            'In a world of magic where social standing is determined by arcane prowess...', // Placeholder synopsis
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreLikeThis() {
    return FutureBuilder<List<dynamic>>(
      future: widget.isMovie
          ? TmdbService.getSimilarMovies(int.parse(widget.tmdbId))
          : TmdbService.getSimilarTvShows(int.parse(widget.tmdbId)),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return SizedBox.shrink();
        final items = snapshot.data!;
        if (items.isEmpty) return SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "More Like This",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final posterPath = item['poster_path'];
                  final titleText = item['title'] ?? item['name'];
                  final tmdbId = item['id'].toString();

                  return GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlayerScreen(
                            tmdbId: tmdbId,
                            isMovie: widget.isMovie,
                            title: titleText,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 120,
                      margin: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: posterPath != null
                                ? Image.network(
                                    'https://image.tmdb.org/t/p/w500$posterPath',
                                    height: 160,
                                    width: 120,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    height: 160,
                                    width: 120,
                                    color: Colors.grey[800],
                                  ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            titleText,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsMenu() {
    return PopupMenuButton<dynamic>(
      icon: const Icon(Icons.settings, color: Colors.white),
      color: Colors.grey[900],
      onSelected: (value) {
        if (value == 'sub') {
          if (_isDub) {
            setState(() {
              _isDub = false;
            });
            _preparePlaybackUrl();
          }
        } else if (value == 'dub') {
          if (!_isDub) {
            setState(() {
              _isDub = true;
            });
            _preparePlaybackUrl();
          }
        } else if (value is Map<String, dynamic>) {
          _changeQuality(value);
        } else if (value is SubtitleTrack) {
          _changeSubtitle(value);
        } else if (value is String && value.startsWith('api_sub_')) {
          final url = value.replaceFirst('api_sub_', '');
          _changeSubtitle(SubtitleTrack.uri(url));
        }
      },
      itemBuilder: (context) {
        List<PopupMenuEntry<dynamic>> items = [];
        if (_availableQualities.isNotEmpty) {
          items.add(
            const PopupMenuItem<dynamic>(
              enabled: false,
              child: Text(
                'Quality',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
          items.addAll(
            _availableQualities.map((stream) {
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
            }),
          );

          items.add(const PopupMenuDivider());

          items.add(
            const PopupMenuItem<dynamic>(
              enabled: false,
              child: Text(
                'Subtitles (CC)',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );

          items.add(
            PopupMenuItem<dynamic>(
              value: SubtitleTrack.no(),
              child: Text(
                'Off',
                style: TextStyle(
                  color: _selectedSubtitleTrack.id == 'no'
                      ? Colors.redAccent
                      : Colors.white,
                  fontWeight: _selectedSubtitleTrack.id == 'no'
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          );

          items.addAll(
            _apiSubtitles.map((sub) {
              return PopupMenuItem<dynamic>(
                value: 'api_sub_${sub['url']}',
                child: Text(
                  sub['lang'] ?? 'Unknown',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              );
            }),
          );

          items.addAll(
            _embeddedSubtitles.map((sub) {
              return PopupMenuItem<dynamic>(
                value: sub,
                child: Text(
                  sub.language ?? sub.title ?? sub.id,
                  style: TextStyle(
                    color: _selectedSubtitleTrack.id == sub.id
                        ? Colors.redAccent
                        : Colors.white,
                    fontWeight: _selectedSubtitleTrack.id == sub.id
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              );
            }),
          );
        }
        return items;
      },
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
    final bool isWide = false; // Force mobile layout everywhere

    return Scaffold(
      backgroundColor: Color(0xFF141414), // Dark background matching design
      appBar: isWide
          ? null
          : AppBar(
              title: Text(
                widget.title,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              backgroundColor: Colors.black,
              iconTheme: IconThemeData(color: Colors.white),
              actions: [
                if (_availableQualities.isNotEmpty) _buildSettingsMenu(),
              ],
            ),
      body: SafeArea(
        child: isWide
            ? Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: _buildPlayerSection(),
                          ),
                          _buildServerSelector(),
                          _buildSeriesInfo(),
                          _buildMoreLikeThis(),
                        ],
                      ),
                    ),
                  ),
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
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _buildPlayerSection(),
                    ),
                    _buildServerSelector(),
                    if (!widget.isMovie)
                      EpisodeSidePanel(
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
                    _buildSeriesInfo(),
                    _buildMoreLikeThis(),
                  ],
                ),
              ),
      ),
    );
  }
}
