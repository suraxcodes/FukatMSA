import re

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add state variables to the top (replacing the old extractor state)
content = content.replace(
'''  // Headless Extractor State
  List<String> _extractedSubtitles = [];
  String? _extractedStreamUrl;
  Map<String, String>? _extractedStreamHeaders;
  Timer? _extractionTimer;
  Timer? _bufferingTimer;''',
'''  // Headless Extractor State
  Map<int, HeadlessInAppWebView> _headlessExtractors = {};
  List<int> _successfulProviders = [];
  Map<int, Map<String, dynamic>> _extractedProviderData = {};
  bool _parallelExtractionComplete = false;
  int _activeConcurrency = 0;
  final int _maxConcurrency = 3;
  List<int> _extractionQueue = [];
  Timer? _extractionTimer;
  Timer? _bufferingTimer;'''
)

# 2. Update dispose
content = content.replace(
'''    headlessWebView?.dispose();''',
'''    for (var webview in _headlessExtractors.values) {
      webview.dispose();
    }
    _headlessExtractors.clear();'''
)

# 3. Replace _preparePlaybackUrl with _startParallelExtractions but keep the name _preparePlaybackUrl
# The easiest way is to replace the body of _preparePlaybackUrl
old_prepare_body = """  Future<void> _preparePlaybackUrl() async {
    final allProviders = List<Map<String, dynamic>>.from(RemoteConfigService.activeProviders);
    
    final providers = allProviders.where((p) {
      if (!widget.isMovie && !(p['engine'] == 'native_miruro')) return true; // Keep TV as-is unless it's Miruro
      final types = List<String>.from(p['audio_types'] ?? []);
      if (types.isEmpty) return true;
      return _isMovieDubMode ? types.contains("dub") : types.contains("sub");
    }).toList();

    if (currentProviderIndex >= providers.length) {
      setState(() {
        currentUrl = "";
        currentHeaders = null;
      });
      return;
    }

    var activeProvider = providers[currentProviderIndex];
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

        _startPlayback();
      });
    }
  }"""

new_prepare_body = """  Future<void> _preparePlaybackUrl() async {
    final allProviders = List<Map<String, dynamic>>.from(RemoteConfigService.activeProviders);
    
    final providers = allProviders.where((p) {
      if (!widget.isMovie && !(p['engine'] == 'native_miruro')) return true; // Keep TV as-is unless it's Miruro
      final types = List<String>.from(p['audio_types'] ?? []);
      if (types.isEmpty) return true;
      return _isMovieDubMode ? types.contains("dub") : types.contains("sub");
    }).toList();

    if (providers.isEmpty) return;

    setState(() {
      _successfulProviders.clear();
      _extractedProviderData.clear();
      _parallelExtractionComplete = false;
      _extractionQueue.clear();
      _activeConcurrency = 0;
      for (var webview in _headlessExtractors.values) {
        webview.dispose();
      }
      _headlessExtractors.clear();
    });

    for (int i = 0; i < providers.length; i++) {
      _extractionQueue.add(i);
    }
    
    _processExtractionQueue(providers);
  }

  void _processExtractionQueue(List<Map<String, dynamic>> providers) {
    if (_extractionQueue.isEmpty) {
      if (_activeConcurrency == 0) {
        if (mounted) {
          setState(() {
            _parallelExtractionComplete = true;
          });
        }
        if (_successfulProviders.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("All servers failed to find streams."),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          });
        }
      }
      return;
    }

    while (_activeConcurrency < _maxConcurrency && _extractionQueue.isNotEmpty) {
      final index = _extractionQueue.removeAt(0);
      _activeConcurrency++;
      _startSingleExtraction(index, providers[index], providers);
    }
  }

  Future<void> _startSingleExtraction(int index, Map<String, dynamic> provider, List<Map<String, dynamic>> providers) async {
    // Fake current provider index for _buildPlaybackUrl
    currentProviderIndex = index;
    final playbackData = await _buildPlaybackUrl(provider);
    
    if (!mounted) return;

    if (playbackData == null || playbackData['url'] == null) {
      _finishExtraction(index, false, providers);
      return;
    }

    final String engine = provider['engine'] ?? 'webview';
    final String url = playbackData['url'] as String;

    if (engine.startsWith('native_') && engine != 'native_extractor') {
      _onExtractionSuccess(index, url, playbackData['headers'] != null ? Map<String, String>.from(playbackData['headers'] as Map) : null, [], providers);
    } else if (engine == 'native_extractor') {
      _startHeadlessExtractor(index, url, providers);
    } else {
      _finishExtraction(index, false, providers);
    }
  }

  void _finishExtraction(int index, bool success, List<Map<String, dynamic>> providers) {
    if (!mounted) return;
    _headlessExtractors[index]?.dispose();
    _headlessExtractors.remove(index);
    _activeConcurrency--;
    _processExtractionQueue(providers);
  }

  void _onExtractionSuccess(int index, String url, Map<String, String>? headers, List<String> subtitles, List<Map<String, dynamic>> providers) {
    if (!mounted) return;
    
    if (!_successfulProviders.contains(index)) {
      print("Parallel Extraction: Server ${index + 1} Succeeded!");
      setState(() {
        _successfulProviders.add(index);
        _extractedProviderData[index] = {
          'url': url,
          'headers': headers,
          'subtitles': subtitles,
        };
        _successfulProviders.sort();
      });

      if (_successfulProviders.length == 1) {
        _playFromProvider(index, providers);
      }
    }
    _finishExtraction(index, true, providers);
  }

  void _playFromProvider(int index, List<Map<String, dynamic>> providers) async {
    final data = _extractedProviderData[index];
    if (data == null) return;
    
    if (_mediaPlayer != null) {
      final pos = _mediaPlayer!.state.position;
      if (pos > Duration.zero) _lastPlaybackPosition = pos;
      await _mediaPlayer!.stop(); // Fixes audio-only phantom playback
    }

    setState(() {
      currentProviderIndex = index;
      currentUrl = data['url'];
      currentHeaders = data['headers'];
      _currentEngine = providers[index]['engine'] ?? 'webview';
      _isPlaying = true;
      
      for (var subUrl in (data['subtitles'] as List<String>)) {
        if (!_apiSubtitles.any((s) => s['url'] == subUrl)) {
          _apiSubtitles.add({
            'lang': 'Extracted ${subUrl.split('.').last.toUpperCase()}',
            'url': subUrl
          });
        }
      }
    });

    _initializeNativePlayer(currentUrl, headers: currentHeaders);
    
    ContinueWatchingService.saveItem(
      tmdbId: widget.tmdbId,
      title: widget.title,
      posterPath: null,
      isMovie: widget.isMovie,
      lastSeason: widget.isMovie ? null : int.tryParse(currentSeason),
      lastEpisode: widget.isMovie ? null : int.tryParse(currentEpisode),
    );
  }"""

content = content.replace(old_prepare_body, new_prepare_body)

# 4. We need to leave _startPlayback() intact so it doesn't break external callers, but it can just be a no-op or fallback to standard play
old_startPlayback = """  void _startPlayback() {
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
  }"""

new_startPlayback = """  void _startPlayback() {
    // This is now handled by _playFromProvider but we keep this method to satisfy existing UI calls like 'Retry'
    final allProviders = List<Map<String, dynamic>>.from(RemoteConfigService.activeProviders);
    if (_successfulProviders.isNotEmpty) {
      _playFromProvider(_successfulProviders.first, allProviders);
    } else {
      _preparePlaybackUrl();
    }
  }"""

content = content.replace(old_startPlayback, new_startPlayback)

# 5. Fix _startHeadlessExtractor
old_headless = """  Future<void> _startHeadlessExtractor(String embedUrl) async {
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
          source: \"\"\"
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
          \"\"\",
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
      // Setup an 8-second timeout to trigger failover if extraction takes too long
      Future.delayed(const Duration(seconds: 8), () {
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

  void _triggerFailover() {"""

new_headless = """  Future<void> _startHeadlessExtractor(int index, String embedUrl, List<Map<String, dynamic>> providers) async {
    final webview = HeadlessInAppWebView(
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
          source: \"\"\"
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
            setTimeout(function() {
              var buttons = document.querySelectorAll('button, .play-button, .vjs-big-play-button, #play-btn, .plyr__control--overlaid');
              buttons.forEach(function(b) { b.click(); });
              var iframes = document.querySelectorAll('iframe');
              iframes.forEach(function(f) {
                 f.contentWindow.postMessage('play', '*');
              });
              var centerEl = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
              if (centerEl) centerEl.click();
              document.body.click();
            }, 1000);
          \"\"\",
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          forMainFrameOnly: false,
        )
      ]),
      shouldInterceptRequest: (controller, request) async {
        final urlStr = request.url.toString();
        final referer = request.headers?['Referer']?.toString() ?? 
                        request.headers?['referer']?.toString() ?? 
                        request.headers?['Origin']?.toString() ?? 
                        Uri.parse(embedUrl).origin + '/';
        _checkExtractedUrl(index, urlStr, referer, providers);
        return null;
      },
      shouldInterceptAjaxRequest: (controller, request) async {
        final urlStr = request.url.toString();
        final referer = Uri.parse(embedUrl).origin + '/';
        _checkExtractedUrl(index, urlStr, referer, providers);
        return null;
      },
      shouldInterceptFetchRequest: (controller, request) async {
        final urlStr = request.url.toString();
        final referer = Uri.parse(embedUrl).origin + '/';
        _checkExtractedUrl(index, urlStr, referer, providers);
        return null;
      },
      onConsoleMessage: (controller, consoleMessage) {
        final msg = consoleMessage.message;
        if (msg.startsWith("STREAM_FOUND: ")) {
          final urlStr = msg.replaceFirst("STREAM_FOUND: ", "");
          final referer = Uri.parse(embedUrl).origin + '/';
          _checkExtractedUrl(index, urlStr, referer, providers);
        } else if (msg.startsWith("SUBTITLE_FOUND: ")) {
          final urlStr = msg.replaceFirst("SUBTITLE_FOUND: ", "");
          final referer = Uri.parse(embedUrl).origin + '/';
          _checkExtractedUrl(index, urlStr, referer, providers);
        }
      },
    );

    _headlessExtractors[index] = webview;

    try {
      await webview.run();
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted && !_successfulProviders.contains(index) && _headlessExtractors.containsKey(index)) {
          print("Headless Extractor: Timeout for index $index");
          _finishExtraction(index, false, providers);
        }
      });
    } catch (e) {
      print("Headless Extractor error: $e");
      _finishExtraction(index, false, providers);
    }
  }

  void _checkExtractedUrl(int index, String urlStr, String referer, List<Map<String, dynamic>> providers) {
    if (!mounted || _successfulProviders.contains(index)) return;
    
    if (urlStr.contains('.vtt') || urlStr.contains('.srt')) {
      if (_extractedProviderData[index] == null) {
        _extractedProviderData[index] = {'url': '', 'headers': null, 'subtitles': <String>[]};
      }
      final subs = _extractedProviderData[index]!['subtitles'] as List<String>;
      if (!subs.contains(urlStr)) {
        subs.add(urlStr);
      }
    } else if (urlStr.contains('.m3u8') || urlStr.contains('.mp4')) {
      print("Headless Extractor: Found stream for index $index! $urlStr");
      final existingSubs = _extractedProviderData[index]?['subtitles'] as List<String>? ?? [];
      _onExtractionSuccess(index, urlStr, {'Referer': referer}, existingSubs, providers);
    }
  }

  void _triggerFailover() {"""

content = content.replace(old_headless, new_headless)

old_failover = """  void _triggerFailover() {
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
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Stream failed. Switching to backup stream..."),
                backgroundColor: Colors.orangeAccent,
                duration: Duration(seconds: 2),
              ),
            );
          }
        });
        
        _changeQuality(nextStream, isAuto: true);
        return;
      }
    }

    print("All aggregated streams failed. Moving to next engine/provider...");
    
    // Show a popup on screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("All streams failed. Switching to next server..."),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });

    setState(() {
      currentProviderIndex++;
    });
    _preparePlaybackUrl();
  }"""

new_failover = """  void _triggerFailover() {
    print("Provider/Stream failed, triggering failover...");
    
    if (_mediaPlayer != null) {
      final pos = _mediaPlayer!.state.position;
      if (pos > Duration.zero) _lastPlaybackPosition = pos;
    }

    final allProviders = List<Map<String, dynamic>>.from(RemoteConfigService.activeProviders);
    
    // Find the next successful provider
    int? nextIndex;
    for (int idx in _successfulProviders) {
      if (idx > currentProviderIndex) {
        nextIndex = idx;
        break;
      }
    }
    
    if (nextIndex != null) {
      print("Failover: Switching to Server ${nextIndex + 1}");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Stream failed. Switching to Server ${nextIndex! + 1}..."),
              backgroundColor: Colors.orangeAccent,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });
      _playFromProvider(nextIndex, allProviders);
    } else {
      print("All successful streams failed.");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("All fallback streams failed."),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    }
  }"""

content = content.replace(old_failover, new_failover)

old_ui = """  Widget _buildServerSelector() {
    final allProviders = RemoteConfigService.activeProviders;
    if (allProviders.isEmpty) return SizedBox.shrink();

    // Determine if we are showing native Anime logic (Miruro)
    bool isNativeAnime = allProviders[0]['engine'] == 'native_miruro' && !widget.isMovie;
    
    final providers = allProviders.where((p) {
      if (!widget.isMovie && !(p['engine'] == 'native_miruro')) return true;
      final types = List<String>.from(p['audio_types'] ?? []);
      if (types.isEmpty) return true;
      return _isMovieDubMode ? types.contains("dub") : types.contains("sub");
    }).toList();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: Colors.black,
      child: Row(
        children: [
          Icon(Icons.dns, color: Colors.white70, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: currentProviderIndex,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A1A1A),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  items: List.generate(
                    allProviders.length,
                    (index) => DropdownMenuItem(
                      value: index,
                      child: Text(
                        allProviders[index]['name'],
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
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
          if (isNativeAnime && (_hasDubAvailable || _hasSubAvailable))
            Row(
              children: [
                _buildToggleBtn("SUBBED", !_isMovieDubMode, () {
                  if (_isMovieDubMode) {
                    setState(() {
                      _isMovieDubMode = false;
                      currentProviderIndex = 0;
                    });
                    _preparePlaybackUrl();
                  }
                }),
                const SizedBox(width: 8),
                _buildToggleBtn("DUBBED", _isMovieDubMode, () {
                  if (!_isMovieDubMode) {
                    setState(() {
                      _isMovieDubMode = true;
                      currentProviderIndex = 0;
                    });
                    _preparePlaybackUrl();
                  }
                }),
              ],
            ),
        ],
      ),
    );
  }"""

new_ui = """  Widget _buildServerSelector() {
    final allProviders = RemoteConfigService.activeProviders;
    if (allProviders.isEmpty) return SizedBox.shrink();

    // Determine if we are showing native Anime logic (Miruro)
    bool isNativeAnime = allProviders[0]['engine'] == 'native_miruro' && !widget.isMovie;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: Colors.black,
      child: Row(
        children: [
          Icon(Icons.dns, color: Colors.white70, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _successfulProviders.map((index) {
                  final providerName = allProviders[index]['name'];
                  final isSelected = index == currentProviderIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: GestureDetector(
                      onTap: () {
                        if (index != currentProviderIndex) {
                          _playFromProvider(index, allProviders);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.redAccent : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? Colors.redAccent : Colors.white24,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) const Icon(Icons.play_circle_fill, color: Colors.white, size: 16),
                            if (isSelected) const SizedBox(width: 4),
                            Text(
                              isSelected ? "Playing: $providerName" : "Change Server: $providerName",
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          if (!_parallelExtractionComplete)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
              ),
            ),
          const SizedBox(width: 12),
          // Sub/Dub Toggle right next to Server Selector
          if (isNativeAnime && (_hasDubAvailable || _hasSubAvailable))
            Row(
              children: [
                _buildToggleBtn("SUB", !_isMovieDubMode, () {
                  if (_isMovieDubMode) {
                    setState(() {
                      _isMovieDubMode = false;
                    });
                    _preparePlaybackUrl();
                  }
                }),
                const SizedBox(width: 4),
                _buildToggleBtn("DUB", _isMovieDubMode, () {
                  if (!_isMovieDubMode) {
                    setState(() {
                      _isMovieDubMode = true;
                    });
                    _preparePlaybackUrl();
                  }
                }),
              ],
            ),
        ],
      ),
    );
  }"""

content = content.replace(old_ui, new_ui)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Replaced smoothly!')
