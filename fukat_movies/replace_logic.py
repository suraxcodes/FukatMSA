import re

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

start_marker = "Future<void> _preparePlaybackUrl() async {"
end_marker = "Widget _buildVideoPlayerArea() {"

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print("Could not find markers")
    exit(1)

new_code = """Future<void> _startParallelExtractions() async {
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
    // Fake current provider index for _buildPlaybackUrl dependencies
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
  }

  Future<void> _startHeadlessExtractor(int index, String embedUrl, List<Map<String, dynamic>> providers) async {
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

  void _triggerFailover() {
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
  }

"""

content = content[:start_idx] + new_code + content[end_idx:]

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Replaced logic successfully!")
