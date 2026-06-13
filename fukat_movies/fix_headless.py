import re

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Replace _startHeadlessExtractor to _checkExtractedUrl to _triggerFailover
start_marker = r'Future<void> _startHeadlessExtractor\(String embedUrl\) async \{'
end_marker = r'Widget _buildVideoPlayerArea\(\) \{'

match = re.search(start_marker + r'.*?(?=' + end_marker + r')', content, re.DOTALL)
if match:
    old_text = match.group(0)
    new_text = '''Future<void> _startHeadlessExtractor(int index, String embedUrl, List<Map<String, dynamic>> providers) async {
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
          source: """
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
          """,
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

  '''
    content = content.replace(old_text, new_text)
    print('Replaced _startHeadlessExtractor to _triggerFailover.')
else:
    print('Could not find start_marker.')

# 2. Fix _startPlayback to use _playFromProvider
start_playback = r'void _startPlayback\(\) \{.*?(?=Future<void> _startHeadlessExtractor)'
match2 = re.search(start_playback, content, re.DOTALL)
if match2:
    old_play = match2.group(0)
    new_play = '''void _startPlayback() {
    final allProviders = List<Map<String, dynamic>>.from(RemoteConfigService.activeProviders);
    if (_successfulProviders.isNotEmpty) {
      _playFromProvider(_successfulProviders.first, allProviders);
    } else {
      _preparePlaybackUrl();
    }
  }

  '''
    content = content.replace(old_play, new_play)
    print('Replaced _startPlayback.')

# 3. Fix tmdbId parsing if needed
content = content.replace('tmdbId: widget.tmdbId,', 'tmdbId: int.parse(widget.tmdbId),')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
