import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import 'player_screen.dart';
import '../widgets/watchlist_icon_button.dart';
import '../services/continue_watching_service.dart';
import 'search_screen.dart';
import 'watchlist_screen.dart';
import 'settings_screen.dart';
import '../services/supabase_sync_service.dart';
import '../services/supabase_auth_service.dart';
import '../monetization/services/ad_service.dart';


class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _trendingMovies = [];
  List<dynamic> _trendingTv = [];
  List<dynamic> _trendingAnime = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
    SupabaseSyncService.pullContinueWatching();
  }

  Future<void> _fetchData() async {
    try {
      final hasInternet = await TmdbService.hasInternetConnection();
      if (!hasInternet) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No internet connection. Please check your network.')),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      // 1. Fetch movies first
      final movies = await TmdbService.getTrendingMovies();
      setState(() {
        _trendingMovies = movies;
      });

      // 2. Tiny gap to avoid TMDB firewall triggers
      await Future.delayed(const Duration(milliseconds: 300));

      // 3. Fetch TV shows next
      final tvShows = await TmdbService.getTrendingTvShows();
      setState(() {
        _trendingTv = tvShows;
      });

      await Future.delayed(const Duration(milliseconds: 300));

      // 4. Fetch Anime
      final anime = await TmdbService.getTrendingAnime();
      setState(() {
        _trendingAnime = anime;
        _isLoading = false;
      });
    } catch (e) {
      print("UI Layer caught fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildMediaRow(String title, List<dynamic> items, bool isMovie) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            title,
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final posterPath = item['poster_path'];
              final titleText = item['title'] ?? item['name'];
              final tmdbId = item['id'].toString();

              return GestureDetector(
                onTap: () async {
                  if (!SupabaseAuthService.isPremium) {
                    await MockAdService().showInterstitialAd(context);
                  }
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayerScreen(
                        tmdbId: tmdbId,
                        isMovie: isMovie,
                        title: titleText,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 150,
                  margin: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: posterPath != null
                                ? Image.network(
                                    'https://image.tmdb.org/t/p/w500${posterPath}',
                                    height: 200,
                                    width: 150,
                                    fit: BoxFit.cover,
                                  )
                                : Container(height: 200, width: 150, color: Colors.grey),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: WatchlistIconButton(
                              tmdbId: tmdbId,
                              title: titleText,
                              posterPath: posterPath,
                              isMovie: isMovie,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        titleText,
                        style: TextStyle(color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContinueWatchingRow() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ContinueWatchingService.getAllItemsAsync(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return SizedBox.shrink();
        final items = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Continue Watching",
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final titleText = item['title'];
                  final tmdbId = item['tmdbId'].toString();
                  final isMovie = item['isMovie'];
                  final posterPath = item['posterPath'];
                  return GestureDetector(
                    onTap: () async {
                      if (!SupabaseAuthService.isPremium) {
                        await MockAdService().showInterstitialAd(context);
                      }
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlayerScreen(
                            tmdbId: tmdbId,
                            isMovie: isMovie,
                            title: titleText,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 150,
                      margin: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: posterPath != null
                                ? Image.network(
                                    'https://image.tmdb.org/t/p/w500$posterPath',
                                    height: 200,
                                    width: 150,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    height: 200,
                                    width: 150,
                                    color: Colors.grey[800],
                                    child: Center(
                                      child: Text(
                                        titleText,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                    ),
                                  ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            titleText,
                            style: TextStyle(color: Colors.white70),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF141414), // Netflix dark theme
      appBar: AppBar(
        title: Text('Fukat MSA', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.bookmark, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => WatchlistScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.search, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SearchScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildContinueWatchingRow(),
                  if (_trendingMovies.isNotEmpty) 
                    _buildMediaRow("Trending Movies", _trendingMovies, true),
                  _buildMediaRow("Trending TV Shows", _trendingTv, false),
                  _buildMediaRow("Trending Anime", _trendingAnime, true),
                ],
              ),
            ),
    );
  }
}
