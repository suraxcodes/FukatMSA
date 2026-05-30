import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/remote_config_service.dart';
import '../services/tmdb_service.dart';

class PlayerScreen extends StatefulWidget {
  final String tmdbId;
  final bool isMovie;
  final String title;

  PlayerScreen({required this.tmdbId, required this.isMovie, required this.title});

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  InAppWebViewController? webViewController;
  int currentProviderIndex = 0;
  String? currentImdbId;
  bool isInitializing = true;
  String currentUrl = "";

  @override
  void initState() {
    super.initState();
    _initializePlayback();
  }

  Future<void> _initializePlayback() async {
    // Fetch IMDB ID since some providers require it
    final imdbId = await TmdbService.getImdbId(int.parse(widget.tmdbId), widget.isMovie);
    setState(() {
      currentImdbId = imdbId ?? widget.tmdbId; // Fallback to TMDB if IMDB not found
      isInitializing = false;
      _startPlaybackChain();
    });
  }

  String _buildPlaybackUrl(Map<String, dynamic> provider, String tmdbId, String imdbId, String season, String episode, bool isMovie) {
    String activeId = (provider['id_type'] == "tmdb") ? tmdbId : imdbId;
    
    if (isMovie) {
      return "${provider['movie_url']}$activeId";
    }

    switch (provider['format_style']) {
      case "slash":
        return "${provider['tv_url']}$activeId/$season/$episode";
      case "query":
        return "${provider['tv_url']}$activeId&season=$season&episode=$episode";
      case "query_mix":
        return "${provider['tv_url']}$activeId&s=$season&e=$episode";
      default:
        return "${provider['tv_url']}$activeId";
    }
  }

  void _startPlaybackChain() {
    final providersList = RemoteConfigService.activeProviders;
    if (currentProviderIndex >= providersList.length) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("All fallback options exhausted. Stream unavailable.")),
        );
      }
      return;
    }

    var activeProvider = providersList[currentProviderIndex];
    // Default to Season 1 Episode 1 for TV Shows for now
    String requestUrl = _buildPlaybackUrl(activeProvider, widget.tmdbId, currentImdbId!, "1", "1", widget.isMovie);
    
    setState(() {
      currentUrl = requestUrl;
    });

    if (webViewController != null) {
      webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(requestUrl)));
    }
  }

  void _triggerFailover() {
    print("Provider failed, triggering failover to next provider...");
    setState(() {
      currentProviderIndex++;
    });
    _startPlaybackChain();
  }

  @override
  Widget build(BuildContext context) {
    if (isInitializing) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: currentProviderIndex >= RemoteConfigService.activeProviders.length
          ? Center(child: Text("No streams available.", style: TextStyle(color: Colors.white)))
          : InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(currentUrl)),
              initialSettings: InAppWebViewSettings(
                mediaPlaybackRequiresUserGesture: false,
                javaScriptEnabled: true,
                // Basic ad-blocking sandbox implementation
                supportZoom: false,
                disableContextMenu: true,
              ),
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame ?? false) {
                  _triggerFailover();
                }
              },
              onReceivedHttpError: (controller, request, errorResponse) {
                if ((request.isForMainFrame ?? false) && errorResponse.statusCode == 400) {
                  _triggerFailover();
                }
              },
            ),
    );
  }
}
