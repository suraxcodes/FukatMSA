import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'supabase_sync_service.dart';

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
    int? position,
    int? duration,
    bool isCompleted = false,
  }) async {
    await _box.put(tmdbId, {
      'tmdbId': tmdbId,
      'title': title,
      'posterPath': posterPath,
      'isMovie': isMovie,
      'lastSeason': lastSeason,
      'lastEpisode': lastEpisode,
      'position': position,
      'duration': duration,
      'isCompleted': isCompleted,
      'savedAt': DateTime.now().toIso8601String(),
    });
    
    // Trigger sync in background safely without crashing the local thread
    unawaited(
      SupabaseSyncService.syncContinueWatching().catchError((e) {
        print("Background progress sync paused: $e");
      })
    );
  }

  static Future<void> removeItem(String tmdbId) async {
    await _box.delete(tmdbId);
  }

  static Future<List<Map<String, dynamic>>> getAllItemsAsync() async {
    return await compute(_extractItems, _box);
  }

  static bool isWatched(String tmdbId) {
    if (!_box.isOpen) return false;
    final item = _box.get(tmdbId);
    if (item != null && item is Map) {
      return item['isCompleted'] == true;
    }
    return false;
  }

  static List<Map<String, dynamic>> _extractItems(Box box) {
    return box.values
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
      ..sort((a, b) => DateTime.parse(b['savedAt']).compareTo(DateTime.parse(a['savedAt'])));
  }


}



