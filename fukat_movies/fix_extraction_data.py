import sys
import re

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace _startSingleExtraction
start_single = '''  Future<void> _startSingleExtraction(int index, Map<String, dynamic> provider, List<Map<String, dynamic>> providers) async {
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
      _onExtractionSuccess(index, playbackData, providers);
    } else if (engine == 'native_extractor') {
      _startHeadlessExtractor(index, url, providers);
    } else {
      _finishExtraction(index, false, providers);
    }
  }'''
content = content.replace(start_single, new_single)

# Replace _onExtractionSuccess
on_success_old = '''  void _onExtractionSuccess(int index, String url, Map<String, String>? headers, List<String> subtitles, List<Map<String, dynamic>> providers) {
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
  }'''

on_success_new = '''  void _onExtractionSuccess(int index, Map<String, dynamic> playbackData, List<Map<String, dynamic>> providers) {
    if (!mounted) return;
    
    if (!_successfulProviders.contains(index)) {
      print("Parallel Extraction: Server ${index + 1} Succeeded!");
      setState(() {
        _successfulProviders.add(index);
        _extractedProviderData[index] = playbackData;
        _successfulProviders.sort();
      });

      if (_successfulProviders.length == 1) {
        _playFromProvider(index, providers);
      }
    }
    _finishExtraction(index, true, providers);
  }'''
content = content.replace(on_success_old, on_success_new)

# Update _startHeadlessExtractor
content = re.sub(
    r'_onExtractionSuccess\(index,\s*streamUrl,\s*null,\s*headlessSubtitles,\s*providers\);',
    r"_onExtractionSuccess(index, { 'url': streamUrl, 'headless_subtitles': headlessSubtitles }, providers);",
    content
)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Replaced single extraction successfully!")
