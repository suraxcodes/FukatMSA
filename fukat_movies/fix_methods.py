import sys

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix int.parse(widget.tmdbId) -> widget.tmdbId
content = content.replace('tmdbId: int.parse(widget.tmdbId),', 'tmdbId: widget.tmdbId,')

# 2. Fix old _startHeadlessExtractor(currentUrl) call
content = content.replace('_startHeadlessExtractor(currentUrl);', '/* _startHeadlessExtractor(currentUrl); */')

# 3. Add missing methods before _buildServerSelector
missing_methods = '''  void _processExtractionQueue(List<Map<String, dynamic>> providers) {
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
      await _mediaPlayer!.stop();
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

'''

if '_playFromProvider' not in content:
    content = content.replace('  Widget _buildServerSelector() {', missing_methods + '  Widget _buildServerSelector() {')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Fixed compilation errors.')
