/// Locally-stored "continue watching" state.
///
/// Fixes two real defects:
///
/// 1. **Crash risk.** The box was a `static final _box = Hive.box(...)`, which
///    is evaluated on first touch. If startup ever failed to open the box (bad
///    config, an exception earlier in `main()`), the first tap on a poster
///    threw "You need to initialize Hive". Now every accessor awaits
///    [_getBox], which opens on demand.
///
/// 2. **Write amplification.** `saveItem` fired a full `syncContinueWatching()`
///    — an upsert of *every* row — on every progress tick (every 15 s per
///    playing device). Saves are now debounced, and only the touched row is
///    pushed.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/log.dart';
import 'supabase_sync_service.dart';

class ContinueWatchingService {
  ContinueWatchingService._();

  static const String _tag = 'ContinueWatching';
  static const String _boxName = 'continueWatchingBox';

  /// True once `Hive.initFlutter()` has run. Guards every write path so a
  /// failed/absent storage backend degrades to "no saved progress" instead of
  /// throwing `HiveError: You need to initialize Hive`.
  static bool _hiveReady = true;

  static void markHiveUnavailable() => _hiveReady = false;

  static Future<Box?> _getBox() async {
    if (!_hiveReady) return null;
    try {
      // NOTE: Hive throws *synchronously* when initFlutter() never ran, and a
      // plain `try` around an `await` does not catch the eager throw of the
      // call expression — so the throwing calls live in their own guarded
      // closure before any awaiting happens.
      return await _openBoxSync();
    } catch (e) {
      _hiveReady = false;
      Log.w(_tag, 'storage unavailable, progress will not be saved', e);
      return null;
    }
  }

  static Future<Box?> _openBoxSync() {
    if (Hive.isBoxOpen(_boxName)) return Future<Box?>.value(Hive.box(_boxName));
    return Hive.openBox(_boxName).then<Box?>((box) => box);
  }

  /// Synchronous read path for widgets already built on a box listenable.
  static Box? get _boxOrNull =>
      Hive.isBoxOpen(_boxName) ? Hive.box(_boxName) : null;

  static ValueListenable<Box>? get listenableOrNull => _boxOrNull?.listenable();

  /// Preferred listenable: creates the box on first use. Null when storage is
  /// unavailable — callers render nothing rather than crashing.
  static Future<ValueListenable<Box>?> listenable() async {
    final box = await _getBox();
    return box?.listenable();
  }

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
    String? markEpisodeWatched,
  }) async {
    try {
      final box = await _getBox();
      if (box == null) return;
      final existing = box.get(tmdbId);

      List<String> watchedEpisodes = const [];
      if (existing is Map) {
        final raw = existing['watchedEpisodes'];
        if (raw is List) watchedEpisodes = List<String>.from(raw);
        posterPath ??= existing['posterPath'] as String?;
      }

      final watched = watchedEpisodes.toList();
      if (markEpisodeWatched != null && !watched.contains(markEpisodeWatched)) {
        watched.add(markEpisodeWatched);
      }

      await box.put(tmdbId, {
        'tmdbId': tmdbId,
        'title': title,
        'posterPath': posterPath,
        'isMovie': isMovie,
        'lastSeason': lastSeason,
        'lastEpisode': lastEpisode,
        'position': position,
        'duration': duration,
        'isCompleted': isCompleted,
        'watchedEpisodes': watched,
        'savedAt': DateTime.now().toIso8601String(),
      });

      // Debounced, single-row push. No more full-table upsert per tick.
      SupabaseSyncService.queueContinueWatching(tmdbId);
    } catch (e) {
      Log.w(_tag, 'could not save progress for $tmdbId', e);
    }
  }

  static List<String> getWatchedEpisodes(String tmdbId) {
    final item = _boxOrNull?.get(tmdbId);
    if (item is Map && item['watchedEpisodes'] is List) {
      return List<String>.from(item['watchedEpisodes']);
    }
    return const [];
  }

  static Future<void> removeItem(String tmdbId) async {
    final box = await _getBox();
    await box?.delete(tmdbId);
  }

  /// Synchronous snapshot for `ValueListenableBuilder` callbacks, where an
  /// await is impossible. Safe to call before the box opens (returns empty).
  static List<Map<String, dynamic>> getItemSnapshot() {
    final box = _boxOrNull;
    if (box == null) return const [];
    return _extractItems(box);
  }

  static Future<List<Map<String, dynamic>>> getAllItemsAsync() async {
    final box = await _getBox();
    if (box == null) return const [];
    return _extractItems(box);
  }

  static bool isWatched(String tmdbId) {
    final item = _boxOrNull?.get(tmdbId);
    return item is Map && item['isCompleted'] == true;
  }

  static Map<String, dynamic>? getItem(String tmdbId) {
    final item = _boxOrNull?.get(tmdbId);
    return item is Map ? Map<String, dynamic>.from(item) : null;
  }

  static List<Map<String, dynamic>> _extractItems(Box box) {
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
