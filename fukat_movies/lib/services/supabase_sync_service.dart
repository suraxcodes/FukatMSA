import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'supabase_auth_service.dart';

class SupabaseSyncService {
  static final _supabase = Supabase.instance.client;

  static Future<void> syncContinueWatching() async {
    final user = SupabaseAuthService.currentUser;
    if (user == null) return;

    try {
      final box = Hive.isBoxOpen('continueWatchingBox') ? Hive.box('continueWatchingBox') : await Hive.openBox('continueWatchingBox');
      final items = box.values.toList();
      
      for (var item in items) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(item as Map);
        
        await _supabase.from('continue_watching').upsert({
          'user_id': user.id,
          'media_id': data['tmdbId'].toString(),
          'current_time_seconds': data['position'] ?? 0,
          'total_duration_seconds': data['duration'] ?? 0,
          'updated_at': data['savedAt'] ?? DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      print('Sync Error: $e');
    }
  }

  static Future<void> pullContinueWatching() async {
    final user = SupabaseAuthService.currentUser;
    if (user == null) return;

    try {
      final response = await _supabase
          .from('continue_watching')
          .select()
          .eq('user_id', user.id);

      final box = Hive.isBoxOpen('continueWatchingBox') ? Hive.box('continueWatchingBox') : await Hive.openBox('continueWatchingBox');

      for (var row in response) {
        final mediaId = row['media_id'] as String;
        final remoteTime = DateTime.parse(row['updated_at'].toString());
        
        final localItem = box.get(mediaId);
        
        if (localItem != null) {
          final localMap = Map<String, dynamic>.from(localItem as Map);
          final localTime = DateTime.parse(localMap['savedAt']?.toString() ?? DateTime.fromMillisecondsSinceEpoch(0).toIso8601String());
          
          if (remoteTime.isAfter(localTime)) {
            // Remote is newer, update local
            localMap['position'] = row['current_time_seconds'];
            localMap['duration'] = row['total_duration_seconds'];
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
            'savedAt': remoteTime.toIso8601String(),
            'isMovie': true, // Assumed default, might need better handling
            'title': 'Synced Item',
            'posterPath': null,
          });
        }
      }
    } catch (e) {
      print('Pull Error: $e');
    }
  }
}
