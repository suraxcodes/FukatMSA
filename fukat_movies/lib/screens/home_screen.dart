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
import '../widgets/auth_popup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/manga_service.dart';
import 'manga_details_screen.dart';
import '../widgets/manga_watchlist_icon_button.dart';
import 'dart:io' show Platform;
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _trendingMovies = [];
  List<dynamic> _trendingTv = [];
  List<dynamic> _trendingAnime = [];
  List<dynamic> _trendingManga = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
    SupabaseSyncService.pullContinueWatching();
    SupabaseSyncService.pullWatchlist();
    SupabaseSyncService.pullSearchHistory();
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
      });
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      // 5. Fetch Manga (from Anilist via MangaService)
      final manga = await MangaService.getTrendingManga();
      setState(() {
        _trendingManga = manga;
        _isLoading = false;
      });
    } catch (e) {
      print("UI Layer caught fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildMediaRow(String title, List<dynamic> items, bool isMovie, {bool isAnime = false}) {
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
                              isAnime: isAnime,
                            ),
                          ),
                          ValueListenableBuilder<Box>(
                            valueListenable: ContinueWatchingService.listenable,
                            builder: (context, box, child) {
                              if (ContinueWatchingService.isWatched(tmdbId)) {
                                return Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('WATCHED', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
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

  Widget _buildMangaRow(String title, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final coverImage = item['coverImage']?['large'];
              final titleText = item['title']?['english'] ?? item['title']?['romaji'] ?? 'Unknown Manga';

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MangaDetailsScreen(manga: item),
                    ),
                  );
                },
                child: Container(
                  width: 150,
                  margin: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: coverImage != null
                                ? Image.network(
                                    coverImage,
                                    headers: const {'User-Agent': 'Mozilla/5.0'},
                                    height: 200,
                                    width: 150,
                                    fit: BoxFit.cover,
                                  )
                                : Container(height: 200, width: 150, color: Colors.grey),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: MangaWatchlistIconButton(manga: item),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        titleText,
                        style: const TextStyle(color: Colors.white70),
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
                          Stack(
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
                              ValueListenableBuilder<Box>(
                                valueListenable: ContinueWatchingService.listenable,
                                builder: (context, box, child) {
                                  if (ContinueWatchingService.isWatched(tmdbId)) {
                                    return Positioned(
                                      top: 4,
                                      left: 4,
                                      child: Container(
                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent.withOpacity(0.9),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('WATCHED', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
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
          StreamBuilder<AuthState>(
            stream: SupabaseAuthService.authStateChanges,
            builder: (context, snapshot) {
              final session = snapshot.data?.session;
              if (session != null) {
                return IconButton(
                  icon: const Icon(Icons.person, color: Colors.greenAccent),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.grey[900],
                        title: const Text('Account', style: TextStyle(color: Colors.white)),
                        content: Text('Logged in as ${session.user.email}', style: const TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close', style: TextStyle(color: Colors.white70)),
                          ),
                          TextButton(
                            onPressed: () {
                              SupabaseAuthService.signOut();
                              Navigator.pop(context);
                            },
                            child: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }
              return IconButton(
                icon: const Icon(Icons.login, color: Colors.redAccent),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AuthPopup(),
                  );
                },
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
                  if (_trendingMovies.isNotEmpty) 
                    _buildMediaRow("Trending Movies", _trendingMovies, true),
                  if (_trendingTv.isNotEmpty)
                    _buildMediaRow("Trending TV Shows", _trendingTv, false),
                  if (_trendingAnime.isNotEmpty)
                    _buildMediaRow("Trending Anime", _trendingAnime, false, isAnime: true),
                  if (_trendingManga.isNotEmpty)
                    _buildMangaRow("Trending Manga", _trendingManga),
                  _buildContinueWatchingRow(),
                ],
              ),
            ),
    );
  }
}
