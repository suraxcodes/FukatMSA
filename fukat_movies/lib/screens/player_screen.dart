import 'dart:collection';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../services/remote_config_service.dart';
import '../services/tmdb_service.dart';
import '../services/ad_block_service.dart';
import '../services/streaming_aggregator_service.dart';
import '../services/network_service.dart';
import '../widgets/episode_side_panel.dart';
import '../services/continue_watching_service.dart';
import '../widgets/watchlist_icon_button.dart';

// Helper to set fullscreen on both desktop and mobile
Future<void> _setFullScreen(bool enable) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Desktop: use window_manager
    if (enable) {
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
    }
  } else {
    // Mobile: use SystemChrome immersive mode
    if (enable) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}

// In the button callback replace direct windowManager calls with _setFullScreen
// Example usage inside the UI builder:
// onTap: () async {
//   bool isFull = Platform.isWindows || Platform.isLinux || Platform.isMacOS
//       ? await windowManager.isFullScreen()
//       : MediaQuery.of(context).padding.top == 0; // rough mobile check
//   await _setFullScreen(!isFull);
// },



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

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  // UI State
  bool _isDesktopFullscreen = false;
  bool _showControls = true;
  bool _isFirstSubtitleLoad = true;
  InAppWebViewController? webViewController;
  HeadlessInAppWebView? headlessWebView;
  bool _isExtracting = false;
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
  bool _hasSubAvailable = true;
  bool _isMappingEpisode = false;
  String _currentEngine = 'webview';
  bool _userForcedQuality = false;
  Timer? _autoQualityTimer;
  StreamSubscription<NetworkSpeed>? _networkSub;
  Map<String, dynamic>? _mediaDetails;
  
  // Headless Extractor State
  List<String> _extractedSubtitles = [];
  String? _extractedStreamUrl;
  Map<String, String>? _extractedStreamHeaders;
  Timer? _extractionTimer;
  Timer? _bufferingTimer;
  Duration _lastPlaybackPosition = Duration.zero;
  bool _hasRestoredPosition = false;

  @override
  void initState() {
    super.initState();
    StreamingAggregatorService.preferredProvider = null; // Reset preferred provider for new anime session
    windowManager.addListener(this);
    NetworkService().initialize();
    _networkSub = NetworkService().onSpeedChange.listen((speed) {
      if (mounted) _handleNetworkSpeedChange(speed);
    });
    if (!widget.isMovie) {
      _hasDubAvailable = true;
    }
    _initializePlaybackData();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    headlessWebView?.dispose();
    _networkSub?.cancel();
    _autoQualityTimer?.cancel();
    _extractionTimer?.cancel();
    _bufferingTimer?.cancel();
    _saveProgress();
    _mediaPlayer?.dispose();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) {
      setState(() {
        _isDesktopFullscreen = true;
      });
    }
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) {
      setState(() {
        _isDesktopFullscreen = false;
      });
    }
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

    // If speed drops significantly AFTER the timer, we auto-downgrade.
    if (speed == NetworkSpeed.slow) {
      _applyOptimalQualityForSpeed(speed);
    }
  }

  void _applyOptimalQualityForSpeed(NetworkSpeed speed) {
    if (_availableQualities.isEmpty) return;
    
    // Only auto-switch within the current provider to prevent accidental failovers
    String providerSuffix = "";
    if (_selectedQuality != null && _selectedQuality!.contains('(')) {
      providerSuffix = "(${_selectedQuality!.split('(').last.replaceAll(')', '').trim()})";
    }

    var providerStreams = _availableQualities;
    if (providerSuffix.isNotEmpty) {
      providerStreams = _availableQualities.where((s) => s['quality'].toString().contains(providerSuffix)).toList();
      if (providerStreams.isEmpty) providerStreams = _availableQualities;
    }
    
    Map<String, dynamic> targetStream;
    if (speed == NetworkSpeed.fast) {
      targetStream = providerStreams.first; // Usually highest
    } else if (speed == NetworkSpeed.moderate) {
      int midIndex = providerStreams.length ~/ 2;
      targetStream = providerStreams[midIndex]; // Medium quality
    } else {
      // Find lowest quality
      targetStream = providerStreams.firstWhere(
        (s) =>
            s['quality'].toString().contains('360') ||
            s['quality'].toString().contains('480'),
        orElse: () => providerStreams.last,
      );
    }

    if (_selectedQuality != targetStream['quality']) {
      Fluttertoast.showToast(msg: "Auto-adjusting video quality to ${targetStream['quality']} based on internet speed");
      _changeQuality(targetStream, isAuto: true);
    }
  }

  Future<void> _initializePlaybackData() async {
    // Fetch IMDB ID since some providers require it
    final imdbId = await TmdbService.getImdbId(
      int.parse(widget.tmdbId),
      widget.isMovie,
    );

    // Attempt to get full media details and banner/backdrop
    if (!widget.isMovie) {
      _mediaDetails = await TmdbService.getSeriesDetails(
        int.parse(widget.tmdbId),
      );
      if (_mediaDetails != null && _mediaDetails!['backdrop_path'] != null) {
        _bannerUrl =
            'https://image.tmdb.org/t/p/w1280${_mediaDetails!['backdrop_path']}';
      }
      // Load seasons list only
      if (_mediaDetails != null && _mediaDetails!['seasons'] != null) {
        final seasonList = _mediaDetails!['seasons'] as List<dynamic>;
        List<String> seasons = [];
        final now = DateTime.now();
        for (var season in seasonList) {
          final sNum = season['season_number'];
          if (sNum != null && sNum > 0) {
            final airDateStr = season['air_date'];
            if (airDateStr != null) {
              try {
                final airDate = DateTime.parse(airDateStr);
                if (airDate.isAfter(now.add(const Duration(days: 7)))) continue;
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
      _mediaDetails = await TmdbService.getMovieDetails(int.parse(widget.tmdbId));
      if (_mediaDetails != null && _mediaDetails!['backdrop_path'] != null) {
        _bannerUrl =
            'https://image.tmdb.org/t/p/w1280${_mediaDetails!['backdrop_path']}';
      }
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
              // 1. Always start playback with the top priority provider
              String topProviderSuffix = "";
              if (_availableQualities.first['quality'].toString().contains('(')) {
                topProviderSuffix = "(${_availableQualities.first['quality'].toString().split('(').last.replaceAll(')', '').trim()})";
              }

              var providerStreams = _availableQualities;
              if (topProviderSuffix.isNotEmpty) {
                providerStreams = _availableQualities.where((s) => s['quality'].toString().contains(topProviderSuffix)).toList();
              }

              final lowQualityStream = providerStreams.firstWhere(
                (s) => s['quality'].toString().contains('360') || s['quality'].toString().contains('480'),
                orElse: () => providerStreams.last,
              );
              _selectedQuality = lowQualityStream['quality']?.toString();
              currentUrl = lowQualityStream['url'] ?? currentUrl;
              if (lowQualityStream['headers'] != null) {
                currentHeaders = Map<String, String>.from(lowQualityStream['headers']);
              }
              _userForcedQuality = false; // Reset on new video
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
        _hasSubAvailable = playbackData['hasSub'] == true;
        
        // Auto-correct global _isDub state if the requested track doesn't exist
        if (_isDub && !_hasDubAvailable && _hasSubAvailable) {
          _isDub = false;
        } else if (!_isDub && !_hasSubAvailable && _hasDubAvailable) {
          _isDub = true;
        }
      });
      if (_isPlaying) {
        if (_currentEngine == 'webview' && webViewController != null) {
          webViewController!.loadUrl(
            urlRequest: URLRequest(url: WebUri(currentUrl)),
          );
        } else if (_currentEngine == 'native_extractor') {
          _startHeadlessExtractor(currentUrl);
        } else if (_currentEngine.startsWith('native_') && _currentEngine != 'native_extractor') {
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
    print("PlayerScreen: Headers: $headers");

    _mediaPlayer?.dispose();

    _mediaPlayer = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 1024 * 1024 * 32, // 32MB buffer for fast seeking
        logLevel: MPVLogLevel.debug,
      ),
    );

    _mediaPlayer!.stream.error.listen((error) {
      print("MediaKit Error: $error");
      if (mounted) {
        // Trigger failover if we hit an error opening the stream (e.g. DNS failure)
        _triggerFailover();
      }
    });
    
    _mediaPlayer!.stream.log.listen((event) {
      print("MediaKit Log [${event.level}]: ${event.text}");
    });

    _mediaPlayer!.stream.buffering.listen((isBuffering) {
      if (isBuffering) {
        _bufferingTimer?.cancel();
        _bufferingTimer = Timer(const Duration(seconds: 8), () {
          if (mounted && _mediaPlayer != null && _mediaPlayer!.state.buffering) {
            print("MediaKit Buffering Timeout! Stream might be corrupt or dead. Forcing failover...");
            _triggerFailover();
          }
        });
      } else {
        _bufferingTimer?.cancel();
      }
    });

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

    _mediaPlayer!.stream.position.listen((pos) {
      if (pos > Duration.zero) {
        _lastPlaybackPosition = pos;
      }
      
      // Remember preferred working provider after 15s of playback
      if (pos.inSeconds > 15 && _selectedQuality != null && _selectedQuality!.contains('(')) {
        final prov = _selectedQuality!.split('(').last.replaceAll(')', '').trim();
        if (StreamingAggregatorService.preferredProvider != prov) {
          StreamingAggregatorService.preferredProvider = prov;
          print("Aggregator: Saved preferred provider: $prov");
        }
      }
    });

    _mediaPlayer!.stream.duration.listen((duration) {
      if (mounted && !_hasRestoredPosition && _lastPlaybackPosition > Duration.zero && duration > Duration.zero) {
        _hasRestoredPosition = true;
        _mediaPlayer!.seek(_lastPlaybackPosition);
        print("Restored playback position to $_lastPlaybackPosition");
      }
    });

    _hasRestoredPosition = false;
    await _mediaPlayer!.open(Media(url, httpHeaders: headers), play: true);

    // 2. Start 15-second timer to auto-upgrade/downgrade based on measured speed
    _autoQualityTimer?.cancel();
    _autoQualityTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_userForcedQuality) {
        _applyOptimalQualityForSpeed(NetworkService().currentSpeed);
      }
    });

    setState(() {});
  }

  void _changeQuality(
    Map<String, dynamic> stream, {
    bool isAuto = false,
  }) async {
    if (_mediaPlayer == null) return;

    if (!isAuto) {
      _userForcedQuality = true; // User manually selected, disable auto-downgrade
      _autoQualityTimer?.cancel();
    }

    final position = _mediaPlayer!.state.position;
    if (position > Duration.zero) {
      _lastPlaybackPosition = position;
    }

    setState(() {
      _selectedQuality = stream['quality'];
      currentUrl = stream['url'];
      if (stream['headers'] != null) {
        currentHeaders = Map<String, String>.from(stream['headers']);
      }
    });

    _hasRestoredPosition = false;
    await _mediaPlayer!.open(
      Media(currentUrl, httpHeaders: currentHeaders),
      play: true,
    );
    // Restore the selected subtitle track when quality changes
    _mediaPlayer!.setSubtitleTrack(_selectedSubtitleTrack);
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

    if (engine.startsWith('native_') && engine != 'native_extractor') {
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
      } else if (_currentEngine == 'native_extractor') {
        _startHeadlessExtractor(currentUrl);
      } else if (_currentEngine.startsWith('native_') && _currentEngine != 'native_extractor') {
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

  Future<void> _startHeadlessExtractor(String embedUrl) async {
    setState(() {
      _isExtracting = true;
      _extractedSubtitles.clear();
      _extractedStreamUrl = null;
      _extractedStreamHeaders = null;
    });

    headlessWebView?.dispose();
    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
      initialSettings: InAppWebViewSettings(
        useShouldInterceptRequest: true,
        useShouldInterceptAjaxRequest: true,
        useShouldInterceptFetchRequest: true,
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: """
            // 1. Override fetch to sniff out .m3u8, .mp4, .vtt, .srt
            var originalFetch = window.fetch;
            window.fetch = function() {
                var reqUrl = arguments[0];
                if (typeof reqUrl === 'string') {
                    if (reqUrl.includes('.m3u8') || reqUrl.includes('.mp4')) {
                        console.log("STREAM_FOUND: " + reqUrl);
                    } else if (reqUrl.includes('.vtt') || reqUrl.includes('.srt')) {
                        console.log("SUBTITLE_FOUND: " + reqUrl);
                    }
                }
                return originalFetch.apply(this, arguments);
            };
            
            // 2. Auto-click play buttons
            setTimeout(function() {
              var buttons = document.querySelectorAll('button, .play-button, .vjs-big-play-button, #play-btn, .plyr__control--overlaid');
              buttons.forEach(function(b) { b.click(); });
              
              var iframes = document.querySelectorAll('iframe');
              iframes.forEach(function(f) {
                 f.contentWindow.postMessage('play', '*');
              });
              
              // Click the absolute center of the screen
              var x = window.innerWidth / 2;
              var y = window.innerHeight / 2;
              var centerEl = document.elementFromPoint(x, y);
              if (centerEl) centerEl.click();
              
              document.body.click();
            }, 1000);
            
            // Try clicking again after 3 seconds
            setTimeout(function() {
              var buttons = document.querySelectorAll('button, .play-button, .vjs-big-play-button, #play-btn, .plyr__control--overlaid');
              buttons.forEach(function(b) { b.click(); });
              
              var x = window.innerWidth / 2;
              var y = window.innerHeight / 2;
              var centerEl = document.elementFromPoint(x, y);
              if (centerEl) centerEl.click();
            }, 3000);
          """,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          forMainFrameOnly: false, // Critical: Inject into all iframes!
        )
      ]),
      onWebViewCreated: (controller) {
        print("Headless Extractor: Created for $embedUrl");
      },
      onLoadStart: (controller, url) {
        print("Headless Extractor: Started loading $url");
      },
      shouldInterceptRequest: (controller, request) async {
        final urlStr = request.url.toString();
        final referer = request.headers?['Referer']?.toString() ?? 
                        request.headers?['referer']?.toString() ?? 
                        request.headers?['Origin']?.toString() ?? 
                        Uri.parse(embedUrl).origin + '/';
        _checkExtractedUrl(urlStr, referer);
        return null;
      },
      shouldInterceptAjaxRequest: (controller, request) async {
        final urlStr = request.url.toString();
        final referer = Uri.parse(embedUrl).origin + '/';
        _checkExtractedUrl(urlStr, referer);
        return null;
      },
      shouldInterceptFetchRequest: (controller, request) async {
        final urlStr = request.url.toString();
        final referer = Uri.parse(embedUrl).origin + '/';
        _checkExtractedUrl(urlStr, referer);
        return null;
      },
      onConsoleMessage: (controller, consoleMessage) {
        final msg = consoleMessage.message;
        if (msg.startsWith("STREAM_FOUND: ")) {
          final urlStr = msg.replaceFirst("STREAM_FOUND: ", "");
          final referer = Uri.parse(embedUrl).origin + '/';
          _checkExtractedUrl(urlStr, referer);
        } else if (msg.startsWith("SUBTITLE_FOUND: ")) {
          final urlStr = msg.replaceFirst("SUBTITLE_FOUND: ", "");
          final referer = Uri.parse(embedUrl).origin + '/';
          _checkExtractedUrl(urlStr, referer);
        }
      },
      onLoadStop: (controller, url) async {
        print("Headless Extractor: Stopped loading $url");
      },
    );

    try {
      await headlessWebView?.run();
      // Setup a 15-second timeout to trigger failover if extraction takes too long
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _isExtracting && _extractedStreamUrl == null) {
          print("Headless Extractor: Timeout reached without finding stream, triggering failover");
          headlessWebView?.dispose();
          headlessWebView = null;
          setState(() {
            _isExtracting = false;
          });
          _triggerFailover();
        }
      });
    } catch (e) {
      print("Headless Extractor error: $e");
      _triggerFailover();
    }
  }

  void _checkExtractedUrl(String urlStr, String referer) {
    if (!_isExtracting) return;
    
    if (urlStr.contains('.vtt') || urlStr.contains('.srt')) {
      if (!_extractedSubtitles.contains(urlStr)) {
        print("Headless Extractor: Found subtitle! $urlStr");
        _extractedSubtitles.add(urlStr);
      }
    } else if ((urlStr.contains('.m3u8') || urlStr.contains('.mp4')) && _extractedStreamUrl == null) {
      print("Headless Extractor: Found stream! $urlStr");
      _extractedStreamUrl = urlStr;
      _extractedStreamHeaders = {'Referer': referer};
      
      // Wait 2 seconds for subtitles to load before initializing player
      _extractionTimer?.cancel();
      _extractionTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _isExtracting) {
          setState(() {
            _isExtracting = false;
            // Add extracted subtitles to the API subtitles list
            for (var subUrl in _extractedSubtitles) {
              if (!_apiSubtitles.any((s) => s['url'] == subUrl)) {
                _apiSubtitles.add({
                  'lang': 'Extracted ${subUrl.split('.').last.toUpperCase()}',
                  'url': subUrl
                });
              }
            }
          });
          
          headlessWebView?.dispose();
          headlessWebView = null;
          
          _initializeNativePlayer(_extractedStreamUrl!, headers: _extractedStreamHeaders);
        }
      });
    }
  }

  void _triggerFailover() {
    print("Provider/Stream failed, triggering failover...");
    
    if (_mediaPlayer != null) {
      final pos = _mediaPlayer!.state.position;
      if (pos > Duration.zero) {
        _lastPlaybackPosition = pos;
      }
    }

    // First, try fallback within the same aggregator if it provided multiple streams
    if (_availableQualities.isNotEmpty) {
      _availableQualities.removeWhere((s) => s['url'] == currentUrl);
      if (_availableQualities.isNotEmpty) {
        final nextStream = _availableQualities.first;
        print("Failover: Trying next available stream from aggregator: ${nextStream['quality']}");
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Stream failed. Switching to backup stream..."),
            backgroundColor: Colors.orangeAccent,
            duration: Duration(seconds: 2),
          ),
        );
        _changeQuality(nextStream, isAuto: true);
        return;
      }
    }

    print("All aggregated streams failed. Moving to next engine/provider...");
    
    // Show a popup on screen
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("All streams failed. Switching to next server..."),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 2),
      ),
    );

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

    if (_isExtracting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.purpleAccent),
            SizedBox(height: 16),
            Text(
              "Bypassing provider and extracting native stream...",
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_currentEngine.startsWith('native_') || _currentEngine == 'native_extractor') {
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
                        '${providers[index]['name']}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }),
                  onChanged: (int? newIndex) {
                    if (newIndex != null && newIndex != currentProviderIndex) {
                      setState(() {
                        if (_mediaPlayer != null) {
                          final pos = _mediaPlayer!.state.position;
                          if (pos > Duration.zero) _lastPlaybackPosition = pos;
                        }
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
          const SizedBox(width: 12),
          // Sub/Dub Toggle right next to Server Selector
          if (_currentEngine.startsWith('native_') && (_hasDubAvailable || _hasSubAvailable))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sub Button
                if (_hasSubAvailable)
                  GestureDetector(
                    onTap: () {
                      if (_isDub) {
                        setState(() => _isDub = false);
                        _preparePlaybackUrl();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: !_isDub ? Colors.redAccent : const Color(0xFF222222),
                        borderRadius: (_hasSubAvailable && _hasDubAvailable)
                            ? const BorderRadius.horizontal(left: Radius.circular(8))
                            : BorderRadius.circular(8),
                        border: Border.all(color: !_isDub ? Colors.redAccent : Colors.white24),
                      ),
                      child: Text(
                        'SUB',
                        style: TextStyle(
                          color: !_isDub ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                
                // Dub Button
                if (_hasDubAvailable)
                  GestureDetector(
                    onTap: () {
                      if (!_isDub) {
                        setState(() => _isDub = true);
                        _preparePlaybackUrl();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isDub ? Colors.redAccent : const Color(0xFF222222),
                        borderRadius: (_hasSubAvailable && _hasDubAvailable)
                            ? const BorderRadius.horizontal(right: Radius.circular(8))
                            : BorderRadius.circular(8),
                        border: Border.all(color: _isDub ? Colors.redAccent : Colors.white24),
                      ),
                      child: Text(
                        'DUB',
                        style: TextStyle(
                          color: _isDub ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.fullscreen, color: Colors.white70),
            tooltip: 'Toggle Fullscreen',
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              bool isFull = await windowManager.isFullScreen();
              await windowManager.setFullScreen(!isFull);
              if (mounted) {
                setState(() {
                  _isDesktopFullscreen = !isFull;
                });
              }
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

  Widget _buildDesktopSidebar() {
    final posterPath = _mediaDetails?['poster_path'];
    final overview = _mediaDetails?['overview'] ?? 'No overview available.';
    final genresList = _mediaDetails?['genres'] as List<dynamic>?;
    final genres = genresList?.map((g) => g['name']).join(', ') ?? 'Unknown';
    
    final countriesList = _mediaDetails?['production_countries'] as List<dynamic>?;
    final country = (countriesList != null && countriesList.isNotEmpty) ? countriesList[0]['name'] : 'Unknown';
    
    final vote = _mediaDetails?['vote_average'];
    final rating = vote != null ? vote.toStringAsFixed(1) : 'N/A';
    
    final dateStr = widget.isMovie ? (_mediaDetails?['release_date']) : (_mediaDetails?['first_air_date']);
    final year = (dateStr != null && dateStr.toString().length >= 4) ? dateStr.toString().substring(0, 4) : 'N/A';

    final breadcrumbLabel = widget.isMovie ? 'Movie' : 'TV';

    return Container(
      color: const Color(0xFF141414),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (posterPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                'https://image.tmdb.org/t/p/w500$posterPath',
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          const SizedBox(height: 16),
          
          // Breadcrumbs
          Row(
            children: [
              const Icon(Icons.home, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              Text('Home / $breadcrumbLabel / ${widget.title}', 
                style: const TextStyle(color: Colors.white54, fontSize: 12)
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Info Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E24), // Darker card background
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))
              ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isMovie ? widget.title : '${widget.title} - Season $currentSeason',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                // Badges Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
                      child: Text('IMDb $rating', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(4)),
                      child: const Text('1080P', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    Text(year, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Synopsis
                Text(
                  overview,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 24),
                
                // Country & Genres
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12, height: 1.6),
                    children: [
                      const TextSpan(text: 'Country: ', style: TextStyle(color: Colors.white54)),
                      TextSpan(text: '$country\n', style: const TextStyle(color: Colors.white)),
                      const TextSpan(text: 'Genres: ', style: TextStyle(color: Colors.white54)),
                      TextSpan(text: genres, style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          )
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
        
        if (_hasDubAvailable) {
          items.addAll([
            const PopupMenuItem<dynamic>(
              enabled: false,
              child: Text(
                'Audio Track',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            PopupMenuItem<dynamic>(
              value: 'sub',
              child: Text(
                'Subbed (Original)',
                style: TextStyle(
                  color: !_isDub ? Colors.redAccent : Colors.white,
                  fontWeight: !_isDub ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            PopupMenuItem<dynamic>(
              value: 'dub',
              child: Text(
                'Dubbed (English)',
                style: TextStyle(
                  color: _isDub ? Colors.redAccent : Colors.white,
                  fontWeight: _isDub ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            const PopupMenuDivider(),
          ]);
        }

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
        }

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
    final bool isWide = screenWidth > 800; // Enable desktop split layout

    return Scaffold(
      backgroundColor: const Color(0xFF141414), // Dark background matching design
      appBar: _isDesktopFullscreen ? null : AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_availableQualities.isNotEmpty) _buildSettingsMenu(),
        ],
      ),
      body: SafeArea(
        child: _isDesktopFullscreen
            ? Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: _buildPlayerSection(),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 28),
                        onPressed: () async {
                          await windowManager.setFullScreen(false);
                          if (mounted) {
                            setState(() {
                              _isDesktopFullscreen = false;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              )
            : isWide
                ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                                  _lastPlaybackPosition = Duration.zero;
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
                          _buildMoreLikeThis(),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 350,
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Colors.white12, width: 1),
                      ),
                    ),
                    child: _buildDesktopSidebar(),
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
                            _lastPlaybackPosition = Duration.zero;
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
