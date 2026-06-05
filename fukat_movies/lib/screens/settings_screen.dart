import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/custom_repo_service.dart';
import '../services/supabase_auth_service.dart';
import '../monetization/screens/premium_screen.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repoController = TextEditingController();
  String? _savedRepoUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRepoUrl();
  }

  Future<void> _loadRepoUrl() async {
    final url = await CustomRepoService.getRepoUrl();
    setState(() {
      _savedRepoUrl = url;
      if (url != null) _repoController.text = url;
    });
  }

  Future<void> _saveRepo() async {
    final url = _repoController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isLoading = true);
    final success = await CustomRepoService.saveRepoUrl(url);
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Custom repository saved!' : 'Failed to save repository.'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      if (success) _loadRepoUrl();
    }
  }

  Future<void> _clearRepo() async {
    await CustomRepoService.clearRepo();
    setState(() {
      _savedRepoUrl = null;
      _repoController.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom repository cleared.')),
      );
    }
  }

  Future<void> _signOut() async {
    await SupabaseAuthService.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Scan QR Code'), backgroundColor: Colors.black),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  Navigator.pop(context);
                  _repoController.text = barcode.rawValue!;
                  return;
                }
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseAuthService.currentUser;
    final userEmail = user?.email ?? 'Guest';

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Account',
            style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Logged in as', style: TextStyle(color: Colors.white70)),
            subtitle: Text(userEmail, style: const TextStyle(color: Colors.white, fontSize: 16)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!SupabaseAuthService.isPremium && user != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const PremiumScreen()));
                    },
                    icon: const Icon(Icons.workspace_premium, color: Colors.amber),
                    label: const Text('Get Premium', style: TextStyle(color: Colors.amber)),
                  )
                else if (user != null)
                  const Padding(
                    padding: EdgeInsets.only(right: 16.0),
                    child: Row(
                      children: [
                        Icon(Icons.workspace_premium, color: Colors.amber),
                        SizedBox(width: 4),
                        Text('Premium', style: TextStyle(color: Colors.amber)),
                      ],
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: _signOut,
                  tooltip: 'Sign Out',
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 32),
          Text(
            'Custom Repository',
            style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _repoController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Repository URL',
              labelStyle: const TextStyle(color: Colors.white70),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                onPressed: _openScanner,
                tooltip: 'Scan QR Code',
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveRepo,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    child: const Text('Save'),
                  ),
                ),
                if (_savedRepoUrl != null) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearRepo,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
