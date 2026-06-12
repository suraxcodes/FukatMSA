import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/watchlist_service.dart';
import '../services/manga_watchlist_service.dart';
import 'player_screen.dart';
import 'manga_details_screen.dart';
import '../widgets/watchlist_icon_button.dart';
import '../services/supabase_auth_service.dart';
import '../monetization/services/ad_service.dart';

class WatchlistScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF141414),
      appBar: AppBar(
        title: Text('My Watchlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
        body: FutureBuilder(
          future: Future.wait([
            WatchlistService.ensureInitialized(),
            MangaWatchlistService.ensureInitialized()
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: Colors.red));
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section 1: Movies
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "Movies",
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: WatchlistService.listenable,
                    builder: (context, box, _) {
                      final items = box.values
                          .map((item) => Map<String, dynamic>.from(item))
                          .where((item) => item['isMovie'] == true)
                          .toList()
                        ..sort((a, b) => DateTime.parse(b['savedAt']).compareTo(DateTime.parse(a['savedAt'])));

                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            'Your movies watchlist is empty.',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        );
                      }

                      return _buildWatchlistRow(items);
                    },
                  ),
                  
                  const SizedBox(height: 20),

                  // Section 2: TV Shows
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "TV Shows",
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: WatchlistService.listenable,
                    builder: (context, box, _) {
                      final items = box.values
                          .map((item) => Map<String, dynamic>.from(item))
                          .where((item) => item['isMovie'] == false && item['isAnime'] != true)
                          .toList()
                        ..sort((a, b) => DateTime.parse(b['savedAt']).compareTo(DateTime.parse(a['savedAt'])));

                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            'Your TV shows watchlist is empty.',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        );
                      }

                      return _buildWatchlistRow(items);
                    },
                  ),

                  const SizedBox(height: 20),

                  // Section 3: Anime
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "Anime",
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: WatchlistService.listenable,
                    builder: (context, box, _) {
                      final items = box.values
                          .map((item) => Map<String, dynamic>.from(item))
                          .where((item) => item['isAnime'] == true)
                          .toList()
                        ..sort((a, b) => DateTime.parse(b['savedAt']).compareTo(DateTime.parse(a['savedAt'])));

                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            'Your anime watchlist is empty.',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        );
                      }

                      return _buildWatchlistRow(items);
                    },
                  ),
                  
                  const SizedBox(height: 20),

                  // Section 2: Manga
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "Manga",
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: MangaWatchlistService.listenable,
                    builder: (context, box, _) {
                      final items = (box.values
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList()
                        ..sort((a, b) => DateTime.parse(b['savedAt']).compareTo(DateTime.parse(a['savedAt']))));

                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            'Your manga watchlist is empty.',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        );
                      }

                      return SizedBox(
                        height: 250,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final manga = items[index];
                            final title = manga['title']?['romaji'] ?? manga['title']?['english'] ?? 'Unknown';
                            final coverUrl = manga['coverImage']?['extraLarge'] ?? manga['coverImage']?['large'] ?? manga['coverImage']?['medium'];

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MangaDetailsScreen(manga: manga),
                                  ),
                                );
                              },
                              child: Container(
                                width: 150,
                                margin: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (coverUrl != null)
                                        Image.network(
                                          coverUrl,
                                          fit: BoxFit.cover,
                                          headers: const {'User-Agent': 'Mozilla/5.0'},
                                        )
                                      else
                                        Container(
                                          color: Colors.grey[800],
                                          child: Center(
                                            child: Text(
                                              title,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(color: Colors.white70),
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          color: Colors.black54,
                                          child: Text(
                                            title,
                                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        ),
    );
  }

  Widget _buildWatchlistRow(List<Map<String, dynamic>> items) {
    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final posterPath = item['posterPath'];
          final title = item['title'];
          final tmdbId = item['tmdbId'].toString();
          final isMovie = item['isMovie'];

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
                    title: title,
                  ),
                ),
              );
            },
            child: Container(
              width: 150,
              margin: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: posterPath != null
                        ? Image.network(
                            'https://image.tmdb.org/t/p/w500$posterPath',
                            fit: BoxFit.cover,
                            width: 150,
                            height: 250,
                          )
                        : Container(
                            color: Colors.grey[800],
                            width: 150,
                            height: 250,
                            child: Center(
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: WatchlistIconButton(
                      tmdbId: tmdbId,
                      title: title,
                      posterPath: posterPath,
                      isMovie: isMovie,
                      isAnime: item['isAnime'] == true,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
