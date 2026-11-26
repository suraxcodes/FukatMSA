import sys
import re

# 1. Get the deleted methods from the commit backup
backup_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\player_screen_commit.dart'
with open(backup_path, 'r', encoding='utf-16') as f:
    backup_content = f.read()

# Extract _initializeNativePlayer
init_player_match = re.search(r'  Future<void> _initializeNativePlayer\(.*?\}\n\n  void _changeQuality', backup_content, re.DOTALL)
init_player = init_player_match.group(0).replace('\n\n  void _changeQuality', '')

# Extract _changeQuality
change_quality_match = re.search(r'  void _changeQuality\(.*?\}\n\n  void _changeSubtitle', backup_content, re.DOTALL)
change_quality = change_quality_match.group(0).replace('\n\n  void _changeSubtitle', '')

# Extract _changeSubtitle
change_subtitle_match = re.search(r'  void _changeSubtitle\(SubtitleTrack track\) \{.*?\}', backup_content, re.DOTALL)
change_subtitle = change_subtitle_match.group(0)

# Define _preparePlaybackUrl
prepare_playback = '''  Future<void> _preparePlaybackUrl() async {
    setState(() {
      _parallelExtractionComplete = false;
      _successfulProviders.clear();
      _extractedProviderData.clear();
      _activeConcurrency = 0;
      _isPlaying = false;
      final allProviders = List<Map<String, dynamic>>.from(RemoteConfigService.activeProviders);
      _extractionQueue = List.generate(allProviders.length, (index) => index);
      _processExtractionQueue(allProviders);
    });
  }'''


# Now modify player_screen.dart
file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove the trailing brace and add everything back
if content.strip().endswith('}'):
    content = content[:content.rfind('}')]
    
content += '\n\n' + prepare_playback + '\n\n' + init_player + '\n\n' + change_quality + '\n\n' + change_subtitle + '\n}'

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Restored deleted methods!")
