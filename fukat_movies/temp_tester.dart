import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print("\n==========================================");
  print("🎬 Fukat MSA - VPN Infrastructure Tester");
  print("==========================================\n");

  const String testTmdbId = "550"; // Fight Club

  final Map<String, String> providers = {
    "Embed.su": "https://embed.su/embed/movie/{id}",
    "VidSrc.rip (VRF)": "https://vidsrc.rip/embed/movie/{id}",
    "VidSrc.icu": "https://vidsrc.icu/embed/movie/{id}",
    "LordFlix (New)": "https://snowhouse.lordflix.club/movie/{id}",
    "VidLink": "https://vidlink.pro/movie/{id}",
    "Braflix (so)": "https://embed.braflix.so/movie/{id}",
    "Braflix (video)": "https://braflix.video/movie/{id}",
    "SFlix Embed (se)": "https://embed.sflix.se/movie/{id}",
    "SFlix (to)": "https://sflix.to/movie/{id}",
    "FlixHQ (to)": "https://flixhq.to/ajax/movie/get_sources/{id}",
  };

  print("Pinging providers through your VPN...\n");
  for (var entry in providers.entries) {
    await testIframeProvider(
      providerName: entry.key,
      urlTemplate: entry.value,
      tmdbId: testTmdbId,
    );
  }
}

Future<void> testIframeProvider({
  required String providerName,
  required String urlTemplate,
  required String tmdbId,
}) async {
  final String testUrl = urlTemplate.replaceAll('{id}', tmdbId);
  
  try {
    Map<String, String> requestHeaders = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    };
    if (providerName.contains("Braflix")) {
      requestHeaders['Referer'] = 'https://braflix.so/';
    } else if (providerName.contains("SFlix")) {
      requestHeaders['Referer'] = 'https://sflix.to/';
    } else if (providerName.contains("Embed.su")) {
      requestHeaders['Referer'] = 'https://embed.su/';
    } else if (providerName.contains("VidSrc.rip")) {
      requestHeaders['Referer'] = 'https://vidsrc.rip/';
    } else if (providerName.contains("VidSrc.icu")) {
      requestHeaders['Referer'] = 'https://vidsrc.icu/';
    } else if (providerName.contains("LordFlix")) {
      requestHeaders['Referer'] = 'https://snowhouse.lordflix.club/';
    }

    final response = await http.get(Uri.parse(testUrl), headers: requestHeaders).timeout(const Duration(seconds: 15)); 

    if (response.statusCode == 200) {
      print("✅ [ONLINE] $providerName");
    } else if (response.statusCode == 403) {
      print("⚠️ [BLOCKED] $providerName (Status 403 Forbidden - Cloudflare, will work in WebView)");
    } else if (response.statusCode == 404) {
      print("❌ [OFFLINE] $providerName (Status 404 Not Found)");
    } else {
      print("❓ [UNKNOWN] $providerName (Status ${response.statusCode})");
    }
  } catch (e) {
    print("❌ [DEAD] $providerName (Exception: $e)");
  }
}
