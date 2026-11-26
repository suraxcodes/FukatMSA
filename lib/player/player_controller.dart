/// All player *state*, with no widget code.
///
/// This is the extraction promised in the review: `player_screen.dart` was a
/// 2,466-line StatefulWidget with 43 `setState` calls, so a play/pause flash
/// animation re-built the video surface, and every playback concern
/// (resolution, extractor, subtitles, quality, progress) was entangled with
/// layout. State now lives here; the screen only renders [PlayerState].
///
/// Responsibilities kept deliberately separate:
///   * [StreamResolver]  — which provider to use (network, racing).
///   * [PlayerController] — media_kit lifecycle, tracks, progress, failover.
///   * PlayerScreen      — pixels.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../core/errors.dart';
import '../core/media_classifier.dart';
import '../core/log.dart';
import '../services/continue_watching_service.dart';
import '../services/network_service.dart';
import '../services/playback_prefs_service.dart';
import '../services/provider_reputation.dart';
import '../services/stream_resolver.dart';
import '../services/streaming_aggregator_service.dart';
import '../services/tmdb_client.dart';
import 'stream_prober.dart';

/// Immutable snapshot of everything the UI needs to draw the player.
@immutable
class PlayerState {
  final bool isInitializing;
  final bool isPlaying;
  final String engine;
  final String url;
  final Map<String, String>? headers;
  final List<Map<String, dynamic>> qualities;
  final List<Map<String, dynamic>> apiSubtitles;
  final List<mk.SubtitleTrack> embeddedSubtitles;
  final List<mk.AudioTrack> audioTracks;
  final String? selectedAudioLang;
  final String? selectedQuality;
  final dynamic selectedSubtitleTrack;
  final bool hasDub;
  final bool hasSub;
  final bool isDub;
  final String season;
  final String episode;
  final List<String> seasons;
  final Map<String, int> seasonEpisodeCounts;
  final Set<String> watchedEpisodes;
  final String? bannerUrl;
  final List<String> failures;

  /// Non-null when we know nothing can play: drives the "all providers down"
  /// screen instead of an infinite spinner.
  final AppError? fatalError;

  const PlayerState({
    this.isInitializing = true,
    this.isPlaying = false,
    this.engine = 'webview',
    this.url = '',
    this.headers,
    this.qualities = const [],
    this.apiSubtitles = const [],
    this.embeddedSubtitles = const [],
    this.audioTracks = const [],
    this.selectedAudioLang,
    this.selectedQuality,
    this.selectedSubtitleTrack,
    this.hasDub = false,
    this.hasSub = true,
    this.isDub = false,
    this.season = '1',
    this.episode = '1',
    this.seasons = const [],
    this.seasonEpisodeCounts = const {},
    this.watchedEpisodes = const {},
    this.bannerUrl,
    this.failures = const [],
    this.fatalError,
  });

  bool get isNativeEngine =>
      engine.startsWith('native_') && engine != 'native_extractor';
  bool get isExtractorEngine => engine == 'native_extractor';
  bool get isWebViewEngine => !isNativeEngine && !isExtractorEngine;

  PlayerState copyWith({
    bool? isInitializing,
    bool? isPlaying,
    String? engine,
    String? url,
    Map<String, String>? headers,
    bool clearHeaders = false,
    List<Map<String, dynamic>>? qualities,
    List<Map<String, dynamic>>? apiSubtitles,
    List<mk.SubtitleTrack>? embeddedSubtitles,
    List<mk.AudioTrack>? audioTracks,
    String? selectedAudioLang,
    String? selectedQuality,
    dynamic selectedSubtitleTrack,
    bool? hasDub,
    bool? hasSub,
    bool? isDub,
    String? season,
    String? episode,
    List<String>? seasons,
    Map<String, int>? seasonEpisodeCounts,
    Set<String>? watchedEpisodes,
    String? bannerUrl,
    List<String>? failures,
    AppError? fatalError,
    bool clearFatalError = false,
  }) {
    return PlayerState(
      isInitializing: isInitializing ?? this.isInitializing,
      isPlaying: isPlaying ?? this.isPlaying,
      engine: engine ?? this.engine,
      url: url ?? this.url,
      headers: clearHeaders ? null : (headers ?? this.headers),
      qualities: qualities ?? this.qualities,
      apiSubtitles: apiSubtitles ?? this.apiSubtitles,
      embeddedSubtitles: embeddedSubtitles ?? this.embeddedSubtitles,
        audioTracks: audioTracks ?? this.audioTracks,
        selectedAudioLang: selectedAudioLang ?? this.selectedAudioLang,
        selectedQuality: selectedQuality ?? this.selectedQuality,
      selectedSubtitleTrack:
          selectedSubtitleTrack ?? this.selectedSubtitleTrack,
      hasDub: hasDub ?? this.hasDub,
      hasSub: hasSub ?? this.hasSub,
      isDub: isDub ?? this.isDub,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      seasons: seasons ?? this.seasons,
      seasonEpisodeCounts: seasonEpisodeCounts ?? this.seasonEpisodeCounts,
      watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      failures: failures ?? this.failures,
      fatalError: clearFatalError ? null : (fatalError ?? this.fatalError),
    );
  }
}

class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.tmdbId,
    required this.title,
    required this.isMovie,
  });

  static const String _tag = 'Player';

  final String tmdbId;
  final String title;
  final bool isMovie;

  PlayerState _state = const PlayerState();
  PlayerState get state => _state;

  mk.Player? _mediaPlayer;
  VideoController? _videoController;
  VideoController? get videoController => _videoController;

  StreamResolver? _resolver;
  StreamResolver? get resolver => _resolver;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _progressTimer;
  Timer? _bufferingTimer;
  bool _disposed = false;
  bool _hasRestoredPosition = false;
  Duration _lastPosition = Duration.zero;
  bool _isAnime = false;

  /// Saved playback preferences for the current title (audio/sub/dub language).
  Map<String, dynamic> _savedPrefs = const {};

  /// True while we are verifying candidates instead of blindly opening the
  /// first URL a provider returned. This is what removes the manual
  /// "switch server until one plays" loop.
  bool _isVerifying = false;
  bool get isVerifying => _isVerifying;

  /// Candidates already tried and rejected for the current episode, so
  /// failover never retries a known-bad server.
  final Set<String> _rejected = {};

  /// Startup watchdog: a stream that opens but produces no audio/video is a
  /// stall, not a success. Without this the app waited forever on a dead link.
  Timer? _startupWatchdog;
  bool _sawPlaybackProgress = false;

  void _set(PlayerState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  void _patch(PlayerState Function(PlayerState) update) => _set(update(_state));

  static const int _verifyBatchSize = 2;

  bool _hasStartedPlayback = false;

  /// Applies a stream, then opens it if the engine needs media_kit.
  void _applyAndMaybeOpen(StreamInfo stream) {
    _applyStream(stream);
    if (_state.isNativeEngine) unawaited(openCurrentStream());
  }

  /// Ranks candidates by *verified playability*, then opens the best one.
  ///
  /// Replaces the old "first URL returned wins" behaviour, which is why you
  /// had to keep switching servers manually: provider #1 answering with a 403
  /// still counted as a success.
  Future<void> _verifyAndOpen(List<StreamInfo> candidates) async {
    if (_isVerifying || _disposed) return;

    final fresh = candidates
        .where((c) => !_rejected.contains('${c.providerName}|${c.url}'))
        .toList(growable: false);
    if (fresh.isEmpty) return;

    _isVerifying = true;
    _patch((s) => s.copyWith(isInitializing: true));

    try {
      await ProviderReputation.load();
      final ranked = await StreamProber.rank(
        fresh,
        latencyBonus: ProviderReputation.bonuses,
      );
      if (_disposed) return;

      // Remember rejections so failover never comes back to them.
      for (final candidate in ranked.where((r) => r.probe.isDead)) {
        _rejected.add(
          '${candidate.stream.providerName}|${candidate.stream.url}',
        );
        unawaited(
          ProviderReputation.recordFailure(candidate.stream.providerName),
        );
        Log.w(
          _tag,
          'rejected ${candidate.stream.providerName}: ${candidate.probe.reason}',
        );
      }

      final winner = ranked.firstWhere(
        (r) => !r.probe.isDead,
        orElse: () => ranked.first,
      );

      if (winner.probe.isDead) {
        // Everything in this batch is bad. If resolution is still running,
        // wait for more; otherwise this is genuinely unwatchable.
        _isVerifying = false;
        if (_resolver?.currentState.isDrained ?? true) {
          _patch(
            (s) => s.copyWith(
              isInitializing: false,
              fatalError: AppError(
                AppErrorKind.serverError,
                'Found ${candidates.length} source(s) but none of them play.',
              ),
            ),
          );
        }
        return;
      }

      Log.i(
        _tag,
        'auto-selected ${winner.stream.providerName} '
        '(${winner.probe.verdict.name}${winner.probe.reason == null ? '' : ', ${winner.probe.reason}'})',
      );

      _hasStartedPlayback = true;
      _isVerifying = false;
      _applyAndMaybeOpen(winner.stream);
    } catch (e) {
      Log.w(_tag, 'verification failed, falling back to first candidate', e);
      _isVerifying = false;
      if (!_disposed && candidates.isNotEmpty) {
        _hasStartedPlayback = true;
        _applyAndMaybeOpen(candidates.first);
      }
    }
  }

  // ------------------------------------------------------------------ start

  /// Loads TMDB metadata, restores progress, then races providers.
  Future<void> start() async {
    final details = isMovie
        ? await TmdbClient.getMovieDetails(int.tryParse(tmdbId) ?? 0)
        : await TmdbClient.getSeriesDetails(int.tryParse(tmdbId) ?? 0);

    if (_disposed) return;

    final backdrop = details?['backdrop_path'] as String?;
    final saved = ContinueWatchingService.getItem(tmdbId);

    var season = _state.season;
    var episode = _state.episode;
    if (!isMovie && saved != null) {
      season = saved['lastSeason']?.toString() ?? season;
      episode = saved['lastEpisode']?.toString() ?? episode;
      final pos = saved['position'];
      if (saved['isCompleted'] != true && pos is int && pos > 0) {
        _lastPosition = Duration(seconds: pos);
      }
    }

    _isAnime = _detectAnime(details);

    // Restore saved audio/sub/dub preference for this title.
    _savedPrefs = PlaybackPrefsService.load(
      isMovie: isMovie,
      tmdbId: tmdbId,
    );
    if (_savedPrefs['isDub'] == true) {
      _patch((s) => s.copyWith(isDub: true));
    }

    _patch(
      (s) => s.copyWith(
        isInitializing: false,
        bannerUrl: backdrop == null
            ? null
            : 'https://image.tmdb.org/t/p/w1280$backdrop',
        season: season,
        episode: episode,
        seasons: MediaClassifier.availableSeasons(details),
        seasonEpisodeCounts: MediaClassifier.episodeCounts(details),
        watchedEpisodes: ContinueWatchingService.getWatchedEpisodes(
          tmdbId,
        ).toSet(),
      ),
    );

    await resolve();
  }

  /// Heuristic anime detection — Japanese origin *or* animation genre.
  /// The old code additionally required a `native_miruro` provider to exist,
  /// so once that engine disappeared anime mode never activated and anime was
  /// resolved against movie providers.
  bool _detectAnime(Map<String, dynamic>? details) {
    if (isMovie || details == null) return false;
    final origin = details['origin_country'];
    if (origin is List && origin.contains('JP')) return true;
    final genres = details['genres'];
    if (genres is List) {
      return genres.any(
        (g) => g is Map && (g['name']?.toString().toLowerCase() == 'animation'),
      );
    }
    return false;
  }

  // -------------------------------------------------------------- resolving

  /// Starts (or restarts) provider racing for the current season/episode.
  Future<void> resolve({bool isDub = false}) async {
    _resolver?.cancel();
    _resolver = StreamResolver(
      tmdbId: tmdbId,
      title: title,
      isMovie: isMovie,
      season: int.tryParse(_state.season) ?? 1,
      episode: int.tryParse(_state.episode) ?? 1,
      isDub: isDub,
      isAnime: _isAnime,
    );

    _rejected.clear();

    _subs.add(
      _resolver!.state.listen((resolved) {
        if (_disposed) return;

        _patch((s) => s.copyWith(failures: resolved.failures));

        // Only start choosing once either (a) enough candidates have arrived
        // to compare, or (b) resolution is finished, or (c) the first one is
        // already verified playable — whichever comes first. This keeps the
        // common case fast while still giving us something to compare.
        final readyToChoose =
            resolved.isDrained ||
            resolved.streams.length >= _verifyBatchSize ||
            _isVerifying;

        if (!_isVerifying &&
            !_hasStartedPlayback &&
            readyToChoose &&
            resolved.hasAny) {
          unawaited(_verifyAndOpen(resolved.streams));
        }

        // Drained with nothing: this is the state that used to be an endless
        // spinner. Surface it as a real error with a real explanation.
        if (resolved.isDrained && !resolved.hasAny) {
          _patch(
            (s) => s.copyWith(
              isInitializing: false,
              fatalError: AppError(
                AppErrorKind.serverError,
                'All ${resolved.failures.length} providers failed for '
                '"$title" S${_state.season} E${_state.episode}.',
              ),
            ),
          );
        }
      }),
    );

    _patch((s) => s.copyWith(isDub: isDub, clearFatalError: true));
    await _resolver!.start();
  }

  void _applyStream(StreamInfo stream) {
    _currentProviderName = stream.providerName;
    _patch(
      (s) => s.copyWith(
        url: stream.url,
        headers: stream.headers,
        clearHeaders: stream.headers == null,
        engine: stream.engine,
        qualities: stream.qualities,
        apiSubtitles: stream.subtitles
            .map((sub) => {'lang': sub['lang'], 'url': sub['url']})
            .toList(),
        hasDub: stream.hasDub,
        hasSub: stream.hasSub,
        selectedQuality: stream.qualities.isNotEmpty
            ? stream.qualities.first['quality']?.toString()
            : null,
      ),
    );
  }

  /// Opens [_state.url] in the media_kit player. WebView / extractor engines
  /// are started by the screen, which owns those widgets.
  Future<void> openCurrentStream() async {
    if (!_state.isNativeEngine) return;

    var url = _state.url;
    // A provider that hands back a bare CDN link may need the proxy rewrite.
    if (url.isNotEmpty) {
      url = await StreamingAggregatorService.proxyHlsIfConfigured(url);
    }
    if (url.isEmpty || _disposed) return;

    await _openNativePlayer(url, headers: _state.headers);
  }

  Future<void> _openNativePlayer(
    String url, {
    Map<String, String>? headers,
  }) async {
    Log.i(_tag, 'opening $url');

    await _mediaPlayer?.dispose();
    _subs.removeWhere((s) {
      s.cancel();
      return true;
    });

    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        bufferSize: 1024 * 1024 * 96,
        // Was debug: it printed every MPV frame log to the console.
        logLevel: mk.MPVLogLevel.error,
      ),
    );
    _mediaPlayer = player;

    player.stream.error.listen((error) {
      Log.w(_tag, 'media error: $error');
      _startupWatchdog?.cancel();
      final name = _currentProviderName;
      if (name != null) {
        unawaited(ProviderReputation.recordFailure(name));
        _rejected.add('$name|${_state.url}');
      }
      // One automatic failover, then surface the error rather than looping.
      if (failover() == null) {
        _patch(
          (s) => s.copyWith(
            fatalError: AppError(
              AppErrorKind.serverError,
              'Playback failed: $error',
            ),
          ),
        );
      }
    });

    player.stream.buffering.listen((buffering) {
      _bufferingTimer?.cancel();
      if (!buffering) return;
      _bufferingTimer = Timer(const Duration(seconds: 20), () {
        if (!_disposed && (player.state.buffering)) {
          Log.w(_tag, 'buffering timeout — failing over');
          failover();
        }
      });
    });

    _videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    player.stream.tracks.listen((tracks) {
      if (_disposed) return;
      final audio = tracks.audio
          .where((t) => t.id != 'no' && t.id != 'auto')
          .toList();
      // Auto-select the user's saved audio language for this title (e.g.
      // Japanese for sub, English for dub) so they don't have to re-pick it
      // every episode.
      mk.AudioTrack? autoSelect;
      if (_savedPrefs['audioLang'] != null &&
          _savedPrefs['audioLang'] is String &&
          audio.isNotEmpty) {
        final wanted = _savedPrefs['audioLang'] as String;
        for (final t in audio) {
          if ((t.id ?? '').toLowerCase() == wanted.toLowerCase()) {
            autoSelect = t;
            break;
          }
        }
      }
      _patch(
        (s) => s.copyWith(
          embeddedSubtitles: tracks.subtitle
              .where((t) => t.id != 'no' && t.id != 'auto')
              .toList(),
          audioTracks: audio,
          selectedAudioLang: autoSelect != null ? autoSelect.id : null,
        ),
      );
      if (autoSelect != null) {
        _mediaPlayer?.setAudioTrack(autoSelect);
      }
    });

    player.stream.position.listen((pos) {
      if (pos > Duration.zero) {
        _lastPosition = pos;
        // Any real movement means this stream is genuinely playing — cancel
        // the watchdog and credit the provider.
        if (!_sawPlaybackProgress && pos > const Duration(milliseconds: 1200)) {
          _sawPlaybackProgress = true;
          _startupWatchdog?.cancel();
          final name = _currentProviderName;
          if (name != null) unawaited(ProviderReputation.recordSuccess(name));
          Log.i(_tag, 'verified playing: $name');
        }
      }
    });

    player.stream.duration.listen((duration) {
      if (_hasRestoredPosition || duration <= Duration.zero) return;
      _hasRestoredPosition = true;
      if (_lastPosition > Duration.zero && _lastPosition < duration) {
        player.seek(_lastPosition);
      }
    });

    player.stream.completed.listen((completed) {
      if (!completed || isMovie || _disposed) return;
      saveProgress(forceComplete: true);
      playNextEpisode();
    });

    _hasRestoredPosition = false;
    _sawPlaybackProgress = false;
    await player.open(mk.Media(url, httpHeaders: headers), play: true);

    // Startup watchdog: a dead-but-accepting stream opens fine and then sits
    // there forever. 9s with zero playback progress = assume dead, move on
    // automatically. This is the second half of "stop making me switch servers".
    _startupWatchdog?.cancel();
    _startupWatchdog = Timer(const Duration(seconds: 9), () {
      if (_disposed || _sawPlaybackProgress) return;
      final state = _mediaPlayer?.state;
      final stalled =
          state == null ||
          (state.position <= const Duration(milliseconds: 1200) &&
              !state.playing);
      if (!stalled) return;

      Log.w(_tag, 'stream opened but never played — auto-failing over');
      final name = _currentProviderName;
      if (name != null) {
        unawaited(ProviderReputation.recordStall(name));
        _rejected.add('$name|${_state.url}');
      }
      if (failover() == null) {
        _patch(
          (s) => s.copyWith(
            fatalError: AppError(
              AppErrorKind.serverError,
              'Every source opened but none of them actually play. '
              'The providers may be broken right now.',
            ),
          ),
        );
      }
    });

    _startProgressTicker();
    _patch((s) => s.copyWith(isPlaying: true));
  }

  // ------------------------------------------------------------- transport

  Future<void> togglePlayPause() async {
    final player = _mediaPlayer;
    if (player == null) return;
    await player.playOrPause();
    _patch((s) => s.copyWith(isPlaying: player.state.playing));
  }

  Future<void> seek(Duration position) async {
    await _mediaPlayer?.seek(position);
  }

  Future<void> selectQuality(Map<String, dynamic> stream) async {
    final url = stream['url']?.toString();
    if (url == null || url.isEmpty) return;

    final resumeAt = _mediaPlayer?.state.position ?? Duration.zero;
    _lastPosition = resumeAt;

    _patch(
      (s) => s.copyWith(
        url: url,
        selectedQuality: stream['quality']?.toString(),
        headers: (stream['headers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      ),
    );

    _hasRestoredPosition = false;
    await openCurrentStream();
  }

  void selectSubtitle(dynamic track) {
    _patch((s) => s.copyWith(selectedSubtitleTrack: track));
    if (track is mk.SubtitleTrack) {
      _mediaPlayer?.setSubtitleTrack(track);
      if (track.id != null && track.id.isNotEmpty) {
        unawaited(PlaybackPrefsService.save(
          isMovie: isMovie,
          tmdbId: tmdbId,
          subtitleLang: track.id,
        ));
      }
    }
  }

  void selectAudioTrack(mk.AudioTrack track) {
    _mediaPlayer?.setAudioTrack(track);
    final id = track.id;
    if (id != null && id.isNotEmpty) {
      _patch((s) => s.copyWith(selectedAudioLang: id));
      unawaited(PlaybackPrefsService.save(
        isMovie: isMovie,
        tmdbId: tmdbId,
        audioLang: id,
      ));
    }
  }

  bool toggleDub() {
    final next = !_state.isDub;
    dropPlayer();
    _hasStartedPlayback = false;
    _rejected.clear();
    _patch((s) => s.copyWith(isDub: next));
    unawaited(PlaybackPrefsService.save(
      isMovie: isMovie,
      tmdbId: tmdbId,
      isDub: next,
    ));
    unawaited(resolve(isDub: next));
    return next;
  }

  /// Next successful provider, keeping position. Returns null when there is no
  /// alternative left.
  StreamInfo? failover() {
    // Prefer the next *unrejected* candidate; the resolver's own rotation may
    // hand back a server we already proved dead.
    final all = _resolver?.currentState.streams ?? const <StreamInfo>[];
    final healthy = all
        .where((s) => !_rejected.contains('${s.providerName}|${s.url}'))
        .toList(growable: false);

    StreamInfo? next;
    if (healthy.isNotEmpty) {
      final currentName = _state.url;
      final idx = healthy.indexWhere((s) => s.url != currentName);
      next = idx >= 0 ? healthy[idx] : healthy.first;
      _resolver?.select(next);
    } else {
      next = _resolver?.failover();
    }

    if (next == null) return null;

    final failedProvider = _state.engine.isEmpty ? null : _state.url;
    if (failedProvider != null) {
      unawaited(
        ProviderReputation.recordFailure(_currentProviderName ?? 'unknown'),
      );
    }
    _patch((s) => s.copyWith(clearFatalError: true));
    _applyAndMaybeOpen(next);
    return next;
  }

  String? _currentProviderName;

  /// Which provider is currently on screen — used by the "Auto: X" chip.
  String? get currentStreamName => _currentProviderName;

  void selectStream(StreamInfo stream) {
    _resolver?.select(stream);
    _applyAndMaybeOpen(stream);
  }

  // -------------------------------------------------------------- episodes

  void playNextEpisode() {
    if (isMovie) return;
    final current = int.tryParse(_state.episode);
    if (current == null) return;
    changeEpisode(_state.season, '${current + 1}');
  }

  void changeEpisode(String season, String episode) {
    saveProgress(forceComplete: true);
    dropPlayer();
    _hasStartedPlayback = false;
    _rejected.clear();
    _patch(
      (s) => s.copyWith(
        season: season,
        episode: episode,
        url: '',
        clearHeaders: true,
        qualities: const [],
        apiSubtitles: const [],
        selectedQuality: null,
        clearFatalError: true,
      ),
    );
    unawaited(resolve(isDub: _state.isDub));
  }

  // -------------------------------------------------------------- progress

  void _startProgressTicker() {
    _progressTimer?.cancel();
    // 15s of *watch time*, and only while actually playing. The old timer
    // wrote to Hive + Supabase every 15s even when paused or buffering.
    _progressTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_mediaPlayer?.state.playing == true) saveProgress();
    });
  }

  void saveProgress({bool forceComplete = false}) {
    final player = _mediaPlayer;
    final position = player?.state.position.inSeconds ?? 0;
    final duration = player?.state.duration.inSeconds ?? 0;

    final completed =
        forceComplete || (duration > 0 && position >= duration * 0.9);
    String? watchedKey;
    if (!isMovie && completed) {
      watchedKey = '${_state.season}_${_state.episode}';
      if (!_state.watchedEpisodes.contains(watchedKey)) {
        _patch(
          (s) =>
              s.copyWith(watchedEpisodes: {...s.watchedEpisodes, watchedKey!}),
        );
      }
    }

    unawaited(
      ContinueWatchingService.saveItem(
        tmdbId: tmdbId,
        title: title,
        posterPath: null,
        isMovie: isMovie,
        lastSeason: isMovie ? null : int.tryParse(_state.season),
        lastEpisode: isMovie ? null : int.tryParse(_state.episode),
        position: position > 0 ? position : null,
        duration: duration > 0 ? duration : null,
        isCompleted: completed,
        markEpisodeWatched: watchedKey,
      ),
    );
  }

  /// Plays a URL that the headless extractor pulled out of an embed page.
  ///
  /// The extracted URL is a real m3u8, so it goes to media_kit even though the
  /// *provider's* engine was `native_extractor` (which is not a native engine).
  Future<void> playExtractedStream(String url) async {
    if (url.isEmpty) return;
    _patch((s) => s.copyWith(url: url, engine: 'native_stream'));
    await _openNativePlayer(url, headers: _state.headers);
  }

  /// Hands the current URL to the screen for WebView/extractor playback and
  /// marks the session as playing.
  void beginExternalPlayback() {
    _patch((s) => s.copyWith(isPlaying: true));
    saveProgress();
  }

  void reportExternalError(String message) {
    _patch(
      (s) =>
          s.copyWith(fatalError: AppError(AppErrorKind.serverError, message)),
    );
  }

  /// Clears the fatal state so the UI can offer "try another provider".
  void clearFatalError() => _patch((s) => s.copyWith(clearFatalError: true));

  void dropPlayer() {
    _startupWatchdog?.cancel();
    _bufferingTimer?.cancel();
    _progressTimer?.cancel();
    _subs.removeWhere((s) {
      s.cancel();
      return true;
    });
    _mediaPlayer?.dispose();
    _mediaPlayer = null;
    _videoController = null;
  }

  /// Called when the player is retried from the "all providers down" screen.
  Future<void> retryResolution() async {
    NetworkService().checkNetworkSpeed();
    _patch((s) => s.copyWith(isInitializing: true, clearFatalError: true));
    await resolve(isDub: _state.isDub);
    _patch((s) => s.copyWith(isInitializing: false));
  }

  Map<String, dynamic> get diagnostics => {
    ...?_resolver?.diagnostics,
    'currentEngine': _state.engine,
    'hasUrl': _state.url.isNotEmpty,
    'isAnime': _isAnime,
    'watchedEpisodes': _state.watchedEpisodes.length,
  };

  @override
  void dispose() {
    _disposed = true;
    _startupWatchdog?.cancel();
    saveProgress();
    dropPlayer();
    _resolver?.cancel();
    super.dispose();
  }
}
