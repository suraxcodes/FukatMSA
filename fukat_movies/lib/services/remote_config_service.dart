import 'dart:convert';
import 'package:http/http.dart' as http;
import 'custom_repo_service.dart';

class RemoteConfigService {
  // Replace this with your actual Pastebin/Gist Raw URL containing remote_config.json
  static const String _configUrl = "https://raw.githubusercontent.com/suraxcodes/FukatMSA/main/remote_config.json";


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

      final response = await http.get(Uri.parse(_configUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['active_providers'] != null) {
          _activeProviders = data['active_providers'];
          print("Successfully loaded ${_activeProviders.length} providers from DEFAULT remote config.");
        }
      } else {
        print("Failed to load remote config. Status code: ${response.statusCode}");
        _loadFallbackConfig();
      }
    } catch (e) {
      print("Error fetching remote config: $e");
      _loadFallbackConfig();
    }
  }

  // Fallback disabled per user request: forces the app to fetch from the URL
  static void _loadFallbackConfig() {
    print("Fallback disabled. Ensure the remote_config.json URL is valid.");
    _activeProviders = [];
  }
}
