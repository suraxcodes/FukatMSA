import 'dart:convert';
import 'package:http/http.dart' as http;

/// =========================================================================
/// 🏴‍☠️ Fukat MSA - Ultimate Streaming Infrastructure Registry Tester
/// =========================================================================
/// Run this script using:
/// dart run test/scraper_tester.dart

void main() async {
  print("\n==========================================");
  print("🎬 Fukat MSA - Infrastructure Tester");
  print("==========================================\n");

  const String testTmdbId = "550"; // Fight Club (Movie)
  const String testImdbId = "tt0137523"; 
  const String testSeason = "1";
  const String testEpisode = "1";

  // 1. TEST SELF-HOSTED SCRAPER APIS
  print("=== PART 1: SELF-HOSTED NATIVE SCRAPERS ===");
  // Note: Replace these with your deployed Vercel/Render/Railway URLs!
  await testNativeScraper(
    scraperName: "CinePro Core",
    apiUrl: "https://your-cinepro-deployment.vercel.app/api/stream?id=$testTmdbId",
  );
  
  await testNativeScraper(
    scraperName: "TMDB Embed API",
    apiUrl: "https://your-tmdb-embed-deployment.onrender.com/movie/$testTmdbId",
  );

  await testNativeScraper(
    scraperName: "VidSrc Playwright Scraper",
    apiUrl: "https://your-playwright-deployment.up.railway.app/vidsrc/$testTmdbId",
  );

  print("\n=== PART 2: GLOBAL IFRAME & EMBED PROVIDER MATRIX ===");
  
  final Map<String, String> providers = {
    // Tier 1
    "VidLink": "https://vidlink.pro/movie/{id}",
    "VidSrc To": "https://vidsrc.to/embed/movie/{id}",
    "AutoEmbed": "https://player.autoembed.cc/movie/{id}",
    // Tier 2
    "MultiEmbed": "https://multiembed.mov/?video_id={id}&tmdb=1",
    "SmashyStream": "https://embed.smashystream.com/playere.php?tmdb={id}",
    "VixSrc": "https://vixsrc.to/embed/movie/{id}",
    "NoTorrent": "https://embed.notorrent.club/movie/{id}",
    // Tier 3
    "GhostIndex": "https://ghostindex.one/api/movie/{id}",
    "HydraStream": "https://hydrastream.lol/embed/movie/{id}",
    "VidSrc In": "https://vidsrc.in/embed/movie/{id}",
    "VidSrc CC": "https://vidsrc.cc/v2/embed/movie/{id}",
    "Videasy": "https://videasy.xyz/embed/movie/{id}",
    "SuperEmbed": "https://superembed.org/?video_id={id}&tmdb=1",
    "Showbox/FebBox": "https://www.febbox.pro/file/player?id={id}",
    "4KHDHub": "https://4khdhub.to/embed/movie/{id}",
    "DahmerMovies": "https://dahmermovies.com/embed/movie/{id}",
  };

  print("Pinging providers to verify domain uptime...\n");
  for (var entry in providers.entries) {
    await testIframeProvider(
      providerName: entry.key,
      urlTemplate: entry.value,
      tmdbId: testTmdbId,
    );
  }
}

/// Tests a self-hosted API scraper by sending a GET request and expecting JSON
Future<void> testNativeScraper({required String scraperName, required String apiUrl}) async {
  print("🧪 Testing Scraper: $scraperName");
  
  if (apiUrl.contains('your-')) {
    print("   ⚠️ Skipped: URL not configured (Please update the URL in this script).");
    return;
  }

  try {
    final response = await http.get(Uri.parse(apiUrl));
    if (response.statusCode == 200) {
      print("   ✅ SUCCESS! Status 200 OK.");
      try {
        final data = jsonDecode(response.body);
        print("   ✅ Valid JSON received: ${data.toString().substring(0, data.toString().length > 100 ? 100 : data.toString().length)}...");
      } catch (e) {
        print("   ❌ Error: Response was not valid JSON.");
      }
    } else {
      print("   ❌ FAILED! Status: ${response.statusCode}");
    }
  } catch (e) {
    print("   ❌ ERROR connecting to server: $e");
  }
}

/// Tests an Iframe/Webview provider by pinging the URL to see if the domain is alive
Future<void> testIframeProvider({
  required String providerName,
  required String urlTemplate,
  required String tmdbId,
}) async {
  // Replace the {id} token with our test TMDB ID
  final String testUrl = urlTemplate.replaceAll('{id}', tmdbId);
  
  try {
    // We use a GET request. Even though it's an iframe, we expect a 200 OK (HTML document).
    final response = await http.get(Uri.parse(testUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    }).timeout(const Duration(seconds: 10)); // 10 second timeout

    if (response.statusCode == 200) {
      print("✅ [ONLINE] $providerName");
    } else if (response.statusCode == 403) {
      print("⚠️ [BLOCKED] $providerName (Status 403 Forbidden - Likely Cloudflare, but iframe might still work in app)");
    } else if (response.statusCode == 404) {
      print("❌ [OFFLINE] $providerName (Status 404 Not Found)");
    } else {
      print("❓ [UNKNOWN] $providerName (Status ${response.statusCode})");
    }
  } catch (e) {
    print("❌ [DEAD] $providerName (Domain unreachable or timeout)");
  }
}
