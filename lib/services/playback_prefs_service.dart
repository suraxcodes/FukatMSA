/// Remembers per-title playback preferences so an anime opened in Japanese +
/// subs stays that way across episodes and app restarts.
///
/// Stored in a Hive box `playbackPrefsBox`, keyed by the TMDB id. Values are
/// JSON maps like `{ "audioLang": "ja", "subtitleLang": "en", "isDub": false }`.
library;

import 'package:hive_flutter/hive_flutter.dart';

class PlaybackPrefsService {
  PlaybackPrefsService._();

  static const String _boxName = 'playbackPrefsBox';

  static Future<dynamic> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  /// Key for a title: `movie_<tmdbId>` or `series_<tmdbId>`.
  static String _key(String type, dynamic tmdbId) => '${type}_$tmdbId';

  /// Save the user's audio/subtitle/dub choice for a title.
  static Future<void> save({
    required bool isMovie,
    required dynamic tmdbId,
    String? audioLang,
    String? subtitleLang,
    bool? isDub,
  }) async {
    final box = await _box();
    final existing =
        (box.get(_key(isMovie ? 'movie' : 'series', tmdbId)) as Map?) ?? {};
    await box.put(
      _key(isMovie ? 'movie' : 'series', tmdbId),
      {
        ...existing,
        if (audioLang != null) 'audioLang': audioLang,
        if (subtitleLang != null) 'subtitleLang': subtitleLang,
        if (isDub != null) 'isDub': isDub,
      }..removeWhere((_, v) => v == null),
    );
  }

  /// Load saved preferences for a title. Returns an empty map when none saved.
  static Map<String, dynamic> load({
    required bool isMovie,
    required dynamic tmdbId,
  }) {
    // Synchronous read — Hive boxes are read-through from disk.
    final box = Hive.isBoxOpen(_boxName) ? Hive.box(_boxName) : null;
    final raw = box?.get(_key(isMovie ? 'movie' : 'series', tmdbId));
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  /// Clear preferences for a title (e.g. when the user resets them).
  static Future<void> clear({
    required bool isMovie,
    required dynamic tmdbId,
  }) async {
    final box = await _box();
    await box.delete(_key(isMovie ? 'movie' : 'series', tmdbId));
  }
}
