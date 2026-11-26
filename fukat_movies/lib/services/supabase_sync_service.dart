import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../core/log.dart';
import 'supabase_auth_service.dart';

class SupabaseSyncService {
  static SupabaseClient get _supabase => Supabase.instance.client;

  /// All sync is a no-op on local-only builds.
  static bool get _enabled =>
      SupabaseAuthService.isAvailable && SupabaseAuthService.isSignedIn;

  static Timer? _debounce;
  static final Set<String> _dirtyMediaIds = {};

  /// Queue a single item to be pushed. Collapses the old behaviour of
  /// upserting *every* row every 15 seconds (which the progress timer did).
  static void queueContinueWatching(String tmdbId) {
    _dirtyMediaIds.add(tmdbId);
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), () {
      final ids = Set<String>.from(_dirtyMediaIds);
      _dirtyMediaIds.clear();
      syncContinueWatchingOnly(ids);
    });
  }

  /// Push just the given media ids.
  static Future<void> syncContinueWatchingOnly(Set<String> mediaIds) async {
    if (!_enabled || mediaIds.isEmpty) return;
    final user = SupabaseAuthService.currentUser;
    if (user == null) return;

    try {
      final box = Hive.isBoxOpen('continueWatchingBox')
          ? Hive.box('continueWatchingBox')
          : await Hive.openBox('continueWatchingBox');

      for (final id in mediaIds) {
        final raw = box.get(id);
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);
        await _supabase.from('continue_watching').upsert({
          'user_id': user.id,
          'media_id': id,
          'current_time_seconds': data['position'] ?? 0,
          'total_duration_seconds': data['duration'] ?? 0,
          'is_completed': data['isCompleted'] ?? false,
          'updated_at': data['savedAt'] ?? DateTime.now().toIso8601String(),
          'last_season': data['lastSeason'],
          'last_episode': data['lastEpisode'],
          'title': data['title'],
          'poster_path': data['posterPath'],
          'is_movie': data['isMovie'] ?? true,
        });
      }
    } catch (e) {
      Log.w('Sync', 'incremental continue-watching push failed', e);
    }
  }

  static Future<void> syncContinueWatching() async {
    if (!_enabled) return;
    final user = SupabaseAuthService.currentUser;
    if (user == null) return;

    try {
      final box = Hive.isBoxOpen('continueWatchingBox')
          ? Hive.box('continueWatchingBox')
          : await Hive.openBox('continueWatchingBox');
      final items = box.values.toList();

      for (var item in items) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          item as Map,
        );

        await _supabase.from('continue_watching').upsert({
          'user_id': user.id,
          'media_id': data['tmdbId'].toString(),
          'current_time_seconds': data['position'] ?? 0,
          'total_duration_seconds': data['duration'] ?? 0,
          'is_completed': data['isCompleted'] ?? false,
          'updated_at': data['savedAt'] ?? DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      Log.w('Sync', 'continue-watching push failed', e);
    }
  }

  static Future<void> pullContinueWatching() async {
    if (!_enabled) return;
    final user = SupabaseAuthService.currentUser;
    if (user == null) return;

    try {
      final response = await _supabase
          .from('continue_watching')
          .select()
          .eq('user_id', user.id);

      final box = Hive.isBoxOpen('continueWatchingBox')
          ? Hive.box('continueWatchingBox')
          : await Hive.openBox('continueWatchingBox');

      for (var row in response) {
        final mediaId = row['media_id'] as String;
        final remoteTime = DateTime.parse(row['updated_at'].toString());

        final localItem = box.get(mediaId);

        if (localItem != null) {
          final localMap = Map<String, dynamic>.from(localItem as Map);
          final localTime = DateTime.parse(
            localMap['savedAt']?.toString() ??
                DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
          );

          if (remoteTime.isAfter(localTime)) {
            // Remote is newer, update local
            localMap['position'] = row['current_time_seconds'];
            localMap['duration'] = row['total_duration_seconds'];
            localMap['isCompleted'] = row['is_completed'] ?? false;
            localMap['savedAt'] = remoteTime.toIso8601String();
            await box.put(mediaId, localMap);
          }
        } else {
          // Item doesn't exist locally, insert it
          // Note: we might lack some fields like title/poster here, so we might need a placeholder or fetch them later if needed.
          await box.put(mediaId, {
            'tmdbId': mediaId,
            'position': row['current_time_seconds'],
            'duration': row['total_duration_seconds'],
            'isCompleted': row['is_completed'] ?? false,
            'savedAt': remoteTime.toIso8601String(),
            'isMovie': true, // Assumed default, might need better handling
            'title': 'Synced Item',
            'posterPath': null,
          });
        }
      }
    } catch (e) {
      Log.w('Sync', 'continue-watching pull failed', e);
    }
  }

  static Future<void> syncSearchHistory() async {
    if (!_enabled) return;
    final user = SupabaseAuthService.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final textSearches = prefs.getStringList('recent_searches') ?? [];
      final openedItems = prefs.getStringList('recent_opened_items') ?? [];

      await _supabase.from('search_history').upsert({
        'user_id': user.id,
        'recent_searches': textSearches,
        'recent_opened_items': openedItems,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      Log.w('Sync', 'search history push failed', e);
    }
  }

  static Future<void> pullSearchHistory() async {
    if (!_enabled) return;
    final user = SupabaseAuthService.currentUser;
    if (user == null) return;

    try {
      final response = await _supabase
          .from('search_history')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (response != null) {
        final prefs = await SharedPreferences.getInstance();

        final remoteTextSearches = List<String>.from(
          response['recent_searches'] ?? [],
        );
        final remoteOpenedItems = List<String>.from(
          response['recent_opened_items'] ?? [],
        );

        // Merge with local avoiding duplicates (naive merge for now, prioritizing remote if conflicts)
        // For simplicity, we just overwrite local if remote exists since it acts as the source of truth
        if (remoteTextSearches.isNotEmpty) {
          await prefs.setStringList('recent_searches', remoteTextSearches);
        }
        if (remoteOpenedItems.isNotEmpty) {
          await prefs.setStringList('recent_opened_items', remoteOpenedItems);
        }
      }
    } catch (e) {
      Log.w('Sync', 'search history pull failed', e);
    }
  }

  static Future<void> syncWatchlist() async {
    if (!_enabled) return;
    final user = SupabaseAuthService.currentUser;
    if (user == null) return;

    try {
      final box = Hive.isBoxOpen('watchlistBox')
          ? Hive.box('watchlistBox')
          : await Hive.openBox('watchlistBox');
      final items = box.values.toList();

      for (var item in items) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          item as Map,
        );

        await _supabase.from('watchlist').upsert({
          'user_id': user.id,
          'media_id': data['tmdbId'].toString(),
          'title': data['title'],
          'poster_path': data['posterPath'],
          'is_movie': data['isMovie'] ?? true,
          'updated_at': data['savedAt'] ?? DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      Log.w('Sync', 'watchlist push failed', e);
    }
  }

  static Future<void> pullWatchlist() async {
    if (!_enabled) return;
    final user = SupabaseAuthService.currentUser;
    if (user == null) return;

    try {
      final response = await _supabase
          .from('watchlist')
          .select()
          .eq('user_id', user.id);

      final box = Hive.isBoxOpen('watchlistBox')
          ? Hive.box('watchlistBox')
          : await Hive.openBox('watchlistBox');

      for (var row in response) {
        final mediaId = row['media_id'] as String;
        final remoteTime = DateTime.parse(row['updated_at'].toString());

        final localItem = box.get(mediaId);

        if (localItem != null) {
          final localMap = Map<String, dynamic>.from(localItem as Map);
          final localTime = DateTime.parse(
            localMap['savedAt']?.toString() ??
                DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
          );

          if (remoteTime.isAfter(localTime)) {
            localMap['savedAt'] = remoteTime.toIso8601String();
            await box.put(mediaId, localMap);
          }
        } else {
          await box.put(mediaId, {
            'tmdbId': mediaId,
            'title': row['title'],
            'posterPath': row['poster_path'],
            'isMovie': row['is_movie'] ?? true,
            'savedAt': remoteTime.toIso8601String(),
          });
        }
      }
    } catch (e) {
      Log.w('Sync', 'watchlist pull failed', e);
    }
  }
}
