import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/watchlist_service.dart';
import 'player_screen.dart';
import '../widgets/watchlist_icon_button.dart';

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
      body: ValueListenableBuilder(
        valueListenable: WatchlistService.listenable,
        builder: (context, box, _) {
          final items = WatchlistService.getAllItems();

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
                onTap: () {
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
                              'https://image.tmdb.org/t/p/w500\$posterPath',
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
      ),
    );
  }
}
