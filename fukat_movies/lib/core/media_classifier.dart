/// Pure classification helpers, kept out of widgets and controllers so they can
/// be unit-tested without Hive, network or a widget tree.
library;

class MediaClassifier {
  MediaClassifier._();

  /// True when a series should be treated as anime.
  ///
  /// Rule: Japanese origin, or the TMDB "Animation" genre.
  ///
  /// The old check additionally required a provider with
  /// `engine == 'native_miruro'` to exist. That engine is gone, so anime mode
  /// never activated and anime titles were resolved against movie providers
  /// (wrong URLs, no episodes). Classification must not depend on which
  /// providers happen to be configured.
  static bool isAnime(Map<String, dynamic>? details, {required bool isMovie}) {
    if (isMovie || details == null) return false;

    final origin = details['origin_country'];
    if (origin is List && origin.map((c) => c.toString()).contains('JP')) {
      return true;
    }

    final genres = details['genres'];
    if (genres is List) {
      return genres.any(
        (g) => g is Map && (g['name']?.toString().toLowerCase() == 'animation'),
      );
    }
    return false;
  }

  /// Seasons that have actually started airing (7-day grace for timezone
  /// leaks and early releases).
  static List<String> availableSeasons(Map<String, dynamic>? details) {
    final seasons = details?['seasons'];
    if (seasons is! List) return const [];
    final cutoff = DateTime.now().add(const Duration(days: 7));
    final out = <String>[];
    for (final season in seasons) {
      if (season is! Map) continue;
      final number = season['season_number'];
      if (number is! int || number <= 0) continue;
      final airDate = DateTime.tryParse('${season['air_date'] ?? ''}');
      if (airDate != null && airDate.isAfter(cutoff)) continue;
      out.add(number.toString());
    }
    return out;
  }

  /// season number -> episode count.
  static Map<String, int> episodeCounts(Map<String, dynamic>? details) {
    final seasons = details?['seasons'];
    if (seasons is! List) return const {};
    return {
      for (final season in seasons.whereType<Map>())
        if (season['season_number'] is int && season['episode_count'] is int)
          '${season['season_number']}': season['episode_count'] as int,
    };
  }
}
