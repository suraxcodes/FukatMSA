import sys

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix int.parse(widget.tmdbId) at line 336
content = content.replace('''      final imdbId = await TmdbService.getImdbId(
        widget.tmdbId,
        widget.isMovie,
      );''', '''      final imdbId = await TmdbService.getImdbId(
        int.parse(widget.tmdbId),
        widget.isMovie,
      );''')

# Fix _changeSubtitle
content = content.replace('''  void _changeSubtitle(SubtitleTrack track) {
    if (_mediaPlayer == null) return;

    setState(() {
      _selectedSubtitleTrack = track;
    }
}''', '''  void _changeSubtitle(SubtitleTrack track) {
    if (_mediaPlayer == null) return;

    setState(() {
      _selectedSubtitleTrack = track;
    });

    _mediaPlayer!.setSubtitleTrack(track);
  }
}''')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Applied final fixes!")
