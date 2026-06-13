import sys
import re

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Revert my bad int.parse replacement
# I'll just change widget.tmdbId back to int.parse(widget.tmdbId) where it's passed to getImdbId, getSeriesDetails, getMovieDetails, getSimilarMovies, getSimilarTvShows
content = content.replace('await TmdbService.getImdbId(\n      widget.tmdbId,', 'await TmdbService.getImdbId(\n      int.parse(widget.tmdbId),')
content = content.replace('TmdbService.getSeriesDetails(\n        widget.tmdbId,', 'TmdbService.getSeriesDetails(\n        int.parse(widget.tmdbId),')
content = content.replace('TmdbService.getMovieDetails(widget.tmdbId)', 'TmdbService.getMovieDetails(int.parse(widget.tmdbId))')
content = content.replace('TmdbService.getSimilarMovies(widget.tmdbId)', 'TmdbService.getSimilarMovies(int.parse(widget.tmdbId))')
content = content.replace('TmdbService.getSimilarTvShows(widget.tmdbId)', 'TmdbService.getSimilarTvShows(int.parse(widget.tmdbId))')

# Fix List<dynamic> for processExtractionQueue
content = content.replace('_processExtractionQueue(providersList);', '_processExtractionQueue(List<Map<String, dynamic>>.from(providersList));')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Fixed type errors!")
