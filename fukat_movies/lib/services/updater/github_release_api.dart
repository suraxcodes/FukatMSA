import 'dart:convert';
import 'package:http/http.dart' as http;

class GitHubReleaseApi {
  static const String repoUrl = "https://api.github.com/repos/suraxcodes/FukatMSA/releases/latest";

  /// Fetches the latest release from GitHub.
  /// Returns a Map containing 'version', 'notes', and 'downloadUrl', or null if failed.
  static Future<Map<String, dynamic>?> getLatestRelease() async {
    try {
      final response = await http.get(Uri.parse(repoUrl), headers: {
        "Accept": "application/vnd.github.v3+json",
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tagName = data['tag_name'] as String;
        final body = data['body'] as String? ?? "No release notes provided.";
        
        String? downloadUrl;
        final assets = data['assets'] as List<dynamic>? ?? [];
        for (var asset in assets) {
          final name = asset['name'] as String;
          if (name.toLowerCase().endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'] as String;
            break;
          }
        }

        if (downloadUrl != null) {
          return {
            'version': tagName,
            'notes': body,
            'downloadUrl': downloadUrl,
          };
        }
      }
      return null;
    } catch (e) {
      print("GitHubReleaseApi error: $e");
      return null;
    }
  }
}
