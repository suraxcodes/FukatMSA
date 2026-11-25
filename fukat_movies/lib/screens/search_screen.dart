import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/log.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_sync_service.dart';
import 'player_screen.dart';
import '../widgets/watchlist_icon_button.dart';
import '../ads/ad_service.dart';
import '../services/manga_service.dart';
import 'manga_details_screen.dart';
import '../widgets/manga_watchlist_icon_button.dart';
import '../widgets/focusable_button.dart';

/// One cached search response, already split into its sections.
class _SearchBundle {
  final List<dynamic> movies;
  final List<dynamic> series;
  final List<dynamic> anime;
  final List<dynamic> manga;

  const _SearchBundle({
    required this.movies,
    required this.series,
    required this.anime,
    required this.manga,
  });
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  SearchScreenState createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<dynamic> _movieResults = [];
  List<dynamic> _seriesResults = [];
  List<dynamic> _animeResults = [];
  List<dynamic> _mangaResults = [];
  bool _isLoading = false;
  Timer? _debounce;
  List<dynamic> _recentOpenedItems = [];
  List<String> _recentSearches = [];

  /// Monotonic token: only the newest request may write to state. Without
  /// this, a slow request for "ava" could land *after* the fast one for
  /// "avatar" and replace good results with stale ones.
  int _requestToken = 0;

  /// Query → results. Typing one extra character and deleting it was firing
  /// two fresh TMDB + AniList round trips; now it is instant.
  final Map<String, _SearchBundle> _cache = {};
  String _activeQuery = '';

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
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) {
        _performSearch(query);
      } else {
        _requestToken++; // cancel any in-flight request
        _activeQuery = '';
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
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final token = ++_requestToken;
    _activeQuery = trimmed;

    // Cache hit: render immediately, no spinner flicker.
    final cached = _cache[trimmed];
    if (cached != null) {
      setState(() {
        _applyBundle(cached);
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    // TMDB and AniList in parallel — they used to be sequential.
    final results = await Future.wait<Object>([
      TmdbService.searchMedia(trimmed).catchError((Object e) {
        Log.w('Search', 'TMDB search failed for "$trimmed"', e);
        return <dynamic>[];
      }),
      MangaService.searchManga(trimmed).catchError((Object e) {
        Log.w('Search', 'AniList search failed for "$trimmed"', e);
        return <dynamic>[];
      }),
    ]);

    // A newer keystroke already superseded this request — discard it.
    if (token != _requestToken || !mounted) return;

    final tmdb = (results[0] as List<dynamic>);
    final manga = (results[1] as List<dynamic>);

    final bundle = _SearchBundle(
      movies: tmdb
          .where(
            (item) =>
                item['media_type'] == 'movie' &&
                !(item['genre_ids']?.contains(16) ?? false),
          )
          .toList(growable: false),
      series: tmdb
          .where(
            (item) =>
                item['media_type'] == 'tv' &&
                !(item['genre_ids']?.contains(16) ?? false),
          )
          .toList(growable: false),
      anime: tmdb
          .where((item) => item['genre_ids']?.contains(16) ?? false)
          .toList(growable: false),
      manga: manga,
    );

    // Bounded cache: keep the 12 most recent queries.
    if (_cache.length >= 12) _cache.remove(_cache.keys.first);
    _cache[trimmed] = bundle;

    setState(() {
      _applyBundle(bundle);
      _isLoading = false;
    });
  }

  void _applyBundle(_SearchBundle bundle) {
    _movieResults = bundle.movies;
    _seriesResults = bundle.series;
    _animeResults = bundle.anime;
    _mangaResults = bundle.manga;
  }

  Widget _buildSection(
    String sectionTitle,
    List<dynamic> items, {
    Widget? trailing,
    bool isAnime = false,
  }) {
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
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ?trailing,
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

              return FocusableButton(
                onTap: () async {
                  _saveOpenedItem(item as Map<String, dynamic>);
                  await Ads.showOnPlayerOpen(context);
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
                margin: const EdgeInsets.only(right: 12.0),
                child: SizedBox(
                  width: 120,
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
                                        child: Icon(
                                          Icons.movie,
                                          color: Colors.white38,
                                          size: 40,
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
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
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
              final titleText =
                  item['title']?['english'] ??
                  item['title']?['romaji'] ??
                  'Unknown Manga';

              return FocusableButton(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MangaDetailsScreen(manga: item),
                    ),
                  );
                },
                margin: const EdgeInsets.only(right: 12.0),
                child: SizedBox(
                  width: 120,
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
                                      headers: const {
                                        'User-Agent': 'Mozilla/5.0',
                                      },
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    )
                                  : Container(
                                      color: Colors.grey[800],
                                      child: const Center(
                                        child: Icon(
                                          Icons.book,
                                          color: Colors.white38,
                                          size: 40,
                                        ),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
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
        child: Text(
          'Search for movies, shows, or anime',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
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
                Text(
                  'Recent Searches',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('recent_searches');
                    setState(() {
                      _recentSearches.clear();
                    });
                  },
                  child: Text(
                    'Clear',
                    style: TextStyle(color: Colors.redAccent),
                  ),
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
                      await prefs.setStringList(
                        'recent_searches',
                        _recentSearches,
                      );
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
                setState(() {
                  _recentOpenedItems.clear();
                });
              },
              child: Text('Clear', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_searchFocusNode.hasFocus) {
          _searchFocusNode.requestFocus();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Color(0xFF141414),
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: IconThemeData(color: Colors.white),
          leading: FocusableButton(
            margin: const EdgeInsets.all(8.0),
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          title: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
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
            FocusableButton(
              margin: const EdgeInsets.all(8.0),
              padding: const EdgeInsets.all(8.0),
              onTap: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              child: const Icon(Icons.clear, color: Colors.white),
            ),
          ],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: Colors.redAccent))
            : _searchController.text.isEmpty
            ? _buildRecentSearches()
            : (_movieResults.isEmpty &&
                  _seriesResults.isEmpty &&
                  _animeResults.isEmpty &&
                  _mangaResults.isEmpty)
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.search_off,
                      color: Colors.white24,
                      size: 44,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No results for "$_activeQuery"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Check the spelling, or try the original title.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: EdgeInsets.all(8),
                children: [
                  if (_movieResults.isNotEmpty)
                    _buildSection('Movies', _movieResults),
                  if (_seriesResults.isNotEmpty)
                    _buildSection('TV Shows', _seriesResults),
                  if (_animeResults.isNotEmpty)
                    _buildSection('Anime', _animeResults, isAnime: true),
                  if (_mangaResults.isNotEmpty)
                    _buildMangaSection('Manga', _mangaResults),
                  SizedBox(height: 20),
                ],
              ),
      ),
    );
  }
}
