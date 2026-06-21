import 'dart:async';
import 'package:flutter/material.dart';
import '../services/remote_config_service.dart';
import '../services/streaming_aggregator_service.dart';
import '../services/tmdb_service.dart';

/// Model representing a successful stream from a provider.
class StreamInfo {
  final String providerName;
  final String engine;
  final String url;
  final Map<String, String>? headers;
  final List<Map<String, dynamic>> qualities; // each: {quality, url, headers}
  final List<Map<String, String>> subtitles; // each: {lang, url}
  final bool hasDub;
  final bool hasSub;

  StreamInfo({
    required this.providerName,
    required this.engine,
    required this.url,
    this.headers,
    required this.qualities,
    required this.subtitles,
    required this.hasDub,
    required this.hasSub,
  });
}

/// Manages provider batch search, caching of successful streams, and failover.
class PlaybackManager {
  final BuildContext context;
  final String tmdbId;
  final bool isMovie;
  final String title;

  // All providers defined in remote config.
  List<Map<String, dynamic>> _allProviders = [];
  // Cached successful streams for the current playback session.
  final List<StreamInfo> _availableStreams = [];
  // Index of the currently playing provider in _availableStreams.
  int _currentStreamIdx = -1;

  // UI callbacks to notify PlayerScreen of changes.
  VoidCallback? onStreamsUpdated;
  VoidCallback? onCurrentStreamChanged;

  PlaybackManager({
    required this.context,
    required this.tmdbId,
    required this.isMovie,
    required this.title,
  });

  List<StreamInfo> get availableStreams => List.unmodifiable(_availableStreams);
  StreamInfo? get currentStream =>
      (_currentStreamIdx >= 0 && _currentStreamIdx < _availableStreams.length)
          ? _availableStreams[_currentStreamIdx]
          : null;

  bool _currentIsDub = false;

  /// Initialise providers list and start batch search.
  Future<void> initAndSearch({bool isAnime = false, bool isDub = false, int season = 1, int episode = 1}) async {
    _currentIsDub = isDub;
    _allProviders = List<Map<String, dynamic>>.from(RemoteConfigService.activeProviders);
    
    if (isAnime) {
      _allProviders = _allProviders.where((p) => p['engine'] == 'native_miruro').toList();
    } else {
      _allProviders = _allProviders.where((p) => p['engine'] != 'native_miruro').toList();
    }

    // Prioritize native engines so they are searched first!
    _allProviders.sort((a, b) {
      bool aNative = (a['engine'] ?? '').toString().startsWith('native_');
      bool bNative = (b['engine'] ?? '').toString().startsWith('native_');
      if (aNative && !bNative) return -1;
      if (!aNative && bNative) return 1;
      return 0;
    });

    const batchSize = 3;
    for (int i = 0; i < _allProviders.length; i += batchSize) {
      final batch = _allProviders.sublist(
          i, (i + batchSize).clamp(0, _allProviders.length));
      await _searchBatch(batch, season, episode);
      // Removed the break statement here so it continues searching remaining batches in the background
      // This populates the entire dropdown list!
    }

    // --- USER REQUESTED DEBUG LOGS ---
    int loaded = _allProviders.length;
    int successful = _availableStreams.length;
    // We calculate "failed" based on all loaded providers minus the successful ones, 
    // keeping in mind some may have been skipped due to early break.
    int failed = loaded - successful;
    print("\n=================== PROVIDER DEBUG LOG ===================");
    print("Loaded Providers: $loaded");
    print("Successful Providers: $successful");
    print("Failed Providers (or skipped): $failed");
    print("Dropdown Count: $successful");
    print("==========================================================\n");
  }

  /// Search a batch of providers concurrently.
  Future<void> _searchBatch(List<Map<String, dynamic>> batch, int season, int episode) async {
    final futures = batch.map((provider) async {
      final playbackData = await _buildPlaybackUrl(provider, season, episode);
      if (playbackData != null && playbackData['url'] != null) {
        final qualities = (playbackData['streams'] as List<dynamic>? ?? [])
            .map((s) => {
                  'quality': s['quality'],
                  'url': s['url'],
                  'headers': s['headers'] ?? {},
                })
            .toList();
        final subtitles = (playbackData['subtitles'] as List<dynamic>? ?? [])
            .map<Map<String, String>>((sub) => {
                  'lang': sub['lang'] as String,
                  'url': sub['url'] as String,
                })
            .toList();
        print("PLAYBACK MANAGER: provider engine is ${provider['engine']}"); final info = StreamInfo(
          providerName: provider['name'] ?? provider['engine'] ?? 'Unknown Server',
          engine: provider['engine'] ?? 'webview',
          url: playbackData['url'] as String,
          headers: (playbackData['headers'] as Map?)?.cast<String, String>(),
          qualities: qualities,
          subtitles: subtitles,
          hasDub: playbackData['hasDub'] == true,
          hasSub: playbackData['hasSub'] == true,
        );
        _availableStreams.add(info);
        if (currentStream == null) {
          _currentStreamIdx = _availableStreams.length - 1;
          onCurrentStreamChanged?.call();
        }
        onStreamsUpdated?.call();
      }
    }).toList();
    await Future.wait(futures);
  }

  /// Mirrors PlayerScreen._buildPlaybackUrl for native providers.
  Future<Map<String, dynamic>?> _buildPlaybackUrl(
      Map<String, dynamic> provider, int season, int episode) async {
    final String engine = provider['engine'] ?? 'webview';
    if (engine.startsWith('native_') && engine != 'native_extractor') {
      return await StreamingAggregatorService.getNativeStreamingUrl(
        title: title,
        engine: engine,
        season: season,
        episodeNumber: episode,
        isDub: _currentIsDub,
      );
    }
    // Non‑native (webview) providers – construct URL similarly to PlayerScreen.
    final String idType = provider['id_type'];
    final String formatStyle = provider['format_style'];
    final String baseUrl = isMovie ? provider['movie_url'] : provider['tv_url'];
    String targetId = tmdbId;
    if (idType == 'imdb') {
      final imdbId = await TmdbService.getImdbId(
          int.parse(tmdbId), isMovie);
      if (imdbId != null && imdbId.isNotEmpty) targetId = imdbId;
    }
    // Very simple handling – only slash style needed for current UI.
    if (isMovie) {
      return {'url': '$baseUrl$targetId'};
    } else {
      return {'url': '$baseUrl$targetId/$season/$episode'};
    }
  }

  /// Switch to the next successful provider preserving playback position.
  void failoverToNext() {
    if (_availableStreams.isEmpty) return;
    _currentStreamIdx = (_currentStreamIdx + 1) % _availableStreams.length;
    onCurrentStreamChanged?.call();
  }

  /// Set current stream by provider name if exists.
  void setCurrentProviderByName(String name) {
    final idx = _availableStreams.indexWhere((s) => s.providerName == name);
    if (idx >= 0) {
      _currentStreamIdx = idx;
      onCurrentStreamChanged?.call();
    }
  }

  /// Set current stream by exact stream object.
  void setCurrentStream(StreamInfo stream) {
    final idx = _availableStreams.indexOf(stream);
    if (idx >= 0) {
      _currentStreamIdx = idx;
      onCurrentStreamChanged?.call();
    }
  }

  /// Clear cache when a new movie/episode is selected.
  void clearCache() {
    _availableStreams.clear();
    _currentStreamIdx = -1;
    onStreamsUpdated?.call();
  }
}
