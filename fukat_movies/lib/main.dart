import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_config.dart';
import 'core/log.dart';
import 'screens/home_screen.dart';
import 'services/continue_watching_service.dart';
import 'services/provider_health_service.dart';
import 'services/remote_config_service.dart';
import 'services/supabase_auth_service.dart';

/// Startup order matters, and failure is now *typed* rather than a single
/// boolean that blanked the whole app.
///
/// Previously, a missing Supabase key in `assets/.env` threw, which set
/// `initializationSuccess = false`, which showed "Fatal Initialization Error"
/// — so a fresh clone, or anyone who just wanted TMDB, could not run the app
/// at all. Now:
///   * Supabase is optional → local-only mode.
///   * The .env file is optional → `--dart-define` and defaults take over.
///   * Hive failures are per-box and reported, not fatal.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(960, 600),
      center: true,
      title: 'Fukat MSA',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  MediaKit.ensureInitialized();

  final startupErrors = <String>[];

  // 1. Config (never throws).
  await AppConfig.load();

  // 2. Auth — optional.
  await SupabaseAuthService.initialize();

  // 3. Local storage — one bad box must not kill the app.
  try {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox('watchlistBox'),
      Hive.openBox('continueWatchingBox'),
      Hive.openBox('customRepoBox'),
    ]);
    Log.i('Startup', 'local storage ready');
  } catch (e) {
    Log.e('Startup', 'local storage failed', e);
    // Degrade, do not die: watchlist/progress become no-ops for this session.
    ContinueWatchingService.markHiveUnavailable();
  }

  // 4. Provider list.
  try {
    await RemoteConfigService.initializeConfig();
  } catch (e) {
    Log.w('Startup', 'provider config failed', e);
    startupErrors.add('Provider config could not be loaded.');
  }

  // 5. Warm up sleeping backends in the background; do not await.
  ProviderHealthService.warmUpInBackground();

  // Diagnose the one truly blocking case: nothing to show and nothing to play.
  final blocking = <String>[
    if (!AppConfig.hasTmdbCredentials)
      'TMDB credentials are missing, so no catalogue can load. Add TMDB_API_TOKEN.',
    ...startupErrors,
  ];

  runApp(FukatApp(startupIssues: blocking));
}

class FukatApp extends StatelessWidget {
  /// Empty means everything that must work, works.
  final List<String> startupIssues;

  const FukatApp({super.key, this.startupIssues = const []});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fukat MSA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ).copyWith(surface: const Color(0xFF141414)),
        scaffoldBackgroundColor: const Color(0xFF141414),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
        ),
        focusColor: Colors.white30,
        highlightColor: Colors.redAccent.withValues(alpha: 0.2),
      ),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),
      home: startupIssues.isEmpty
          ? const HomeScreen()
          : StartupErrorScreen(issues: startupIssues),
    );
  }
}

/// Shown only when the app genuinely cannot function — and it says exactly
/// what is missing instead of "Fatal Initialization Error".
class StartupErrorScreen extends StatelessWidget {
  final List<String> issues;

  const StartupErrorScreen({super.key, required this.issues});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.settings_suggest,
                  color: Colors.redAccent,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'This build is not configured',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...issues.map(
                  (issue) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '• $issue',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How to fix',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. Copy assets/.env.example to assets/.env and fill it in,\n'
                        '   or pass values with --dart-define.\n\n'
                        '2. Copy assets/remote_config.example.json to\n'
                        '   assets/remote_config.json to get a provider list.\n\n'
                        '3. Rebuild. See README.md for the full matrix.',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  AppConfig.diagnostics.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join('\n'),
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
