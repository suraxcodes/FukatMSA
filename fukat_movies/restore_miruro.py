import sys
import re

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace _startSingleExtraction
start_single = r'  Future<void> _startSingleExtraction\(int index, Map<String, dynamic> provider, List<Map<String, dynamic>> providers\) async \{.*?  \}'
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
    final String url = playbackData['url'] as String;

    if (engine.startsWith('native_') && engine != 'native_extractor') {
      // Store full playbackData map directly
      _extractedProviderData[index] = playbackData;
      
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
content = re.sub(start_single, new_single, content, flags=re.DOTALL)

# Replace _onExtractionSuccess to ensure headless data matches
start_success = r'  void _onExtractionSuccess\(int index, String url, Map<String, String>\? headers, List<String> subtitles, List<Map<String, dynamic>> providers\) \{.*?  \}'
new_success = '''  void _onExtractionSuccess(int index, String url, Map<String, String>? headers, List<String> subtitles, List<Map<String, dynamic>> providers) {
    if (!mounted) return;
    
    if (!_successfulProviders.contains(index)) {
      print("Parallel Extraction: Server ${index + 1} Succeeded!");
      setState(() {
        _successfulProviders.add(index);
        _extractedProviderData[index] = {
          'url': url,
          'headers': headers,
          'headless_subtitles': subtitles,
        };
        _successfulProviders.sort();
      });

      if (_successfulProviders.length == 1) {
        _playFromProvider(index, providers);
      }
    }
    _finishExtraction(index, true, providers);
  }'''
content = re.sub(start_success, new_success, content, flags=re.DOTALL)

# Replace _playFromProvider
start_play = r'  void _playFromProvider\(int index, List<Map<String, dynamic>> providers\) async \{.*?ContinueWatchingService\.saveItem\(.*?\);.*?  \}'
new_play = '''  void _playFromProvider(int index, List<Map<String, dynamic>> providers) async {
    final playbackData = _extractedProviderData[index];
    if (playbackData == null) return;
    
    if (_mediaPlayer != null) {
      final pos = _mediaPlayer!.state.position;
      if (pos > Duration.zero) _lastPlaybackPosition = pos;
      await _mediaPlayer!.stop();
    }

    setState(() {
      currentProviderIndex = index;
      _currentEngine = providers[index]['engine'] ?? 'webview';
      _isPlaying = true;
      
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
      
      // Load raw extracted subtitles from Headless
      if (playbackData['headless_subtitles'] != null) {
        for (var subUrl in (playbackData['headless_subtitles'] as List<String>)) {
          if (!_apiSubtitles.any((s) => s['url'] == subUrl)) {
            _apiSubtitles.add({
              'lang': 'Extracted ${subUrl.split('.').last.toUpperCase()}',
              'url': subUrl
            });
          }
        }
      }

      _selectedSubtitleTrack = SubtitleTrack.no(); // Reset subtitle on new video load
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
content = re.sub(start_play, new_play, content, flags=re.DOTALL)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Restored original Miruro logic perfectly!")
