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

  /// Null-safe listenable for widgets that may build before the box opens.
  static ValueListenable<Box<dynamic>>? get listenableOrNull =>
      Hive.isBoxOpen('watchlistBox')
      ? Hive.box('watchlistBox').listenable()
      : null;

  static ValueListenable<Box<dynamic>> get listenable =>
      Hive.box('watchlistBox').listenable();

  static Future<void> toggleItem(
    String tmdbId,
    String title,
    String? posterPath,
    bool isMovie, {
    bool isAnime = false,
  }) async {
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
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    items.sort((a, b) {
      final aDate = DateTime.tryParse('${a['savedAt'] ?? ''}');
      final bDate = DateTime.tryParse('${b['savedAt'] ?? ''}');
      if (aDate == null || bDate == null) return 0;
      return bDate.compareTo(aDate);
    });
    return items;
  }
}
