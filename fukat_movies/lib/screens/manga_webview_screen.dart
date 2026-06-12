import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MangaWebviewScreen extends StatefulWidget {
  final String url;
  final String title;

  const MangaWebviewScreen({Key? key, required this.url, required this.title}) : super(key: key);

  @override
  _MangaWebviewScreenState createState() => _MangaWebviewScreenState();
}

class _MangaWebviewScreenState extends State<MangaWebviewScreen> {
  double _progress = 0;
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              webViewController?.reload();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_progress < 1.0)
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.transparent,
                color: Colors.redAccent,
              ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  transparentBackground: false,
                  mediaPlaybackRequiresUserGesture: false,
                  javaScriptEnabled: true,
                  userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                ),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    _progress = progress / 100;
                  });
                },
                onConsoleMessage: (controller, consoleMessage) {
                  print("WebView Console: \${consoleMessage.message}");
                },
                onLoadError: (controller, url, code, message) {
                  print("WebView Load Error: $message (code: $code)");
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
