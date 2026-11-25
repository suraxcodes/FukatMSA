/// Resolves a playable stream for a movie/episode.
///
/// Replaces `PlaybackManager`, whose `initAndSearch` awaited **every** provider
/// batch sequentially — with 12 providers that is the sum of the slowest of
/// each triple before the user could watch anything. It also fired
/// `setState` callbacks from inside those futures (after dispose), and its
/// copy of `_buildPlaybackUrl` forgot to pass `tmdbId`, so Stremio silently
/// failed when resolution went through it.
///
/// This version *races* providers and emits results as they arrive:
///   browse the first success immediately, keep filling the list in the
///   background so the server/quality picker stays populated.
library;

import 'dart:async';

import '../core/app_config.dart';
import '../core/errors.dart';
import '../core/log.dart';
import 'remote_config_service.dart';
import 'streaming_aggregator_service.dart';
import 'tmdb_client.dart';

/// A single successfully resolved provider.
class StreamInfo {
  final String providerName;
  final String engine;
  final String url;
  final Map<String, String>? headers;
  final List<Map<String, dynamic>> qualities; // {quality, url, headers}
  final List<Map<String, String>> subtitles; // {lang, url}
  final bool hasDub;
  final bool hasSub;
  final int latencyMs;

  const StreamInfo({
    required this.providerName,
    required this.engine,
    required this.url,
    this.headers,
    this.qualities = const [],
    this.subtitles = const [],
    this.hasDub = false,
    this.hasSub = false,
    this.latencyMs = 0,
  });
}

/// What the player needs to know about resolution progress.
class ResolveState {
  final List<StreamInfo> streams;
  final List<String> failures;
  final bool isSearching;
  final bool isDrained;

  const ResolveState({
    this.streams = const [],
    this.failures = const [],
    this.isSearching = true,
    this.isDrained = false,
  });

  StreamInfo? get best => streams.isEmpty ? null : streams.first;

  bool get hasAny => streams.isNotEmpty;

  ResolveState copyWith({
    List<StreamInfo>? streams,
    List<String>? failures,
    bool? isSearching,
    bool? isDrained,
  }) => ResolveState(
    streams: streams ?? this.streams,
    failures: failures ?? this.failures,
    isSearching: isSearching ?? this.isSearching,
    isDrained: isDrained ?? this.isDrained,
  );
}

enum StreamKind { movie, series, anime }

class StreamResolver {
  StreamResolver({
    required this.tmdbId,
    required this.title,
    required this.isMovie,
    this.season = 1,
    this.episode = 1,
    this.isDub = false,
    this.isAnime = false,
    this.perProviderTimeout = const Duration(seconds: 20),
  });

  final String tmdbId;
  final String title;
  final bool isMovie;
  final int season;
  final int episode;
  final bool isDub;
  final bool isAnime;
  final Duration perProviderTimeout;

  final _stateController = StreamController<ResolveState>.broadcast();
  Stream<ResolveState> get state => _stateController.stream;

  ResolveState _state = const ResolveState();
  ResolveState get currentState => _state;

  final List<StreamInfo> _streams = [];
  final List<String> _failures = [];
  final List<String> _seenProviders = [];

  bool _cancelled = false;

  /// Currently selected stream (for failover / manual switch).
  StreamInfo? _selected;
  StreamInfo? get selected => _selected;
  void select(StreamInfo info) {
    _selected = info;
    _emit();
  }

  /// Rotate to the next known-good stream. Returns null if there is nothing
  /// else to try (which is the player's cue to show the "all providers down"
  /// screen rather than retrying forever).
  StreamInfo? failover() {
    if (_streams.length < 2) return null;
    final index = _selected == null ? 0 : _streams.indexOf(_selected!);
    _selected = _streams[(index + 1) % _streams.length];
    _emit();
    return _selected;
  }

  /// Starts resolving. Emits progressively; completes when every provider has
  /// either answered or timed out.
  Future<void> start() async {
    final kind = isMovie
        ? StreamKind.movie
        : (isAnime ? StreamKind.anime : StreamKind.series);
    final providers = _providersFor(kind, isAnime);

    if (providers.isEmpty) {
      _state = _state.copyWith(isSearching: false, isDrained: true);
      _emit();
      Log.w(_tag, 'no providers configured for $kind');
      return;
    }

    Log.i(
      _tag,
      'racing ${providers.length} providers for "$title" '
      'S$season E$episode (anime=$isAnime dub=$isDub)',
    );

    // Fire all of them at once. Each completion updates state on its own.
    await Future.wait(providers.map(_resolveOne), eagerError: false);

    if (_cancelled) return;
    _state = _state.copyWith(isSearching: false, isDrained: true);
    _emit();
    Log.i(
      _tag,
      'resolution drained: ${_streams.length} ok, ${_failures.length} failed',
    );
  }

  List<Map<String, dynamic>> _providersFor(StreamKind kind, bool anime) {
    final all = List<Map<String, dynamic>>.from(
      RemoteConfigService.activeProviders.whereType<Map<String, dynamic>>(),
    );

    if (anime) {
      // Anime may be served by the extractor engines and/or a dedicated
      // anime engine. Never fall back to the movie-only provider list, which
      // is what the old `_isAnime` check effectively did when Miruro was gone.
      final animeCapable = all.where((p) {
        final engine = (p['engine'] ?? '').toString();
        return engine == 'native_extractor' ||
            engine == 'native_stremio' ||
            p['anime'] == true;
      }).toList();
      return animeCapable.isEmpty ? all : animeCapable;
    }

    return all.where((p) => p['anime_only'] != true).toList();
  }

  Future<void> _resolveOne(Map<String, dynamic> provider) async {
    final name = (provider['name'] ?? provider['engine'] ?? 'Unknown')
        .toString();
    if (_seenProviders.contains(name)) return;
    _seenProviders.add(name);

    final started = DateTime.now();
    try {
      final playback = await _buildPlayback(provider).timeout(
        perProviderTimeout,
        onTimeout: () => throw AppError(
          AppErrorKind.timeout,
          '$name timed out after ${perProviderTimeout.inSeconds}s',
        ),
      );

      if (_cancelled) return;

      final url = playback?['url']?.toString();
      if (url == null || url.isEmpty) {
        _fail(name, 'returned no stream');
        return;
      }

      final info = StreamInfo(
        providerName: name,
        engine: (provider['engine'] ?? 'webview').toString(),
        url: url,
        headers: (playback!['headers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
        qualities: _qualityList(playback['streams']),
        subtitles: _subtitleList(playback['subtitles']),
        hasDub: playback['hasDub'] == true,
        hasSub: playback['hasSub'] == true,
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );

      _streams.add(info);
      _streams.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
      // First success wins — the user can start watching immediately.
      _selected ??= _streams.first;
      Log.i(_tag, '✅ $name in ${info.latencyMs}ms');
      _emit();
    } on AppError catch (e) {
      _fail(name, e.kind.name);
    } catch (e) {
      _fail(name, e.toString());
    }
  }

  List<Map<String, dynamic>> _qualityList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (s) => <String, dynamic>{
            'quality': s['quality'] ?? 'Auto',
            'url': s['url'],
            'headers': s['headers'] ?? const <String, String>{},
          },
        )
        .where((s) => s['url'] != null)
        .toList(growable: false);
  }

  List<Map<String, String>> _subtitleList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .where((s) => s['url'] != null)
        .map(
          (s) => <String, String>{
            'lang': (s['lang'] ?? 'unknown').toString(),
            'url': s['url'].toString(),
          },
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> _buildPlayback(
    Map<String, dynamic> provider,
  ) async {
    final engine = (provider['engine'] ?? 'webview').toString();

    // Native engines call out to a service; webview engines just need a URL.
    if (engine.startsWith('native_') && engine != 'native_extractor') {
      return StreamingAggregatorService.getNativeStreamingUrl(
        title: title,
        engine: engine,
        tmdbId: tmdbId, // ← the field PlaybackManager forgot to pass
        isMovie: isMovie,
        season: season,
        episodeNumber: episode,
        isDub: isDub,
      );
    }

    return {
      'url': await buildEmbedUrl(
        provider,
        tmdbId: tmdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        isAnime: isAnime,
      ),
    };
  }

  /// Builds a provider embed URL. Kept static + pure so it is unit-testable
  /// without a widget tree (the old copy of this lived inside a State class).
  /// [isAnime] lets a provider expose a dedicated `anime_url` (used by
  /// servers that route anime to a different catalogue).
  static Future<String?> buildEmbedUrl(
    Map<String, dynamic> provider, {
    required String tmdbId,
    required bool isMovie,
    required int season,
    required int episode,
    bool isAnime = false,
  }) async {
    final idType = (provider['id_type'] ?? 'tmdb').toString();
    final format = (provider['format_style'] ?? 'slash').toString();
    final animeUrl = provider['anime_url']?.toString();
    final base = (isAnime && animeUrl != null && animeUrl.isNotEmpty)
        ? animeUrl
        : (isMovie ? provider['movie_url'] : provider['tv_url'])?.toString();
    if (base == null || base.isEmpty) {
      throw const AppError(AppErrorKind.badRequest, 'provider has no base url');
    }

    var targetId = tmdbId;
    if (idType == 'imdb') {
      final parsed = int.tryParse(tmdbId);
      if (parsed == null) {
        throw AppError(AppErrorKind.badRequest, 'bad tmdbId "$tmdbId"');
      }
      final imdb = await TmdbClient.getImdbId(parsed, isMovie);
      if (imdb == null || imdb.isEmpty) {
        // Old code aborted here, which is why imdb-only providers vanished
        // for titles TMDB has no imdb id for. Falling back to tmdb keeps them.
        targetId = tmdbId;
      } else {
        targetId = imdb;
      }
    }

    if (isMovie) return '$base$targetId';

    return switch (format) {
      'slash' => '$base$targetId/$season/$episode',
      'query' => '$base$targetId&s=$season&e=$episode',
      'query_mix' => '$base$targetId&s=$season&e=$episode',
      'dash' => '$base$targetId-$season-$episode',
      _ => '$base$targetId/$season/$episode',
    };
  }

  static const String _tag = 'Resolver';

  void _fail(String name, String reason) {
    _failures.add('$name: $reason');
    _emit();
  }

  void _emit() {
    if (_stateController.isClosed || _cancelled) return;
    _state = _state.copyWith(
      streams: List.unmodifiable(_streams),
      failures: List.unmodifiable(_failures),
    );
    _stateController.add(_state);
  }

  void cancel() {
    _cancelled = true;
    _streams.clear();
    _selected = null;
    _stateController.close();
  }

  /// Diagnostics for the "all providers down" screen and the debug panel.
  Map<String, dynamic> get diagnostics => {
    'title': title,
    'tmdbId': tmdbId,
    'kind': isMovie ? 'movie' : (isAnime ? 'anime' : 'series'),
    'season': season,
    'episode': episode,
    'dub': isDub,
    'providersTried': _seenProviders.length,
    'succeeded': _streams.length,
    'failed': _failures,
    'proxyConfigured': AppConfig.proxifyStreamsUrl.isNotEmpty,
  };
}
