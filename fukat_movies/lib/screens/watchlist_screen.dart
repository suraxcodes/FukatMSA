import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/watchlist_service.dart';
import 'player_screen.dart';
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
        future: WatchlistService.ensureInitialized(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: Colors.red));
          }
          return ValueListenableBuilder(
            valueListenable: WatchlistService.listenable,
            builder: (context, box, _) {
              final items = (box.values
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
          ..sort((a, b) => DateTime.parse(b['savedAt']).compareTo(DateTime.parse(a['savedAt']))));

              if (items.isEmpty) {
                return Center(
                  child: Text(
                    'Your watchlist is empty.',
                    style: TextStyle(color: Colors.white54, fontSize: 18),
                  ),
                );
              }

              return GridView.builder(
                padding: EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
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
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: posterPath != null
                              ? Image.network(
                                  'https://image.tmdb.org/t/p/w500$posterPath',
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                )
                              : Container(
                                  color: Colors.grey[800],
                                  child: Center(
                                    child: Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white70),
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
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
