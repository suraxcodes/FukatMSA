import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ContinueWatchingService {
  static final _box = Hive.box('continueWatchingBox');

  static ValueListenable<Box> get listenable => _box.listenable();

  static Future<void> saveItem({
    required String tmdbId,
    required String title,
    required String? posterPath,
    required bool isMovie,
    int? lastSeason,
    int? lastEpisode,
  }) async {
    await _box.put(tmdbId, {
      'tmdbId': tmdbId,
      'title': title,
      'posterPath': posterPath,
      'isMovie': isMovie,
      'lastSeason': lastSeason,
      'lastEpisode': lastEpisode,
      'savedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> removeItem(String tmdbId) async {
    await _box.delete(tmdbId);
  }

  static Future<List<Map<String, dynamic>>> getAllItemsAsync() async {
    return await compute(_extractItems, _box);
  }

  static List<Map<String, dynamic>> _extractItems(Box box) {
    return box.values
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
      ..sort((a, b) => DateTime.parse(b['savedAt']).compareTo(DateTime.parse(a['savedAt'])));
  }


}
