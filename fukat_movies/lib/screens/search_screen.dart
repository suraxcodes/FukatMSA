import 'dart:async';
import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import 'player_screen.dart';
import 'series_detail_screen.dart';
import '../widgets/watchlist_icon_button.dart';
import '../services/supabase_auth_service.dart';
import '../monetization/services/ad_service.dart';

class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _movieResults = [];
  List<dynamic> _seriesResults = [];
  List<dynamic> _animeResults = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) {
        _performSearch(query);
      } else {
        setState(() {
          _movieResults = [];
          _seriesResults = [];
          _animeResults = [];
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final results = await TmdbService.searchMedia(query);
      setState(() {
        _movieResults = results.where((item) => 
            item['media_type'] == 'movie' && 
            !(item['genre_ids']?.contains(16) ?? false)).toList();
        
        _seriesResults = results.where((item) => 
            item['media_type'] == 'tv' && 
            !(item['genre_ids']?.contains(16) ?? false)).toList();
            
        _animeResults = results.where((item) => 
            item['genre_ids']?.contains(16) ?? false).toList();
            
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildSection(String sectionTitle, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 4.0),
          child: Text(
            sectionTitle,
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 230,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final posterPath = item['poster_path'];
              final title = item['title'] ?? item['name'] ?? 'Unknown';
              final tmdbId = item['id'].toString();
              final mediaType = item['media_type'];
              final isMovie = mediaType == 'movie' || item['title'] != null;

              return Container(
                width: 120,
                margin: EdgeInsets.only(right: 12.0),
                child: GestureDetector(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                                    child: Icon(Icons.movie, color: Colors.white38, size: 40),
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
                  ),
                  SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
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
      backgroundColor: Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search movies, shows, anime...',
            hintStyle: TextStyle(color: Colors.white54),
            border: InputBorder.none,
          ),
          onChanged: _onSearchChanged,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _onSearchChanged('');
            },
          )
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : (_movieResults.isEmpty && _seriesResults.isEmpty && _animeResults.isEmpty)
              ? Center(
                  child: Text(
                    'No results',
                    style: TextStyle(color: Colors.white54, fontSize: 18),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.all(8),
                  children: [
                    if (_movieResults.isNotEmpty) _buildSection('Movies', _movieResults),
                    if (_seriesResults.isNotEmpty) _buildSection('TV Shows', _seriesResults),
                    if (_animeResults.isNotEmpty) _buildSection('Anime', _animeResults),
                    SizedBox(height: 20),
                  ],
                ),
    );
  }
}
