import re

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix _startSingleExtraction
old_single = '''  Future<void> _startSingleExtraction(int index, Map<String, dynamic> provider, List<Map<String, dynamic>> providers) async {
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
  }'''

new_single = '''  Future<void> _startSingleExtraction(int index, Map<String, dynamic> provider, List<Map<String, dynamic>> providers) async {
    // Fake current provider index for _buildPlaybackUrl
    currentProviderIndex = index;
    final playbackData = await _buildPlaybackUrl(provider);
    
    if (!mounted) return;

    if (playbackData == null || playbackData['url'] == null) {
      _finishExtraction(index, false, providers);
      return;
    }

    final String engine = provider['engine'] ?? 'webview';
    String url = playbackData['url'] as String;
    Map<String, String>? headers = playbackData['headers'] != null ? Map<String, String>.from(playbackData['headers'] as Map) : null;
    
    List<Map<String, dynamic>> streams = [];
    if (playbackData['streams'] != null) {
      try {
        streams = List<Map<String, dynamic>>.from(playbackData['streams']);
        if (streams.isNotEmpty) {
           final lowQualityStream = streams.firstWhere(
             (s) => s['quality'].toString().contains('360') || s['quality'].toString().contains('480'),
             orElse: () => streams.last,
           );
           url = lowQualityStream['url'] ?? url;
           if (lowQualityStream['headers'] != null) {
             headers = Map<String, String>.from(lowQualityStream['headers']);
           }
        }
      } catch (e) {
        print("Error parsing streams: $e");
      }
    }
    
    List<Map<String, dynamic>> apiSubs = [];
    if (playbackData['subtitles'] != null) {
      try {
        apiSubs = List<Map<String, dynamic>>.from(playbackData['subtitles']);
      } catch (e) {
        print("Error parsing API subtitles: $e");
      }
    }

    if (engine.startsWith('native_') && engine != 'native_extractor') {
      // Store raw stream/sub data in the extracted map
      _extractedProviderData[index] = {
         'url': url,
         'headers': headers,
         'subtitles': [], // We use apiSubtitles for aggregators
         'apiSubtitles': apiSubs,
         'streams': streams,
      };
      // Short-circuit the generic _onExtractionSuccess since we customized it above
      if (!_successfulProviders.contains(index)) {
        print("Parallel Extraction: Server ${index + 1} Succeeded!");
        setState(() {
          _successfulProviders.add(index);
          _successfulProviders.sort();
        });
        if (_successfulProviders.length == 1) {
          _playFromProvider(index, providers);
        }
      }
      _finishExtraction(index, true, providers);
    } else if (engine == 'native_extractor') {
      _startHeadlessExtractor(index, url, providers);
    } else {
      _finishExtraction(index, false, providers);
    }
  }'''

# Fix _playFromProvider
old_play = '''  void _playFromProvider(int index, List<Map<String, dynamic>> providers) async {
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
  }'''

new_play = '''  void _playFromProvider(int index, List<Map<String, dynamic>> providers) async {
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
      
      // Load aggregator streams and subtitles
      if (data['streams'] != null) {
        _availableQualities = List<Map<String, dynamic>>.from(data['streams']);
      } else {
        _availableQualities = [];
      }
      
      if (data['apiSubtitles'] != null) {
        _apiSubtitles = List<Map<String, dynamic>>.from(data['apiSubtitles']);
      } else {
        _apiSubtitles = [];
      }
      
      // Load raw extracted subtitles from Headless
      if (data['subtitles'] != null) {
        for (var subUrl in (data['subtitles'] as List<String>)) {
          if (!_apiSubtitles.any((s) => s['url'] == subUrl)) {
            _apiSubtitles.add({
              'lang': 'Extracted ${subUrl.split('.').last.toUpperCase()}',
              'url': subUrl
            });
          }
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
  }'''

if old_single in content and old_play in content:
    content = content.replace(old_single, new_single)
    content = content.replace(old_play, new_play)
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Fixed streams array and _playFromProvider properly!")
else:
    print("Could not find blocks to replace!")
