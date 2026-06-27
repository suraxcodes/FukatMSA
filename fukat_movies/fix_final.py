import sys
import re

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix int.parse(widget.tmdbId) -> widget.tmdbId
content = content.replace('int.parse(widget.tmdbId)', 'widget.tmdbId')

# 2. Fix missing tmdbId in _buildPlaybackUrl
content = content.replace('''      return await StreamingAggregatorService.getNativeStreamingUrl(
        title: widget.title,
        engine: engine,
        season: int.tryParse(currentSeason) ?? 1,
        episodeNumber: int.tryParse(currentEpisode) ?? 1,
        isDub: _isDub,
      );''', '''      return await StreamingAggregatorService.getNativeStreamingUrl(
        title: widget.title,
        engine: engine,
        season: int.tryParse(currentSeason) ?? 1,
        episodeNumber: int.tryParse(currentEpisode) ?? 1,
        isDub: _isDub,
        tmdbId: widget.tmdbId,
      );''')

# 3. Comment out old _startHeadlessExtractor(currentUrl) which had 1 argument
content = content.replace('_startHeadlessExtractor(currentUrl);', '/* _startHeadlessExtractor(currentUrl); */')

# 4. _isMappingEpisode -> _successfulProviders.isEmpty && !_parallelExtractionComplete
content = content.replace('if (_isMappingEpisode) {', 'if (_successfulProviders.isEmpty && !_parallelExtractionComplete) {')

# 5. Initialize the parallel queue in _initializePlaybackData
old_init = '''    setState(() {
      currentImdbId =
          imdbId ?? widget.tmdbId; // Fallback to TMDB if IMDB not found
      isInitializing = false;
      _preparePlaybackUrl();
    });'''
new_init = '''    setState(() {
      currentImdbId = imdbId ?? widget.tmdbId;
      isInitializing = false;
      
      _parallelExtractionComplete = false;
      _successfulProviders.clear();
      _extractedProviderData.clear();
      _activeConcurrency = 0;
      _isPlaying = false;
      
      final providersList = RemoteConfigService.activeProviders;
      _extractionQueue = List.generate(providersList.length, (index) => index);
      _processExtractionQueue(providersList);
    });'''
content = content.replace(old_init, new_init)

# 6. Delete _preparePlaybackUrl
match = re.search(r'  Future<void> _preparePlaybackUrl\(\) async \{.*?(?=  Future<Map<String, dynamic>\?> _buildPlaybackUrl)', content, re.DOTALL)
if match:
    content = content.replace(match.group(0), '')

# 7. Rewrite _startPlayback to use _playFromProvider
old_playback = '''  void _startPlayback() {
    final allProviders = List<Map<String, dynamic>>.from(RemoteConfigService.activeProviders);
    if (_successfulProviders.isNotEmpty) {
      _playFromProvider(_successfulProviders.first, allProviders);
    } else {
      _preparePlaybackUrl();
    }
  }'''
new_playback = '''  void _startPlayback() {
    final allProviders = List<Map<String, dynamic>>.from(RemoteConfigService.activeProviders);
    if (_successfulProviders.isNotEmpty) {
      _playFromProvider(_successfulProviders.first, allProviders);
    } else {
      _extractionQueue = List.generate(allProviders.length, (index) => index);
      _processExtractionQueue(allProviders);
    }
  }'''
content = content.replace(old_playback, new_playback)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Applied final compilation fixes!")
