import 'package:flutter/material.dart';
import '../screens/player_screen.dart';

class HeroBanner extends StatelessWidget {
  final Map<String, dynamic> item;

  HeroBanner({required this.item});

  @override
  Widget build(BuildContext context) {
    final title = item['title'] ?? item['name'] ?? 'Unknown';
    final backdropPath = item['backdrop_path'];
    final id = item['id'].toString();
    // In TMDB, if 'title' exists it's usually a movie, if 'name' exists it's usually a tv show.
    // TMDB trending endpoint also explicitly provides 'media_type'.
    final isMovie = item['media_type'] == 'movie' || item['title'] != null;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        if (backdropPath != null)
          Image.network(
            'https://image.tmdb.org/t/p/w1280\$backdropPath',
            height: 400,
            width: double.infinity,
            fit: BoxFit.cover,
          )
        else
          Container(
            height: 400,
            width: double.infinity,
            color: Colors.grey[900],
          ),
        Container(
          height: 400,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black,
                Colors.black.withOpacity(0.0),
              ],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 40.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                icon: Icon(Icons.play_arrow),
                label: Text(
                  'Play',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayerScreen(
                        tmdbId: id,
                        isMovie: isMovie,
                        title: title,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
