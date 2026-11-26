import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'supabase_sync_service.dart';

class WatchlistService {
  // 🚀 Helper to lazily obtain the watchlist Hive box
  static Future<Box> _getBox() async {
    if (Hive.isBoxOpen('watchlistBox')) {
      return Hive.box('watchlistBox');
    }
    return await Hive.openBox('watchlistBox');
  }

  static Future<void> ensureInitialized() async {
    await _getBox();
  }

  static ValueListenable<Box<dynamic>> get listenable => Hive.box('watchlistBox').listenable();

  static Future<void> toggleItem(String tmdbId, String title, String? posterPath, bool isMovie, {bool isAnime = false}) async {
    final box = await _getBox();
    if (box.containsKey(tmdbId)) {
      await box.delete(tmdbId);
    } else {
      await box.put(tmdbId, {
        'tmdbId': tmdbId,
        'title': title,
        'posterPath': posterPath,
        'isMovie': isMovie,
        'isAnime': isAnime,
        'savedAt': DateTime.now().toIso8601String(),
      });
    }
    
    // Trigger background sync
    SupabaseSyncService.syncWatchlist();
  }

  static Future<bool> isSaved(String tmdbId) async {
    final box = await _getBox();
    return box.containsKey(tmdbId);
  }

  static Future<List<Map<String, dynamic>>> getAllItems() async {
    final box = await _getBox();
    final items = box.values
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
      ..sort((a, b) => DateTime.parse(b['savedAt']).compareTo(DateTime.parse(a['savedAt'])));
    return items;
  }
}
