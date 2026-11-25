import 'package:flutter/material.dart';

import '../core/log.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../widgets/focusable_button.dart';

class MangaWebviewScreen extends StatefulWidget {
  final String url;
  final String title;

  const MangaWebviewScreen({super.key, required this.url, required this.title});

  @override
  MangaWebviewScreenState createState() => MangaWebviewScreenState();
}

class MangaWebviewScreenState extends State<MangaWebviewScreen> {
  double _progress = 0;
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          FocusableButton(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            child: const Icon(Icons.refresh, color: Colors.white),
            onTap: () {
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
                  userAgent:
                      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
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
                  Log.d('MangaWebView', consoleMessage.message);
                },
                onReceivedError: (controller, request, error) {
                  Log.w(
                    'MangaWebView',
                    'load error ${error.description} (code ${error.type})',
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
