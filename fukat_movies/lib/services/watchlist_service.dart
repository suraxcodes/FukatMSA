import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class WatchlistService {
  static final _box = Hive.box('watchlistBox');

  static ValueListenable<Box> get listenable => _box.listenable();

  static Future<void> toggleItem(String tmdbId, String title, String? posterPath, bool isMovie) async {
    if (_box.containsKey(tmdbId)) {
      await _box.delete(tmdbId);
    } else {
      await _box.put(tmdbId, {
        'tmdbId': tmdbId,
        'title': title,
        'posterPath': posterPath,
        'isMovie': isMovie,
        'savedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  static bool isSaved(String tmdbId) {
    return _box.containsKey(tmdbId);
  }

  static List<Map<String, dynamic>> getAllItems() {
    return _box.values.map((item) => Map<String, dynamic>.from(item)).toList()
      ..sort((a, b) => DateTime.parse(b['savedAt']).compareTo(DateTime.parse(a['savedAt'])));
  }
}
