import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_sync_service.dart';
import 'player_screen.dart';
import 'series_detail_screen.dart';
import '../widgets/watchlist_icon_button.dart';
import '../services/supabase_auth_service.dart';
import '../monetization/services/ad_service.dart';
import '../services/manga_service.dart';
import 'manga_details_screen.dart';
import '../widgets/manga_watchlist_icon_button.dart';

class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _movieResults = [];
  List<dynamic> _seriesResults = [];
  List<dynamic> _animeResults = [];
  List<dynamic> _mangaResults = [];
  bool _isLoading = false;
  Timer? _debounce;
  List<dynamic> _recentOpenedItems = [];
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _loadSearches();
  }

  Future<void> _loadSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final itemsStr = prefs.getStringList('recent_opened_items') ?? [];
    setState(() {
      _recentOpenedItems = itemsStr.map((e) => jsonDecode(e)).toList();
      _recentSearches = prefs.getStringList('recent_searches') ?? [];
    });
  }

  Future<void> _saveSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _recentSearches.remove(q);
    _recentSearches.insert(0, q);
    if (_recentSearches.length > 20) _recentSearches.removeLast();
    await prefs.setStringList('recent_searches', _recentSearches);
    if (mounted) setState(() {});
    
    // Trigger background sync
    SupabaseSyncService.syncSearchHistory();
  }

  Future<void> _saveOpenedItem(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    
    // We only need specific fields to render the banner
    final minimalItem = {
      'id': item['id'],
      'title': item['title'],
      'name': item['name'],
      'poster_path': item['poster_path'],
      'media_type': item['media_type'],
      'genre_ids': item['genre_ids'],
    };

    _recentOpenedItems.removeWhere((element) => element['id'] == item['id']);
    _recentOpenedItems.insert(0, minimalItem);
    if (_recentOpenedItems.length > 20) _recentOpenedItems.removeLast();
    
    final itemsStr = _recentOpenedItems.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList('recent_opened_items', itemsStr);
    if (mounted) setState(() {});

    // Trigger background sync
    SupabaseSyncService.syncSearchHistory();
  }

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
          _mangaResults = [];
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
      final mangaRes = await MangaService.searchManga(query);
      
      setState(() {
        _movieResults = results.where((item) => 
            item['media_type'] == 'movie' && 
            !(item['genre_ids']?.contains(16) ?? false)).toList();
        
        _seriesResults = results.where((item) => 
            item['media_type'] == 'tv' && 
            !(item['genre_ids']?.contains(16) ?? false)).toList();
            
        _animeResults = results.where((item) => 
            item['genre_ids']?.contains(16) ?? false).toList();
            
        _mangaResults = mangaRes;
            
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildSection(String sectionTitle, List<dynamic> items, {Widget? trailing, bool isAnime = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                sectionTitle,
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (trailing != null) trailing,
            ],
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
                  _saveOpenedItem(item as Map<String, dynamic>);
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
                            isAnime: isAnime,
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

  Widget _buildMangaSection(String sectionTitle, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 4.0),
          child: Text(
            sectionTitle,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 230,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final coverImage = item['coverImage']?['large'];
              final titleText = item['title']?['english'] ?? item['title']?['romaji'] ?? 'Unknown Manga';

              return Container(
                width: 120,
                margin: const EdgeInsets.only(right: 12.0),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MangaDetailsScreen(manga: item),
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
                              child: coverImage != null
                                  ? Image.network(
                                      coverImage,
                                      headers: const {'User-Agent': 'Mozilla/5.0'},
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    )
                                  : Container(
                                      color: Colors.grey[800],
                                      child: const Center(
                                        child: Icon(Icons.book, color: Colors.white38, size: 40),
                                      ),
                                    ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: MangaWatchlistIconButton(manga: item),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        titleText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
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

  Widget _buildRecentSearches() {
    if (_recentOpenedItems.isEmpty && _recentSearches.isEmpty) {
      return Center(
        child: Text('Search for movies, shows, or anime', style: TextStyle(color: Colors.white54, fontSize: 16)),
      );
    }
    return ListView(
      padding: EdgeInsets.all(8),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent Searches', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('recent_searches');
                    setState(() { _recentSearches.clear(); });
                  },
                  child: Text('Clear', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _recentSearches.map((query) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InputChip(
                    label: Text(query, style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.grey[850],
                    deleteIconColor: Colors.white54,
                    onDeleted: () async {
                      _recentSearches.remove(query);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setStringList('recent_searches', _recentSearches);
                      setState(() {});
                    },
                    onPressed: () {
                      _searchController.text = query;
                      _onSearchChanged(query);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          SizedBox(height: 16),
        ],
        if (_recentOpenedItems.isNotEmpty)
          _buildSection(
            'Recently Viewed', 
            _recentOpenedItems,
            trailing: TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('recent_opened_items');
                setState(() { _recentOpenedItems.clear(); });
              },
              child: Text('Clear', style: TextStyle(color: Colors.redAccent)),
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
          onSubmitted: _saveSearch,
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
          : _searchController.text.isEmpty
              ? _buildRecentSearches()
              : (_movieResults.isEmpty && _seriesResults.isEmpty && _animeResults.isEmpty && _mangaResults.isEmpty)
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
                    if (_animeResults.isNotEmpty) _buildSection('Anime', _animeResults, isAnime: true),
                    if (_mangaResults.isNotEmpty) _buildMangaSection('Manga', _mangaResults),
                    SizedBox(height: 20),
                  ],
                ),
    );
  }
}
