import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';

class CustomRepoService {
  static const String _boxName = 'customRepoBox';
  static const String _keyUrl = 'custom_repo_url';

  static Future<Box> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }
    return await Hive.openBox(_boxName);
  }

  static Future<bool> saveRepoUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!uri.isAbsolute) return false;

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data.containsKey('active_providers') && data['active_providers'] is List) {
          final box = await _getBox();
          await box.put(_keyUrl, url);
          return true;
        }
      }
    } catch (e) {
      print('Failed to save repo url: $e');
    }
    return false;
  }

  static Future<String?> getRepoUrl() async {
    final box = await _getBox();
    return box.get(_keyUrl) as String?;
  }

  static Future<void> clearRepo() async {
    final box = await _getBox();
    await box.delete(_keyUrl);
  }

  static Future<List<dynamic>?> fetchCustomProviders() async {
    try {
      final url = await getRepoUrl();
      if (url == null) return null;

      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data.containsKey('active_providers') && data['active_providers'] is List) {
          return data['active_providers'] as List<dynamic>;
        }
      }
    } catch (e) {
      print('Failed to fetch custom providers: $e');
    }
    return null;
  }
}
