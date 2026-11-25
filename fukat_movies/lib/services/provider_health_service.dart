/// Knows whether the provider stack is alive before the user hits play.
///
/// The concrete problem this solves: the app depended on free-tier hosts that
/// suspend or sleep (one was literally returning "This service has been
/// suspended by its owner"). A cold host made *every* provider look broken,
/// and the user got a black player with no explanation.
///
/// Strategy:
///  1. At startup, fire-and-forget "warm up" pings at sleeping hosts so they
///     spin up while the user is browsing the home screen.
///  2. Expose a [probe] that reports per-endpoint status.
///  3. Expose [hasAnyUsableProvider] so the player can show a real
///     "all providers down" screen instead of a spinner forever.
library;

import 'dart:async';

import '../core/app_config.dart';
import '../core/http_json.dart';
import '../core/log.dart';
import 'remote_config_service.dart';

enum ProviderHealth { unknown, warming, up, down }

class EndpointStatus {
  final String label;
  final Uri uri;
  final ProviderHealth health;
  final int? latencyMs;
  final String? detail;

  const EndpointStatus({
    required this.label,
    required this.uri,
    required this.health,
    this.latencyMs,
    this.detail,
  });

  EndpointStatus copyWith({
    ProviderHealth? health,
    int? latencyMs,
    String? detail,
  }) => EndpointStatus(
    label: label,
    uri: uri,
    health: health ?? this.health,
    latencyMs: latencyMs ?? this.latencyMs,
    detail: detail ?? this.detail,
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'url': uri.toString(),
    'health': health.name,
    'latency_ms': latencyMs,
    'detail': detail,
  };
}

class ProviderHealthService {
  ProviderHealthService._();

  static const String _tag = 'Health';

  static final StreamController<List<EndpointStatus>> _statusController =
      StreamController<List<EndpointStatus>>.broadcast();
  static Stream<List<EndpointStatus>> get onStatusChange =>
      _statusController.stream;

  static List<EndpointStatus> _statuses = const [];
  static List<EndpointStatus> get statuses => List.unmodifiable(_statuses);

  static DateTime? _lastProbe;
  static DateTime? get lastProbe => _lastProbe;

  static List<EndpointStatus> _buildTargets() => [
    for (final uri in AppConfig.warmUpTargets)
      EndpointStatus(
        label: _labelFor(uri),
        uri: uri,
        health: ProviderHealth.unknown,
      ),
  ];

  static String _labelFor(Uri uri) {
    if (uri.toString() == AppConfig.remoteConfigUrl) return 'Provider config';
    if (uri.toString() == AppConfig.proxifyStreamsUrl) return 'HLS proxy';
    if (uri.toString() == AppConfig.stremioAddonUrl) return 'Stremio addon';
    return uri.host;
  }

  /// Fire-and-forget at app start. Never awaited by the UI, never throws.
  static void warmUpInBackground() {
    final targets = _buildTargets();
    if (targets.isEmpty) return;

    _statuses = targets
        .map((t) => t.copyWith(health: ProviderHealth.warming))
        .toList(growable: false);
    _emit();

    for (final target in targets) {
      // 30s ceiling: free tiers sometimes need 25s+ to boot.
      unawaited(
        HttpJson.isReachable(
          target.uri,
          timeout: const Duration(seconds: 30),
        ).then((ok) {
          _update(
            target.uri,
            ok ? ProviderHealth.up : ProviderHealth.down,
            detail: ok ? null : 'no response (host may be suspended or asleep)',
          );
        }),
      );
    }
  }

  /// Actively probes every endpoint and returns the results.
  /// Used by the diagnostics screen and by the player's "no streams" state.
  static Future<List<EndpointStatus>> probe({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final targets = _buildTargets();
    if (targets.isEmpty) {
      _statuses = const [];
      _emit();
      return const [];
    }

    final results = await Future.wait(
      targets.map((target) async {
        final started = DateTime.now();
        final ok = await HttpJson.isReachable(target.uri, timeout: timeout);
        final elapsed = DateTime.now().difference(started).inMilliseconds;
        return target.copyWith(
          health: ok ? ProviderHealth.up : ProviderHealth.down,
          latencyMs: ok ? elapsed : null,
          detail: ok ? null : 'no response within ${timeout.inSeconds}s',
        );
      }),
    );

    _statuses = results;
    _lastProbe = DateTime.now();
    _emit();
    Log.i(
      _tag,
      'probe: ${results.map((r) => '${r.label}=${r.health.name}').join(', ')}',
    );
    return results;
  }

  /// True when at least one network-backed endpoint answered, or when there is
  /// nothing to check (i.e. the build has no external services configured).
  static Future<bool> hasAnyUsableProvider() async {
    final results = await probe();
    if (results.isEmpty) return true; // nothing to check ≠ everything down
    final up = results.where((r) => r.health == ProviderHealth.up).length;
    return up > 0;
  }

  /// Count of providers the remote config actually resolved to. Zero means
  /// the config fetch failed, which is a different failure from "all hosts
  /// are down" and deserves different copy in the UI.
  static int get configuredProviderCount =>
      RemoteConfigService.activeProviders.length;

  static void _update(Uri uri, ProviderHealth health, {String? detail}) {
    _statuses = _statuses
        .map(
          (s) => s.uri == uri ? s.copyWith(health: health, detail: detail) : s,
        )
        .toList(growable: false);
    _emit();
  }

  static void _emit() {
    if (!_statusController.isClosed) _statusController.add(_statuses);
  }

  static void dispose() => _statusController.close();
}
