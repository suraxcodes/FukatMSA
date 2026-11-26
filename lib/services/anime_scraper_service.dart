import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:async';
import 'dart:convert';

/// A service to scrape anime streaming links directly on the client side
/// using a Headless WebView. This bypasses typical Cloudflare/DDoS protections
/// because it acts as a real browser.
class AnimeScraperService {
  HeadlessInAppWebView? _headlessWebView;

  /// Scrapes the actual streaming URL (like an .m3u8 or embed URL) from an anime episode page.
  /// Example: scrapeEpisode('https://gogoanime3.co/naruto-episode-1')
  Future<String?> scrapeEpisode(String episodeUrl) async {
    Completer<String?> completer = Completer();

    _headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(episodeUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      ),
      onLoadStop: (controller, url) async {
        print("🌐 [AnimeScraper] Finished loading: $url");
        
        // Inject JavaScript to extract the video source.
        // We will also print a snippet of the page text to see if Cloudflare blocked us.
        String? extractedUrl = await controller.evaluateJavascript(source: """
          (function() {
             console.log("Evaluating JS on " + window.location.href);
             
             // 1. Try to find a standard video tag
             let video = document.querySelector('video source');
             if (video && video.src) return video.src;
             
             // 2. Try to find an iframe (commonly used for vidstreaming/goload)
             let iframe = document.querySelector('.play-video iframe') || document.querySelector('iframe');
             if (iframe && iframe.src) return iframe.src;
             
             // 3. Try finding .m3u8 in the raw HTML scripts as a fallback
             let scripts = document.querySelectorAll('script');
             for (let script of scripts) {
                 let text = script.innerHTML;
                 let match = text.match(/(https?:\\/\\/[^"']*\\.m3u8[^"']*)/);
                 if (match) return match[1];
             }
             
             return null;
          })();
        """);
        
         if (extractedUrl != null && !completer.isCompleted) {
            print("🎉 [AnimeScraper] Found video in DOM: $extractedUrl");
            completer.complete(extractedUrl);
        } else {
            // If nothing is found, we evaluate JS to grab the body text for debugging
            String? pageText = await controller.evaluateJavascript(source: "document.body ? document.body.innerText.substring(0, 100) : 'No Body';");
            print("No video found yet. Page snippet: $pageText");
        }
      },
      onConsoleMessage: (controller, consoleMessage) {
        print("💻 [AnimeScraper-Console]: \${consoleMessage.message}");
      },
      onLoadError: (controller, url, code, message) {
        print("🛑 [AnimeScraper] Load Error: $message (Code: $code) at URL: $url");
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );

    try {
      await _headlessWebView?.run();
      
      // Wait for the scraping to finish with a 15-second timeout
      String? result = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
      
      return result;
    } catch (e) {
      print("Scraping error: $e");
      return null;
    } finally {
      await _headlessWebView?.dispose();
    }
  }
}
