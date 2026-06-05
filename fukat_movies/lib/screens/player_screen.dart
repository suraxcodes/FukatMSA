import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/remote_config_service.dart';
import '../services/tmdb_service.dart';
import '../services/ad_block_service.dart';
import '../widgets/episode_side_panel.dart';
import '../services/continue_watching_service.dart';

class PlayerScreen extends StatefulWidget {
  final String tmdbId;
  final bool isMovie;
  final String title;

  PlayerScreen({
    required this.tmdbId,
    required this.isMovie,
    required this.title,
  });

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
  bool _isPlaying = false;
  String _bannerUrl =
      'https://via.placeholder.com/800x450'; // Placeholder, you can update with real TMDB backdrop
  // New state for dynamic season/episode lists
  List<String> _seasons = [];
  Map<String, List<String>> _episodesPerSeason = {};

  @override
  void initState() {
    super.initState();
    _initializePlaybackData();
  }

  Future<void> _initializePlaybackData() async {
    // Fetch IMDB ID since some providers require it
    final imdbId = await TmdbService.getImdbId(
      int.parse(widget.tmdbId),
      widget.isMovie,
    );

    // Attempt to get banner/backdrop and season data if series
    if (!widget.isMovie) {
      final seriesData = await TmdbService.getSeriesDetails(
        int.parse(widget.tmdbId),
      );
      if (seriesData != null && seriesData['backdrop_path'] != null) {
        _bannerUrl =
            'https://image.tmdb.org/t/p/w1280${seriesData['backdrop_path']}';
      }
      // Load seasons and episodes
      if (seriesData != null && seriesData['seasons'] != null) {
        final seasonList = seriesData['seasons'] as List<dynamic>;
        List<String> seasons = [];
        Map<String, List<String>> episodesMap = {};
        for (var season in seasonList) {
          final seasonNumber = season['season_number'].toString();
          seasons.add(seasonNumber);
          final episodes = await TmdbService.getSeasonEpisodes(
            int.parse(widget.tmdbId),
            int.parse(seasonNumber),
          );
          final epNumbers = episodes
              .map((e) => e['episode_number'].toString())
              .toList();
          episodesMap[seasonNumber] = epNumbers;
        }
        setState(() {
          _seasons = seasons;
          _episodesPerSeason = episodesMap;
          if (_seasons.isNotEmpty) {
            currentSeason = _seasons.first;
          }
        });
      }
    } else {
      // Movie banner logic could be added here
    }

    setState(() {
      currentImdbId =
          imdbId ?? widget.tmdbId; // Fallback to TMDB if IMDB not found
      isInitializing = false;
      _preparePlaybackUrl();
    });
  }

  void _preparePlaybackUrl() {
    final providersList = RemoteConfigService.activeProviders;
    if (currentProviderIndex >= providersList.length) {
      return;
    }
    var activeProvider = providersList[currentProviderIndex];
    String activeId = (activeProvider['id_type'] == "tmdb")
        ? widget.tmdbId
        : currentImdbId!;

    String requestUrl = "";
    if (widget.isMovie) {
      requestUrl = "${activeProvider['movie_url']}$activeId";
    } else {
      switch (activeProvider['format_style']) {
        case "slash":
          requestUrl =
              "${activeProvider['tv_url']}$activeId/$currentSeason/$currentEpisode";
          break;
        case "query":
          requestUrl =
              "${activeProvider['tv_url']}$activeId&season=$currentSeason&episode=$currentEpisode";
          break;
        case "query_mix":
          requestUrl =
              "${activeProvider['tv_url']}$activeId&s=$currentSeason&e=$currentEpisode";
          break;
        default:
          requestUrl = "${activeProvider['tv_url']}$activeId";
      }
    }

    setState(() {
      currentUrl = requestUrl;
    });
  }

  void _startPlayback() {
    setState(() {
      _isPlaying = true;
    });

    if (webViewController != null) {
      webViewController!.loadUrl(
        urlRequest: URLRequest(url: WebUri(currentUrl)),
      );
    }

    ContinueWatchingService.saveItem(
      tmdbId: widget.tmdbId,
      title: widget.title,
      posterPath: null,
      isMovie: widget.isMovie,
      lastSeason: widget.isMovie ? null : int.tryParse(currentSeason),
      lastEpisode: widget.isMovie ? null : int.tryParse(currentEpisode),
    );
  }

  void _triggerFailover() {
    print("Provider failed, triggering failover to next provider...");
    setState(() {
      currentProviderIndex++;
      _preparePlaybackUrl();
    });
    if (_isPlaying && webViewController != null) {
      webViewController!.loadUrl(
        urlRequest: URLRequest(url: WebUri(currentUrl)),
      );
    }
  }

  Widget _buildVideoPlayerArea() {
    if (currentProviderIndex >= RemoteConfigService.activeProviders.length) {
      return Center(
        child: Text(
          "No streams available.",
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    if (!_isPlaying) {
      return Stack(
        alignment: Alignment.center,
        children: [
          CachedNetworkImage(
            imageUrl: _bannerUrl,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            placeholder: (context, url) => Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
            ),
            errorWidget: (context, url, error) =>
                Icon(Icons.broken_image, size: 64, color: Colors.grey),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: _startPlayback,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(
                    0xFF8A2BE2,
                  ).withOpacity(0.8), // Purple play button from reference
                ),
                child: const Icon(
                  Icons.play_arrow,
                  size: 64,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(currentUrl)),
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        javaScriptEnabled: true,
        supportZoom: false,
        disableContextMenu: true,
        useShouldOverrideUrlLoading: true,
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
        await controller.evaluateJavascript(
          source: AdBlockService.sandboxJsInjection,
        );
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          _triggerFailover();
        }
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        if ((request.isForMainFrame ?? false) &&
            errorResponse.statusCode == 400) {
          _triggerFailover();
        }
      },
    );
  }

  Widget _buildControlBar() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlButton(Icons.fullscreen, 'Expand'),
            _buildControlButton(Icons.play_circle_outline, 'Auto Play'),
            _buildControlButton(Icons.check, 'Auto Next'),
            _buildControlButton(Icons.skip_next, 'Auto Skip', isActive: true),
            _buildControlButton(Icons.lightbulb_outline, 'Light'),
            _buildControlButton(Icons.skip_previous, 'Prev'),
            _buildControlButton(Icons.skip_next, 'Next'),
            const SizedBox(width: 32),
            _buildControlButton(Icons.report_problem, 'Report'),
            _buildControlButton(Icons.bookmark_add, 'Add to list'),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(
    IconData icon,
    String label, {
    bool isActive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isActive ? const Color(0xFF8A2BE2) : Colors.white70,
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFF8A2BE2) : Colors.white70,
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSection() {
    return Column(
      children: [
        // Top info bar matching reference
        Container(
          color: const Color(0xFF222222),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Data transfer is finished! Secondary servers might say 404 because of ongoing encoding...',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Main video player area (takes remaining vertical space)
        Flexible(child: _buildVideoPlayerArea()),
      ],
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

    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth > 700;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: isWide
          ? null
          : AppBar(
              title: Text(
                widget.title,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              backgroundColor: Colors.black,
              iconTheme: IconThemeData(color: Colors.white),
            ),
      body: SafeArea(
        child: isWide
            ? Row(
                children: [
                  // Left Side: Episode Picker (if not a movie)
                  if (!widget.isMovie)
                    SizedBox(
                      width: 280,
                      child: EpisodeSidePanel(
                        currentSeason: currentSeason,
                        currentEpisode: currentEpisode,
                        seasons: _seasons,
                        episodesPerSeason: _episodesPerSeason,
                        onEpisodeSelected: (season, episode) {
                          setState(() {
                            currentSeason = season;
                            currentEpisode = episode;
                            currentProviderIndex = 0;
                            _preparePlaybackUrl();
                          });
                          _startPlayback();
                        },
                      ),
                    ),
                  // Right Side: Player Section
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: _buildPlayerSection(),
                  ),
                ],
              )
            : Column(
                children: [
                  // Top Side: Player Section
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    width: double.infinity,
                    child: _buildPlayerSection(),
                  ),
                  // Bottom Side: Episode Picker (if not a movie)
                  if (!widget.isMovie)
                    Expanded(
                      child: EpisodeSidePanel(
                        currentSeason: currentSeason,
                        currentEpisode: currentEpisode,
                        seasons: _seasons,
                        episodesPerSeason: _episodesPerSeason,
                        onEpisodeSelected: (season, episode) {
                          setState(() {
                            currentSeason = season;
                            currentEpisode = episode;
                            currentProviderIndex = 0;
                            _preparePlaybackUrl();
                          });
                          _startPlayback();
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
