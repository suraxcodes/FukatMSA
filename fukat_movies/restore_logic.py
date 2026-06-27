import sys
import subprocess

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    current_content = f.read()

result = subprocess.run(['git', 'show', 'HEAD:fukat_movies/lib/screens/player_screen.dart'], cwd=r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies', capture_output=True, text=True, encoding='utf-8')
old_content = result.stdout

start_marker = "Future<void> _initializeNativePlayer("
end_marker = "Future<Map<String, dynamic>?> _buildPlaybackUrl("

start_idx = old_content.find(start_marker)
end_idx = old_content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print('Failed to find in original file')
    sys.exit(1)

missing_code = old_content[start_idx:end_idx]

missing_code_fixed = missing_code.replace(
    '    _hasRestoredPosition = false;\n    await _mediaPlayer!.open(Media(url, httpHeaders: headers), play: true);',
    '    _hasRestoredPosition = false;\n    await _mediaPlayer!.open(Media(url, httpHeaders: headers), play: true);\n    \n    // Fix: Audio-only Phantom Playback\n    _mediaPlayer!.stream.tracks.listen((tracks) {\n      if (mounted && tracks.audio.isNotEmpty && tracks.video.isEmpty) {\n        print("MediaKit: Track error - Audio only detected, no video track.");\n        // We could trigger failover here, but first wait to see if video loads.\n      }\n    });'
)

insert_marker = "Future<void> _startHeadlessExtractor("
insert_idx = current_content.find(insert_marker)
if insert_idx != -1:
    current_content = current_content[:insert_idx] + missing_code_fixed + current_content[insert_idx:]
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(current_content)
    print('Restored missing functions successfully')
else:
    print('Failed to find insertion point')
