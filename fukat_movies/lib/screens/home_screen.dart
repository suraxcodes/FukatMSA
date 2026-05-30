import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _trendingMovies = [];
  List<dynamic> _trendingTv = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final movies = await TmdbService.getTrendingMovies();
    final tvShows = await TmdbService.getTrendingTvShows();
    setState(() {
      _trendingMovies = movies;
      _trendingTv = tvShows;
      _isLoading = false;
    });
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
                onTap: () {
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
                            : Container(height: 200, width: 150, color: Colors.grey),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF141414), // Netflix dark theme
      appBar: AppBar(
        title: Text('Fukat Movies', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildMediaRow("Trending Movies", _trendingMovies, true),
                  _buildMediaRow("Trending TV Shows", _trendingTv, false),
                ],
              ),
            ),
    );
  }
}
