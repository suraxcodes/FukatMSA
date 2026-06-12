import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class MangaWatchlistService {
  static Future<Box> _getBox() async {
    if (Hive.isBoxOpen('mangaWatchlistBox')) {
      return Hive.box('mangaWatchlistBox');
    }
    return await Hive.openBox('mangaWatchlistBox');
  }

  static Future<void> ensureInitialized() async {
    await _getBox();
  }

  static ValueListenable<Box<dynamic>> get listenable => Hive.box('mangaWatchlistBox').listenable();

  static Future<void> toggleManga(Map<String, dynamic> manga) async {
    final box = await _getBox();
    final mangaId = manga['id'].toString();
    if (box.containsKey(mangaId)) {
      await box.delete(mangaId);
    } else {
      // Create a shallow copy to store
      final mangaToSave = Map<String, dynamic>.from(manga);
      mangaToSave['savedAt'] = DateTime.now().toIso8601String();
      await box.put(mangaId, mangaToSave);
    }
  }

  static Future<bool> isSaved(String mangaId) async {
    final box = await _getBox();
    return box.containsKey(mangaId);
  }
}
