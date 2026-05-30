import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/remote_config_service.dart';
import '../services/tmdb_service.dart';
import '../services/ad_block_service.dart';
import '../widgets/episode_picker_sheet.dart';
import '../services/continue_watching_service.dart';

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
  String currentSeason = "1";
  String currentEpisode = "1";

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
    String requestUrl = _buildPlaybackUrl(activeProvider, widget.tmdbId, currentImdbId!, currentSeason, currentEpisode, widget.isMovie);
    
    setState(() {
      currentUrl = requestUrl;
    });

    if (webViewController != null) {
      webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(requestUrl)));
      ContinueWatchingService.saveItem(
        tmdbId: widget.tmdbId,
        title: widget.title,
        posterPath: null, // Poster path isn't strictly needed for resume play if we design it to work without it
        isMovie: widget.isMovie,
        lastSeason: widget.isMovie ? null : int.tryParse(currentSeason),
        lastEpisode: widget.isMovie ? null : int.tryParse(currentEpisode),
      );
    }
  }

  void _triggerFailover() {
    print("Provider failed, triggering failover to next provider...");
    setState(() {
      currentProviderIndex++;
    });
    _startPlaybackChain();
  }

  void _showEpisodePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => EpisodePickerSheet(
        currentSeason: currentSeason,
        currentEpisode: currentEpisode,
        onPlayPressed: (season, episode) {
          setState(() {
            currentSeason = season;
            currentEpisode = episode;
            currentProviderIndex = 0; // Reset failover loop
          });
          _startPlaybackChain();
        },
      ),
    );
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
        actions: [
          if (!widget.isMovie)
            IconButton(
              icon: Icon(Icons.list),
              tooltip: "Episodes",
              onPressed: _showEpisodePicker,
            )
        ],
      ),
      body: currentProviderIndex >= RemoteConfigService.activeProviders.length
          ? Center(child: Text("No streams available.", style: TextStyle(color: Colors.white)))
          : InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(currentUrl)),
              initialSettings: InAppWebViewSettings(
                mediaPlaybackRequiresUserGesture: false,
                javaScriptEnabled: true,
                supportZoom: false,
                disableContextMenu: true,
                useShouldOverrideUrlLoading: true, // Need this for URL intercept
              ),
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                var url = navigationAction.request.url?.toString() ?? '';
                var isForMainFrame = navigationAction.isForMainFrame ?? false;
                
                if (isForMainFrame) {
                  for (var domain in AdBlockService.adBlocklistDomains) {
                    if (url.contains(domain)) {
                      print('Blocked navigation to ad domain: \$domain');
                      return NavigationActionPolicy.CANCEL;
                    }
                  }
                }
                return NavigationActionPolicy.ALLOW;
              },
              onLoadStop: (controller, url) async {
                await controller.evaluateJavascript(source: AdBlockService.sandboxJsInjection);
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
