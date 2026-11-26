import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'custom_repo_service.dart';
import 'package:flutter/services.dart' show rootBundle;

class RemoteConfigService {
  // Load providers from bundled asset (assets/remote_config.json)
  static const String _assetPath = 'assets/remote_config.json';

  static List<dynamic> _activeProviders = [];

  static List<dynamic> get activeProviders => _activeProviders;

  // Hidden Global Remote URL: 
  // Stored in your assets/.env file so it never goes to GitHub!
  static String get _globalRemoteUrl => dotenv.env['REMOTE_CONFIG_URL'] ?? '';

  static Future<void> initializeConfig() async {
    try {
      // 1. Try fetching from the Global Hidden URL first
      if (_globalRemoteUrl.isNotEmpty) {
        try {
          final res = await http.get(Uri.parse(_globalRemoteUrl)).timeout(const Duration(seconds: 5));
          if (res.statusCode == 200) {
            final data = json.decode(res.body);
            if (data['active_providers'] != null) {
              var globalProviders = data['active_providers'] as List<dynamic>;
              if (Platform.isWindows) {
                globalProviders = globalProviders.where((p) {
                  final movieUrl = p['movie_url']?.toString() ?? '';
                  final tvUrl = p['tv_url']?.toString() ?? '';
                  bool isVidsrc = (movieUrl.contains('vidsrc') || tvUrl.contains('vidsrc')) && p['engine'] != 'native_extractor';
                  return !isVidsrc;
                }).toList();
              }
              _activeProviders = globalProviders;
              print("Successfully loaded ${_activeProviders.length} providers from GLOBAL hidden remote config.");
              return;
            }
          }
        } catch (e) {
          print("Failed to fetch global remote config: $e");
        }
      }

      // 2. Try fetching from user's custom providers (if any)
      final customProviders = await CustomRepoService.fetchCustomProviders();
      if (customProviders != null && customProviders.isNotEmpty) {
        var custom = customProviders;
        if (Platform.isWindows) {
          custom = custom.where((p) {
            final movieUrl = p['movie_url']?.toString() ?? '';
            final tvUrl = p['tv_url']?.toString() ?? '';
            bool isVidsrc =
                (movieUrl.contains('vidsrc') || tvUrl.contains('vidsrc')) &&
                p['engine'] != 'native_extractor';
            return !isVidsrc;
          }).toList();
        }
        _activeProviders = custom;
        print(
          "Successfully loaded ${_activeProviders.length} providers from CUSTOM remote config.",
        );
        return;
      }

      try {
        final jsonString = await rootBundle.loadString(_assetPath);
        final data = json.decode(jsonString);
        if (data['active_providers'] != null) {
          var providers = data['active_providers'] as List<dynamic>;

          if (Platform.isWindows) {
            providers = providers.where((p) {
              final movieUrl = p['movie_url']?.toString() ?? '';
              final tvUrl = p['tv_url']?.toString() ?? '';
              bool isVidsrc =
                  (movieUrl.contains('vidsrc') || tvUrl.contains('vidsrc')) &&
                  p['engine'] != 'native_extractor';
              if (isVidsrc) {
                print(
                  "⚠️ Removing incompatible provider on Windows: ${p['name']}",
                );
              }
              return !isVidsrc;
            }).toList();
          }

          _activeProviders = providers;
          print(
            "✅ Loaded ${_activeProviders.length} providers from bundled asset.",
          );
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
