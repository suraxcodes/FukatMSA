import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MiruroScraperService {
  static const String _pipeUrl = "https://www.miruro.tv/api/secure/pipe";

  static Future<String?> _fetchViaWebView(Uri uri) async {
    final completer = Completer<String?>();
    HeadlessInAppWebView? headlessWebView;

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(uri.toString())),
      initialSettings: InAppWebViewSettings(
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36",
        javaScriptEnabled: true,
        transparentBackground: true,
      ),
      onLoadStart: (controller, url) {
        print("MiruroScraperService: WebView onLoadStart -> $url");
      },
      onProgressChanged: (controller, progress) {
        print("MiruroScraperService: WebView progress -> $progress%");
      },
      onLoadStop: (controller, url) async {
        if (completer.isCompleted) return;
        try {
          // Get the full raw HTML to see what the WebView is actually rendering
          final text = await controller.evaluateJavascript(source: "document.documentElement.outerHTML") as String?;
          
          print("MiruroScraperService: onLoadStop HTML: ${text != null ? text.substring(0, text.length < 200 ? text.length : 200) : 'null'}...");

          if (text != null) {
            // Check if it's the Cloudflare challenge page
            if (text.contains("Just a moment") || text.contains("Checking your browser") || text.contains("cf-turnstile")) {
              print("MiruroScraperService: Waiting for Cloudflare challenge...");
              return; // Wait for the next onLoadStop after challenge completes
            }
            
            // If we see JSON fields in the raw HTML, extract it!
            if (text.contains('"path":"episodes"') || text.contains('"watch"')) {
              // Extract just the JSON from the HTML (it's inside a <pre> tag usually)
              final innerText = await controller.evaluateJavascript(source: "document.body.innerText") as String?;
              if (innerText != null && innerText.trim().startsWith("{")) {
                completer.complete(innerText.trim());
                return;
              }
            }
            
            if (text.contains("ERROR_444") || text.contains("403 Forbidden")) {
              print("MiruroScraperService: Access Denied / 444 by Cloudflare");
              completer.complete(null);
            }
          }
        } catch (e) {
          print("MiruroScraperService: Exception in onLoadStop - \$e");
        }
      },
      onLoadError: (controller, url, code, message) {
        print("MiruroScraperService: WebView load error - " + (message ?? ""));
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    
    await headlessWebView.run();
    
    // Timeout mechanism
    Future.delayed(const Duration(seconds: 25), () {
      if (!completer.isCompleted) {
        print("MiruroScraperService: WebView absolute timeout (25s)");
        completer.complete(null);
      }
    });

    final output = await completer.future;
    headlessWebView?.dispose();
    return output;
  }

  /// Encode payload to Base64 format expected by Miruro Pipe
  static String _encodePipeRequest(Map<String, dynamic> payload) {
    final jsonString = json.encode(payload);
    final bytes = utf8.encode(jsonString);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Decode Miruro Pipe response (Base64 URL Safe -> GZip -> JSON)
  static Map<String, dynamic> _decodePipeResponse(String encodedStr) {
    String normalized = encodedStr;
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    final compressedBytes = base64Url.decode(normalized);
    final decompressedBytes = GZipCodec().decode(compressedBytes);
    final jsonString = utf8.decode(decompressedBytes);
    return json.decode(jsonString);
  }

  /// Helper to decode episode IDs
  static String _translateId(String encodedId) {
    try {
      String normalized = encodedId;
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final decoded = utf8.decode(base64Url.decode(normalized));
      if (decoded.contains(':')) {
        return decoded;
      }
      return encodedId;
    } catch (_) {
      return encodedId;
    }
  }

  /// Recursively translate base64 'id' fields
  static void _deepTranslate(dynamic obj) {
    if (obj is Map<String, dynamic>) {
      for (final key in obj.keys.toList()) {
        final value = obj[key];
        if (key == 'id' && value is String) {
          obj[key] = _translateId(value);
        } else if (value is Map || value is List) {
          _deepTranslate(value);
        }
      }
    } else if (obj is List) {
      for (var item in obj) {
        if (item is Map || item is List) {
          _deepTranslate(item);
        }
      }
    }
  }

  /// Fetch raw episodes data from Miruro
  static Future<Map<String, dynamic>?> fetchRawEpisodes(int anilistId) async {
    final payload = {
      "path": "episodes",
      "method": "GET",
      "query": {"anilistId": anilistId},
      "body": null,
      "version": "0.1.0",
    };
    
    final encodedReq = _encodePipeRequest(payload);
    final uri = Uri.parse("$_pipeUrl?e=$encodedReq");
    
    try {
      final responseBody = await _fetchViaWebView(uri);
      if (responseBody == null) {
        return null;
      }
      final data = _decodePipeResponse(responseBody.trim());
      _deepTranslate(data);
      return data;
    } catch (e) {
      print("MiruroScraperService: Error fetching episodes - $e");
      return null;
    }
  }

  /// Fetch stream sources for a specific episode ID
  static Future<Map<String, dynamic>?> fetchStreamSources(String episodeId, String provider, String category, int anilistId) async {
    final encId = base64Url.encode(utf8.encode(episodeId)).replaceAll('=', '');
    final payload = {
      "path": "sources",
      "method": "GET",
      "query": {
        "episodeId": encId,
        "provider": provider,
        "category": category,
        "anilistId": anilistId,
      },
      "body": null,
      "version": "0.1.0",
    };
    
    final encodedReq = _encodePipeRequest(payload);
    final uri = Uri.parse("$_pipeUrl?e=$encodedReq");
    
    try {
      final responseBody = await _fetchViaWebView(uri);
      if (responseBody == null) {
        return null;
      }
      return _decodePipeResponse(responseBody.trim());
    } catch (e) {
      print("MiruroScraperService: Error fetching sources - $e");
      return null;
    }
  }
}
