import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../ads/ad_service.dart';
import '../core/errors.dart';
import '../services/continue_watching_service.dart';
import '../services/manga_service.dart';
import '../services/provider_health_service.dart';
import '../services/supabase_auth_service.dart';
import '../services/supabase_sync_service.dart';
import '../services/tmdb_client.dart';
import '../widgets/auth_popup.dart';
import '../widgets/focusable_button.dart';
import '../widgets/manga_watchlist_icon_button.dart';
import '../widgets/watchlist_icon_button.dart';
import 'diagnostics_screen.dart';
import 'manga_details_screen.dart';
import 'player_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'watchlist_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  HomeFeed? _feed;
  List<dynamic> _trendingManga = const [];
  AppError? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _syncFromCloud();
  }

  /// Fire-and-forget: cloud pulls must never block the first frame.
  void _syncFromCloud() {
    if (!SupabaseAuthService.isAvailable || !SupabaseAuthService.isSignedIn) {
      return;
    }
    SupabaseSyncService.pullContinueWatching();
    SupabaseSyncService.pullWatchlist();
    SupabaseSyncService.pullSearchHistory();
  }

  /// All four feeds load concurrently. Previously each row waited on the
  /// previous one plus a 300ms artificial delay, so the home screen took
  /// ~4× longer than it needed to.
  Future<void> _fetchData({bool refresh = false}) async {
    if (refresh) TmdbClient.clearCache();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<Object>([
        TmdbClient.fetchHomeFeed(),
        // Manga is a separate provider entirely; a failure there must not
        // take down the movie rows.
        MangaService.getTrendingManga().catchError((Object _) => <dynamic>[]),
      ]);

      if (!mounted) return;
      setState(() {
        _feed = results[0] as HomeFeed;
        _trendingManga = results[1] as List<dynamic>;
        _isLoading = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.from(e, context: 'home');
        _isLoading = false;
      });
    }
  }

  void _openPlayer({
    required String tmdbId,
    required bool isMovie,
    required String title,
    bool isAnime = false,
  }) async {
    await Ads.showOnPlayerOpen(context);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PlayerScreen(tmdbId: tmdbId, isMovie: isMovie, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        title: const Text(
          'Fukat MSA',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          FocusableButton(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.bookmark, color: Colors.white),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => WatchlistScreen()),
            ),
          ),
          FocusableButton(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.search, color: Colors.white),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SearchScreen()),
            ),
          ),
          FocusableButton(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.settings, color: Colors.white),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          _accountButton(),
        ],
      ),
      body: RefreshIndicator(
        color: Colors.redAccent,
        onRefresh: () => _fetchData(refresh: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.redAccent),
      );
    }

    if (_error != null) {
      return _ErrorState(
        error: _error!,
        onRetry: () => _fetchData(refresh: true),
      );
    }

    final feed = _feed;
    final hasAnything =
        feed != null && !feed.isEmpty || _trendingManga.isNotEmpty;
    if (!hasAnything) {
      return _ErrorState(
        error: const AppError(
          AppErrorKind.notFound,
          'No trending titles came back. This usually means TMDB rejected the request.',
        ),
        onRetry: () => _fetchData(refresh: true),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ProviderStatusBanner(),
          if (feed != null && feed.movies.isNotEmpty)
            _buildMediaRow('Trending Movies', feed.movies, true),
          if (feed != null && feed.tvShows.isNotEmpty)
            _buildMediaRow('Trending TV Shows', feed.tvShows, false),
          if (feed != null && feed.anime.isNotEmpty)
            _buildMediaRow('Trending Anime', feed.anime, false, isAnime: true),
          if (_trendingManga.isNotEmpty)
            _buildMangaRow('Trending Manga', _trendingManga),
          _buildContinueWatchingRow(),
          const Attribution(),
        ],
      ),
    );
  }

  Widget _accountButton() {
    final stream = SupabaseAuthService.authStateChanges;
    if (stream == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.cloud_off, color: Colors.white38),
      );
    }

    return StreamBuilder<AuthState?>(
      stream: stream,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        if (session != null) {
          return FocusableButton(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.person, color: Colors.greenAccent),
            onTap: () => _showAccountDialog(session.user.email ?? ''),
          );
        }
        return FocusableButton(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(8),
          child: const Icon(Icons.login, color: Colors.white),
          onTap: () =>
              showDialog<void>(context: context, builder: (_) => AuthPopup()),
        );
      },
    );
  }

  void _showAccountDialog(String email) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Account', style: TextStyle(color: Colors.white)),
        content: Text(
          'Signed in as $email',
          style: const TextStyle(color: Colors.white70),
        ),
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
            child: const Text(
              'Sign out',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ rows

  Widget _buildMediaRow(
    String title,
    List<dynamic> items,
    bool isMovie, {
    bool isAnime = false,
  }) {
    return _Row(
      title: title,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = Map<String, dynamic>.from(items[index] as Map);
        final posterPath = item['poster_path'] as String?;
        final titleText = (item['title'] ?? item['name'] ?? 'Untitled')
            .toString();
        final tmdbId = item['id']?.toString();
        if (tmdbId == null) return const SizedBox.shrink();

        return _PosterCard(
          title: titleText,
          imageUrl: posterPath == null
              ? null
              : 'https://image.tmdb.org/t/p/w342$posterPath',
          overlayTopRight: WatchlistIconButton(
            tmdbId: tmdbId,
            title: titleText,
            posterPath: posterPath,
            isMovie: isMovie,
            isAnime: isAnime,
          ),
          watchedBadgeId: tmdbId,
          onTap: () => _openPlayer(
            tmdbId: tmdbId,
            isMovie: isMovie,
            title: titleText,
            isAnime: isAnime,
          ),
        );
      },
    );
  }

  Widget _buildMangaRow(String title, List<dynamic> items) {
    return _Row(
      title: title,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = Map<String, dynamic>.from(items[index] as Map);
        final cover = (item['coverImage'] as Map?)?['large'] as String?;
        final titles = item['title'] as Map?;
        final titleText =
            (titles?['english'] ?? titles?['romaji'] ?? 'Unknown Manga')
                .toString();

        return _PosterCard(
          title: titleText,
          imageUrl: cover,
          overlayTopRight: MangaWatchlistIconButton(manga: item),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MangaDetailsScreen(manga: item)),
          ),
        );
      },
    );
  }

  Widget _buildContinueWatchingRow() {
    // Null-safe: the box may not be open yet on a cold start.
    final listenable = ContinueWatchingService.listenableOrNull;
    if (listenable == null) return const SizedBox.shrink();

    return ValueListenableBuilder<Box>(
      valueListenable: listenable,
      builder: (context, box, _) {
        final items = ContinueWatchingService.getItemSnapshot();
        if (items.isEmpty) return const SizedBox.shrink();

        return _Row(
          title: 'Continue Watching',
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final tmdbId = item['tmdbId']?.toString() ?? '';
            final titleText = (item['title'] ?? 'Untitled').toString();
            final posterPath = item['posterPath'] as String?;
            final isMovie = item['isMovie'] != false;
            final progress = _progress(item);

            return _PosterCard(
              title: titleText,
              imageUrl: posterPath == null
                  ? null
                  : 'https://image.tmdb.org/t/p/w342$posterPath',
              progress: progress,
              watchedBadgeId: tmdbId,
              onTap: () => _openPlayer(
                tmdbId: tmdbId,
                isMovie: isMovie,
                title: titleText,
              ),
            );
          },
        );
      },
    );
  }

  double? _progress(Map<String, dynamic> item) {
    final position = (item['position'] as num?)?.toDouble();
    final duration = (item['duration'] as num?)?.toDouble();
    if (position == null || duration == null || duration <= 0) return null;
    return (position / duration).clamp(0.0, 1.0);
  }
}

// ---------------------------------------------------------------- widgets

class _Row extends StatelessWidget {
  final String title;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const _Row({
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 248,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final Widget? overlayTopRight;
  final String? watchedBadgeId;
  final double? progress;
  final VoidCallback onTap;

  const _PosterCard({
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.overlayTopRight,
    this.watchedBadgeId,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableButton(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        width: 145,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: imageUrl == null
                        ? Container(
                            color: Colors.grey[850],
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            // Skeleton instead of a grey box jump.
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                ? child
                                : Container(color: Colors.grey[900]),
                            errorBuilder: (context, error, stack) => Container(
                              color: Colors.grey[900],
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.white24,
                                size: 28,
                              ),
                            ),
                          ),
                  ),
                  if (overlayTopRight != null)
                    Positioned(top: 4, right: 4, child: overlayTopRight!),
                  if (watchedBadgeId != null)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: ValueListenableBuilder<Box>(
                        valueListenable:
                            ContinueWatchingService.listenableOrNull!,
                        builder: (context, box, _) {
                          if (!ContinueWatchingService.isWatched(
                            watchedBadgeId!,
                          )) {
                            return const SizedBox.shrink();
                          }
                          return const _Badge(
                            text: 'WATCHED',
                            color: Colors.greenAccent,
                          );
                        },
                      ),
                    ),
                  if (progress != null && progress! > 0.01)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.redAccent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

/// Non-blocking strip that only appears when something is actually wrong with
/// the provider stack — instead of the old behaviour of finding out at play time.
class _ProviderStatusBanner extends StatelessWidget {
  const _ProviderStatusBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EndpointStatus>>(
      stream: ProviderHealthService.onStatusChange,
      builder: (context, snapshot) {
        final statuses = snapshot.data ?? ProviderHealthService.statuses;
        if (statuses.isEmpty) return const SizedBox.shrink();

        final down = statuses
            .where((s) => s.health == ProviderHealth.down)
            .toList();
        final warming = statuses
            .where((s) => s.health == ProviderHealth.warming)
            .length;
        if (down.isEmpty && warming == 0) return const SizedBox.shrink();

        final allDown = down.length == statuses.length;
        final color = allDown ? Colors.redAccent : Colors.amber;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(
                allDown ? Icons.cloud_off : Icons.hourglass_bottom,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  allDown
                      ? 'All streaming services are unreachable right now. Playback will fail.'
                      : (warming > 0 && down.isEmpty
                            ? 'Waking up streaming services…'
                            : '${down.length} of ${statuses.length} services are unreachable.'),
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
                ),
                child: Text(
                  'Details',
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// TMDB's API terms require this notice. It was missing entirely.
class Attribution extends StatelessWidget {
  const Attribution({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(16, 28, 16, 32),
    child: Text(
      'Metadata by TMDB. This product uses the TMDB API but is not endorsed '
      'or certified by TMDB. Manga data by AniList · MangaDex. '
      'Fukat MSA hosts no media and links to third-party sources.',
      style: TextStyle(color: Colors.white24, fontSize: 10, height: 1.5),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final AppError error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final (icon, hint) = switch (error.kind) {
      AppErrorKind.offline => (
        Icons.wifi_off,
        'Connect to the internet and retry.',
      ),
      AppErrorKind.badRequest || AppErrorKind.unauthorized => (
        Icons.key_off,
        'TMDB credentials are missing from this build. Add TMDB_API_TOKEN '
            'via --dart-define or assets/.env.',
      ),
      AppErrorKind.rateLimited => (
        Icons.hourglass_empty,
        'Too many requests — wait a minute.',
      ),
      AppErrorKind.notFound => (
        Icons.search_off,
        'Nothing came back for this query.',
      ),
      _ => (Icons.cloud_off, 'The service is having trouble.'),
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(icon, color: Colors.white24, size: 56),
        const SizedBox(height: 16),
        Center(
          child: Text(
            error.userMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}
