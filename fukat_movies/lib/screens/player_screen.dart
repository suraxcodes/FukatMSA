import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../player/player_controller.dart';
import '../services/ad_block_service.dart';
import '../services/network_service.dart';
import '../widgets/episode_side_panel.dart';

/// Player surface. Rendering + WebView/extractor plumbing only — all playback
/// state lives in [PlayerController].
class PlayerScreen extends StatefulWidget {
  final String tmdbId;
  final bool isMovie;
  final String title;

  const PlayerScreen({
    super.key,
    required this.tmdbId,
    required this.isMovie,
    required this.title,
  });

  @override
  State<PlayerScreen> createState() => PlayerScreenState();
}

class PlayerScreenState extends State<PlayerScreen> with WindowListener {
  late final PlayerController _controller;

  HeadlessInAppWebView? _headlessWebView;

  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isExtracting = false;
  Timer? _hideControlsTimer;
  Timer? _flashTimer;
  IconData? _flashIcon;
  double _flashOpacity = 0;
  StreamSubscription<String>? _extractedUrlSub;

  @override
  void initState() {
    super.initState();
    _controller = PlayerController(
      tmdbId: widget.tmdbId,
      title: widget.title,
      isMovie: widget.isMovie,
    )..addListener(_onControllerChanged);

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
    }
    NetworkService().initialize();
    _controller.start();
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _flashTimer?.cancel();
    _extractedUrlSub?.cancel();
    _headlessWebView?.dispose();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      // Drive external engines when the controller publishes a new URL.
    });
    final state = _controller.state;
    if (state.isExtractorEngine && state.url.isNotEmpty && !_isExtracting) {
      _startExtractor(state.url);
    }
  }

  // ------------------------------------------------------------ fullscreen

  Future<void> _setFullScreen(bool enable) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.setFullScreen(enable);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        enable ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
    if (mounted) setState(() => _isFullscreen = enable);
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullscreen = false);
  }

  // -------------------------------------------------------------- extractor

  /// Headless WebView that sniffs the real .m3u8 out of an embed page.
  Future<void> _startExtractor(String embedUrl) async {
    _isExtracting = true;
    await _headlessWebView?.dispose();

    final streamUrls = StreamController<String>();

    _headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
      initialSettings: InAppWebViewSettings(
        useShouldInterceptRequest: true,
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        userAgent: Platform.isWindows
            ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            : 'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          forMainFrameOnly: false,
          source: '''
            (function () {
              const report = (u) => { try { window.flutter_inappwebview.callHandler('stream', u); } catch (e) {} };
              const origFetch = window.fetch;
              window.fetch = function () {
                const u = arguments[0];
                if (typeof u === 'string' && (u.includes('.m3u8') || u.includes('.mp4'))) report(u);
                return origFetch.apply(this, arguments);
              };
              setTimeout(function () {
                document.querySelectorAll('button, .play-button, .vjs-big-play-button, .plyr__control--overlaid')
                  .forEach(b => { try { b.click(); } catch (e) {} });
              }, 1200);
            })();
          ''',
        ),
      ]),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'stream',
          callback: (args) {
            if (args.isNotEmpty) streamUrls.add(args.first.toString());
            return null;
          },
        );
      },
    );

    await _headlessWebView?.run();

    _extractedUrlSub?.cancel();
    _extractedUrlSub = streamUrls.stream
        .where((u) => u.startsWith('http'))
        .take(1)
        .timeout(const Duration(seconds: 25), onTimeout: (sink) => sink.close())
        .listen(
          (url) async {
            _isExtracting = false;
            await _headlessWebView?.dispose();
            _headlessWebView = null;
            if (!mounted) return;
            // Feed the extracted URL through the native player path.
            await _controller.playExtractedStream(url);
          },
          onDone: () {
            if (!_isExtracting) return;
            _isExtracting = false;
            _controller.reportExternalError(
              'The embed page never revealed a stream URL. It may be down, or it '
              'now requires an interaction we cannot automate.',
            );
          },
        );
  }

  // ---------------------------------------------------------------- chrome

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _flash(IconData icon) {
    _flashTimer?.cancel();
    setState(() {
      _flashIcon = icon;
      _flashOpacity = 1;
    });
    _flashTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _flashOpacity = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          setState(() => _showControls = !_showControls);
          if (_showControls) _scheduleHideControls();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildStage(state),
            if (_flashOpacity > 0 && _flashIcon != null)
              IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _flashOpacity,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(_flashIcon, size: 78, color: Colors.white70),
                  ),
                ),
              ),
            if (state.fatalError != null)
              _AllProvidersDown(
                message: state.fatalError!.message,
                failures: state.failures,
                onRetry: _controller.retryResolution,
                onExit: () => Navigator.maybePop(context),
              ),
            if (state.isInitializing && state.fatalError == null)
              const _LoadingOverlay(),
            AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: _buildControls(state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStage(PlayerState state) {
    if (state.isNativeEngine && _controller.videoController != null) {
      return Video(
        controller: _controller.videoController!,
        controls: NoVideoControls,
        fit: BoxFit.contain,
      );
    }

    if (state.isWebViewEngine && state.url.isNotEmpty) {
      return InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(state.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          userAgent: Platform.isWindows
              ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
              : null,
        ),
        onLoadStop: (controller, url) async {
          final script = await AdBlockService.getUiCleanerScript(
            url?.toString() ?? '',
          );
          await controller.evaluateJavascript(source: script);
        },
      );
    }

    if (state.isExtractorEngine) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              _isExtracting ? 'Extracting stream…' : 'Preparing stream…',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              'Some sources take up to 25 seconds.',
              style: TextStyle(color: Colors.white30, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: Text(
        'Waiting for a source…',
        style: TextStyle(color: Colors.white38),
      ),
    );
  }

  Widget _buildControls(PlayerState state) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent, Colors.black87],
          stops: [0, 0.35, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: Text(
                    widget.isMovie
                        ? widget.title
                        : '${widget.title} · S${state.season} E${state.episode}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
                if (!widget.isMovie && state.seasons.isNotEmpty)
                  IconButton(
                    tooltip: 'Episodes',
                    icon: const Icon(Icons.list, color: Colors.white),
                    onPressed: () => _openEpisodePanel(state),
                  ),
                _serverChip(state),
                if (state.qualities.length > 1) _qualityButton(state),
                if (state.hasDub) _audioButton(state),
                if (state.apiSubtitles.isNotEmpty ||
                    state.embeddedSubtitles.isNotEmpty)
                  _subtitleButton(state),
                IconButton(
                  tooltip: 'Report a problem',
                  icon: const Icon(
                    Icons.bug_report_outlined,
                    color: Colors.white54,
                  ),
                  onPressed: () => _showDiagnostics(state),
                ),
                IconButton(
                  icon: Icon(
                    _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                  ),
                  onPressed: () => _setFullScreen(!_isFullscreen),
                ),
              ],
            ),
            const Spacer(),
            if (state.isNativeEngine)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 56,
                    icon: const Icon(Icons.replay_10, color: Colors.white),
                    onPressed: () =>
                        _seekRelative(const Duration(seconds: -10)),
                  ),
                  IconButton(
                    iconSize: 72,
                    icon: Icon(
                      state.isPlaying ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                    ),
                    onPressed: () async {
                      await _controller.togglePlayPause();
                      _flash(
                        _controller.state.isPlaying
                            ? Icons.play_arrow
                            : Icons.pause,
                      );
                      _scheduleHideControls();
                    },
                  ),
                  IconButton(
                    iconSize: 56,
                    icon: const Icon(Icons.forward_10, color: Colors.white),
                    onPressed: () => _seekRelative(const Duration(seconds: 10)),
                  ),
                ],
              ),
            const Spacer(),
            if (state.failures.isNotEmpty && state.fatalError == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${state.failures.length} source(s) unavailable',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _seekRelative(Duration delta) async {
    // media_kit exposes position through the player; ask the controller.
    final current = _controller.state;
    if (!current.isNativeEngine) return;
    _flash(delta.isNegative ? Icons.fast_rewind : Icons.fast_forward);
  }

  /// "Auto: Videasy" — makes it obvious the app chose for you, and lets you
  /// override it. Manual switching still exists; it is no longer required.
  Widget _serverChip(PlayerState state) {
    final streams = _controller.resolver?.currentState.streams ?? const [];
    if (streams.isEmpty) return const SizedBox.shrink();

    final current = _controller.currentStreamName;
    final playable = state.failures.isEmpty;

    return TextButton.icon(
      onPressed: () => _showServerPicker(state),
      icon: Icon(
        playable ? Icons.check_circle : Icons.warning_amber,
        size: 16,
        color: playable ? Colors.greenAccent : Colors.orangeAccent,
      ),
      label: Text(
        current == null ? 'Auto' : 'Auto: $current',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  void _showServerPicker(PlayerState state) {
    final streams = _controller.resolver?.currentState.streams ?? const [];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                'Servers',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'The app already picked a working one. Tap any server only if '
                'you want a different audio track or quality.',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: streams.length,
                itemBuilder: (context, index) {
                  final stream = streams[index];
                  final isCurrent =
                      stream.providerName == _controller.currentStreamName;
                  final failed = state.failures.any(
                    (f) => f.startsWith(stream.providerName),
                  );
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isCurrent
                          ? Icons.play_circle
                          : (failed
                                ? Icons.error_outline
                                : Icons.circle_outlined),
                      color: isCurrent
                          ? Colors.redAccent
                          : (failed ? Colors.white24 : Colors.white38),
                      size: 20,
                    ),
                    title: Text(
                      stream.providerName,
                      style: TextStyle(
                        color: isCurrent ? Colors.white : Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      [
                        stream.engine,
                        if (stream.qualities.isNotEmpty)
                          '${stream.qualities.length} quality option(s)',
                        if (stream.latencyMs > 0) '${stream.latencyMs}ms',
                      ].join(' · '),
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _controller.selectStream(stream);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _qualityButton(PlayerState state) =>
      PopupMenuButton<Map<String, dynamic>>(
        tooltip: 'Quality',
        icon: const Icon(Icons.tune, color: Colors.white),
        onSelected: _controller.selectQuality,
        itemBuilder: (context) => state.qualities
            .map(
              (q) => PopupMenuItem(
                value: q,
                child: Text(
                  '${q['quality']}',
                  style: TextStyle(
                    color: q['quality'] == state.selectedQuality
                        ? Colors.redAccent
                        : Colors.white,
                  ),
                ),
              ),
            )
            .toList(),
      );

  Widget _audioButton(PlayerState state) => IconButton(
    tooltip: state.isDub ? 'Dubbed' : 'Subtitled',
    icon: Icon(
      state.isDub ? Icons.record_voice_over : Icons.subtitles,
      color: Colors.white,
    ),
    onPressed: () {
      _controller.toggleDub();
      _scheduleHideControls();
    },
  );

  Widget _subtitleButton(PlayerState state) => PopupMenuButton<dynamic>(
    tooltip: 'Subtitles',
    icon: const Icon(Icons.closed_caption, color: Colors.white),
    onSelected: _controller.selectSubtitle,
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: null,
        child: Text('Off', style: TextStyle(color: Colors.white)),
      ),
      ...state.apiSubtitles.map(
        (sub) => PopupMenuItem(
          value: sub['url'],
          child: Text(
            '${sub['lang']}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    ],
  );

  void _openEpisodePanel(PlayerState state) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: EpisodeSidePanel(
          tmdbId: widget.tmdbId,
          currentSeason: state.season,
          currentEpisode: state.episode,
          onEpisodeSelected: _controller.changeEpisode,
          seasons: state.seasons,
          isDub: state.isDub,
          hasDub: state.hasDub,
          onAudioChanged: (_) => _controller.toggleDub(),
          watchedEpisodes: state.watchedEpisodes,
          seasonEpisodeCounts: state.seasonEpisodeCounts,
        ),
      ),
    );
  }

  void _showDiagnostics(PlayerState state) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B1B),
        title: const Text(
          'Playback diagnostics',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Text(
            _controller.diagnostics.entries
                .map((e) => '${e.key}: ${e.value}')
                .join('\n'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black54,
    child: const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.redAccent),
          SizedBox(height: 16),
          Text(
            'Finding a working source…',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

/// The screen that should have existed all along: an honest explanation
/// instead of an endless spinner when nothing can play.
class _AllProvidersDown extends StatelessWidget {
  final String message;
  final List<String> failures;
  final Future<void> Function() onRetry;
  final VoidCallback onExit;

  const _AllProvidersDown({
    required this.message,
    required this.failures,
    required this.onRetry,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final isAnime = message.toLowerCase().contains('dub');

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.redAccent, size: 52),
              const SizedBox(height: 18),
              const Text(
                'No working source',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'What you can try',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...[
                      'Wait ~30 seconds and retry — free-tier backends sleep.',
                      'Add a provider repository in Settings → Providers.',
                      if (isAnime) 'Try the other audio track (sub/dub).',
                    ].map(
                      (tip) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $tip',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (failures.isNotEmpty) ...[
                const SizedBox(height: 10),
                ExpansionTile(
                  title: Text(
                    'Show ${failures.length} failure(s)',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  children: failures
                      .map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            f,
                            style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: onExit,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    onPressed: () => onRetry(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
