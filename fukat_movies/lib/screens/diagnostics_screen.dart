import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../services/provider_health_service.dart';
import '../services/remote_config_service.dart';

/// One screen that answers "why isn't anything playing?".
///
/// Before this existed, a suspended backend produced a spinner, then a black
/// player, then nothing. Now the user (and you, when debugging) can see which
/// endpoints answered, which config source won, and which providers were
/// dropped by validation.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => DiagnosticsScreenState();
}

class DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<EndpointStatus> _statuses = const [];
  bool _probing = false;
  DateTime? _lastProbe;

  @override
  void initState() {
    super.initState();
    _statuses = ProviderHealthService.statuses;
    _probe();
  }

  Future<void> _probe() async {
    setState(() => _probing = true);
    final results = await ProviderHealthService.probe();
    if (!mounted) return;
    setState(() {
      _statuses = results;
      _lastProbe = DateTime.now();
      _probing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final providers = RemoteConfigService.activeProviders;
    final rejected = RemoteConfigService.rejectedProviders;

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        title: const Text('Diagnostics'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            tooltip: 'Re-run checks',
            onPressed: _probing ? null : _probe,
            icon: _probing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heading('Services'),
          if (_statuses.isEmpty)
            const _Hint(
              'No external services configured — this build runs fully locally.',
            ),
          ..._statuses.map(_endpointTile),
          if (_lastProbe != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                'Checked at ${_lastProbe!.toLocal().toString().split('.').first}',
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ),

          _heading('Provider configuration'),
          _kv('source', RemoteConfigService.source),
          _kv('valid providers', '${providers.length}'),
          _kv('rejected', '${rejected.length}'),

          if (rejected.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dropped by validation',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...rejected.map(
                    (r) => Text(
                      '• $r',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          ...providers.map((p) {
            final name = p['name'] ?? p['engine'] ?? 'unnamed';
            final engine = p['engine'] ?? 'webview';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.check_circle_outline,
                color: Colors.greenAccent,
                size: 18,
              ),
              title: Text(
                '$name',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: Text(
                '$engine${p['anime_only'] == true ? ' · anime only' : ''}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            );
          }),

          _heading('Build configuration'),
          ...AppConfig.diagnostics.entries.map((e) => _kv(e.key, e.value)),

          const SizedBox(height: 24),
          const Text(
            'If every service shows DOWN, the backend hosts are suspended or '
            'asleep. Self-hosted free tiers often need a 20–30 second wake-up; '
            'the app pings them at launch, so waiting ~30s and retrying '
            'usually works.',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _endpointTile(EndpointStatus status) {
    final (color, icon, label) = switch (status.health) {
      ProviderHealth.up => (Colors.greenAccent, Icons.check_circle, 'UP'),
      ProviderHealth.down => (Colors.redAccent, Icons.error_outline, 'DOWN'),
      ProviderHealth.warming => (
        Colors.amber,
        Icons.hourglass_bottom,
        'WAKING',
      ),
      ProviderHealth.unknown => (Colors.white38, Icons.help_outline, 'UNKNOWN'),
    };

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 18),
      title: Text(
        status.label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      subtitle: Text(
        <String>[
          status.uri.host,
          if (status.latencyMs != null) '${status.latencyMs}ms',
          ?status.detail,
        ].join(' · '),
        style: const TextStyle(color: Colors.white38, fontSize: 11),
        maxLines: 2,
      ),
      trailing: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.redAccent,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _kv(String key, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            key,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white54, fontSize: 12),
    ),
  );
}
