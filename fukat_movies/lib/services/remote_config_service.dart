import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'custom_repo_service.dart';
import 'package:flutter/services.dart' show rootBundle;

class RemoteConfigService {
  // Load providers from bundled asset (assets/remote_config.json)
  static const String _assetPath = 'assets/remote_config.json';


  static List<dynamic> _activeProviders = [];

  static List<dynamic> get activeProviders => _activeProviders;

  static Future<void> initializeConfig() async {
    try {
      final customProviders = await CustomRepoService.fetchCustomProviders();
      if (customProviders != null && customProviders.isNotEmpty) {
        _activeProviders = customProviders;
        print("Successfully loaded ${_activeProviders.length} providers from CUSTOM remote config.");
        return;
      }

       try {
         final jsonString = await rootBundle.loadString(_assetPath);
         final data = json.decode(jsonString);
         if (data['active_providers'] != null) {
           _activeProviders = data['active_providers'];
           print("✅ Loaded ${_activeProviders.length} providers from bundled asset.");
         } else {
           print('⚠️ No active_providers in asset config.');
         }
       } catch (e) {
         print('❌ Failed to load bundled asset config: $e');
         _loadFallbackConfig();
       }
    } catch (e) {
      print("Error fetching remote config: $e");
      _loadFallbackConfig();
    }
  }

   // Fallback: If bundled asset fails, keep providers empty (already logged).
   static void _loadFallbackConfig() {
     print('⚠️ No providers loaded after fallback attempt.');
     _activeProviders = [];
   }
}
