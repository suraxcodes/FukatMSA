import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_config.dart';
import '../services/custom_repo_service.dart';
import '../services/provider_reputation.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_auth_service.dart';
import '../widgets/focusable_button.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  final _repoController = TextEditingController();
  String? _savedRepoUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadRepoUrl();
  }

  @override
  void dispose() {
    _repoController.dispose();
    super.dispose();
  }

  Future<void> _loadRepoUrl() async {
    final url = await CustomRepoService.getRepoUrl();
    if (!mounted) return;
    setState(() {
      _savedRepoUrl = url;
      if (url != null) _repoController.text = url;
    });
  }

  /// Validates first, then asks the user to confirm exactly which hosts they
  /// are about to trust. A repo URL is executable-ish content: it decides which
  /// pages get rendered inside the app.
  Future<void> _saveRepo() async {
    final url = _repoController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isSaving = true);
    final validation = await CustomRepoService.check(url);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (!validation.ok) {
      _toast(validation.message, error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B1B),
        title: const Text(
          'Trust this repository?',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                validation.message,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              const Text(
                'These hosts will be embedded in the player:',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 6),
              ...validation.hosts.map(
                (h) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• $h',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Trust & save',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await CustomRepoService.saveRepoUrl(url);
    await RemoteConfigService.initializeConfig();
    if (!mounted) return;
    _toast(
      success
          ? 'Repository saved. Providers reloaded.'
          : 'Could not save repository.',
      error: !success,
    );
    if (success) _loadRepoUrl();
  }

  Future<void> _clearRepo() async {
    await CustomRepoService.clearRepo();
    await RemoteConfigService.initializeConfig();
    if (!mounted) return;
    setState(() {
      _savedRepoUrl = null;
      _repoController.clear();
    });
    _toast('Custom repository cleared. Using defaults.');
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Scan repo QR'),
            backgroundColor: Colors.black,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.startsWith('https://')) {
                  Navigator.pop(context);
                  _repoController.text = value;
                  _saveRepo();
                  return;
                }
              }
            },
          ),
        ),
      ),
    );
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade800 : Colors.green.shade800,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseAuthService.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _section('Account'),
          if (!SupabaseAuthService.isAvailable)
            const ListTile(
              leading: Icon(Icons.cloud_off, color: Colors.orange),
              title: Text(
                'Local-only mode',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'This build has no Supabase credentials, so watchlist and '
                'progress stay on this device.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            )
          else
            ListTile(
              leading: Icon(
                user != null ? Icons.person : Icons.person_outline,
                color: user != null ? Colors.greenAccent : Colors.white54,
              ),
              title: Text(
                user?.email ?? 'Not signed in',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              subtitle: Text(
                user != null
                    ? 'Watchlist and progress sync across devices.'
                    : 'Sign in from the home screen.',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: user != null
                  ? FocusableButton(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.logout, color: Colors.white),
                      onTap: () async {
                        await SupabaseAuthService.signOut();
                        if (mounted) setState(() {});
                      },
                    )
                  : null,
            ),

          _section('Providers'),
          ListTile(
            leading: const Icon(Icons.dns_outlined, color: Colors.white70),
            title: const Text(
              'Active providers',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              '${RemoteConfigService.activeProviders.length} loaded '
              'from ${RemoteConfigService.source}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
          if (RemoteConfigService.rejectedProviders.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.warning_amber, color: Colors.orange),
              title: Text(
                '${RemoteConfigService.rejectedProviders.length} provider(s) rejected',
                style: const TextStyle(color: Colors.orange),
              ),
              subtitle: Text(
                RemoteConfigService.rejectedProviders.first,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _showRejections(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _repoController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Custom provider repository',
                labelStyle: const TextStyle(color: Colors.white54),
                hintText: 'https://example.com/providers.json',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                helperText: _savedRepoUrl == null
                    ? 'Optional. HTTPS only.'
                    : 'Saved: $_savedRepoUrl',
                helperStyle: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                ),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    onPressed: _isSaving ? null : _saveRepo,
                    child: _isSaving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Validate & save'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _openScanner,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan'),
                ),
                if (_savedRepoUrl != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _clearRepo,
                    tooltip: 'Clear repository',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ],
            ),
          ),

          _section('Playback'),
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: Colors.greenAccent),
            title: const Text(
              'Automatic server selection',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Sources are verified in parallel and the first one that actually '
              'plays is opened. Servers that failed before are skipped.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt, color: Colors.white70),
            title: const Text(
              'Reset learned server rankings',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Forget which servers worked for you and start fresh.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: () async {
              await ProviderReputation.reset();
              if (!mounted) return;
              _toast('Server rankings cleared.');
            },
          ),

          _section('Diagnostics'),
          ListTile(
            leading: const Icon(
              Icons.health_and_safety_outlined,
              color: Colors.white70,
            ),
            title: const Text(
              'Service health',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Check which backends are up, see why a stream failed.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_ethernet, color: Colors.white70),
            title: const Text(
              'Build configuration',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              AppConfig.diagnostics.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join('\n'),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            isThreeLine: true,
          ),

          _section('About'),
          const ListTile(
            leading: Icon(Icons.info_outline, color: Colors.white38),
            title: Text('Fukat MSA', style: TextStyle(color: Colors.white70)),
            subtitle: Text(
              'Metadata by TMDB. This product uses the TMDB API but is not '
              'endorsed or certified by TMDB. Manga data by AniList and '
              'MangaDex. Fukat MSA hosts no media.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Colors.redAccent,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
  );

  void _showRejections() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B1B),
        title: const Text(
          'Rejected providers',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Text(
            RemoteConfigService.rejectedProviders.join('\n\n'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
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
