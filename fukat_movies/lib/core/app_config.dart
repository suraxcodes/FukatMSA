/// One place that answers "what is this build configured with?".
///
/// Resolution order for every value (first non-empty wins):
///   1. `--dart-define=KEY=value`      ← recommended for CI / release builds
///   2. `assets/.env`                   ← local dev convenience (git-ignored)
///   3. the hard-coded default below
///
/// Nothing here is secret in the security sense: anything shipped inside an
/// APK can be extracted. The Supabase anon key is *designed* to be public —
/// what protects your data is Row Level Security, not hiding the key.
/// Treat this file as configuration, not as a vault.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();

  /// Populated by [load]. True when a usable `.env` asset was found.
  static bool envFileLoaded = false;

  static const String envAssetPath = 'assets/.env';

  /// Loads `assets/.env` if present. Never throws: a missing file just means
  /// the app falls back to `--dart-define` values + defaults, which keeps a
  /// fresh clone runnable instead of showing "Fatal Initialization Error".
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: envAssetPath, isOptional: true);
      envFileLoaded = dotenv.env.isNotEmpty;
    } catch (e) {
      envFileLoaded = false;
      debugPrint(
        'AppConfig: .env not loaded ($e) — using dart-define/defaults',
      );
    }
  }

  static String _read(String key, {String fallback = ''}) {
    // 1. Compile-time define.
    final fromDefine = switch (key) {
      'TMDB_API_TOKEN' => const String.fromEnvironment('TMDB_API_TOKEN'),
      'TMDB_API_KEY' => const String.fromEnvironment('TMDB_API_KEY'),
      'TMDB_BASE_URL' => const String.fromEnvironment('TMDB_BASE_URL'),
      'SUPABASE_URL' => const String.fromEnvironment('SUPABASE_URL'),
      'SUPABASE_ANON_KEY' => const String.fromEnvironment('SUPABASE_ANON_KEY'),
      'REMOTE_CONFIG_URL' => const String.fromEnvironment('REMOTE_CONFIG_URL'),
      'ADBLOCK_CONFIG_URL' => const String.fromEnvironment(
        'ADBLOCK_CONFIG_URL',
      ),
      'PROXIFY_STREAMS_URL' => const String.fromEnvironment(
        'PROXIFY_STREAMS_URL',
      ),
      'STREMIO_ADDON_URL' => const String.fromEnvironment('STREMIO_ADDON_URL'),
      'MEDIAFUSION_URL' => const String.fromEnvironment('MEDIAFUSION_URL'),
      'PROXIFY_SHARED_SECRET' => const String.fromEnvironment(
        'PROXIFY_SHARED_SECRET',
      ),
      _ => '',
    };
    if (fromDefine.isNotEmpty) return fromDefine;

    // 2. assets/.env
    try {
      final fromEnv = dotenv.env[key];
      if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();
    } catch (_) {
      // dotenv not loaded yet — fall through.
    }

    // 3. default
    return fallback;
  }

  // ---------------------------------------------------------------- TMDB
  static String get tmdbBaseUrl =>
      _read('TMDB_BASE_URL', fallback: 'https://api.themoviedb.org/3');

  /// v4 read access token (preferred). Sent as `Authorization: Bearer`.
  static String get tmdbReadToken => _read('TMDB_API_TOKEN');

  /// v3 key, only used when no v4 token exists.
  static String get tmdbApiKey => _read('TMDB_API_KEY');

  static bool get hasTmdbCredentials =>
      tmdbReadToken.isNotEmpty || tmdbApiKey.isNotEmpty;

  // ------------------------------------------------------------ Supabase
  static String get supabaseUrl => _read('SUPABASE_URL');
  static String get supabaseAnonKey => _read('SUPABASE_ANON_KEY');
  static bool get hasSupabaseCredentials =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // ------------------------------------------------------ provider config
  static String get remoteConfigUrl => _read('REMOTE_CONFIG_URL');

  static String get adBlockConfigUrl => _read('ADBLOCK_CONFIG_URL');

  /// Optional. Only needed if you keep a self-hosted HLS proxy.
  static String get proxifyStreamsUrl => _read('PROXIFY_STREAMS_URL');

  /// Optional Stremio addon for the `native_stremio` engine.
  ///
  /// Deliberately empty by default. Live testing (26 Nov 2026) showed:
  ///   * mediafusion.elfhosted.com answers 200 but returns `{"streams":[]}`
  ///     for every id, so it only burns a resolver slot;
  ///   * public torrentio returns `infoHash` only — unplayable by media_kit —
  ///     unless a debrid key is configured.
  /// Configure your own, e.g.
  ///   STREMIO_ADDON_URL=https://torrentio.strem.fun/realdebrid=YOUR_KEY
  static String get stremioAddonUrl =>
      _read('STREMIO_ADDON_URL', fallback: _read('MEDIAFUSION_URL'));

  /// Sent as `X-Api-Key` to a self-hosted proxy so randoms can't burn your
  /// Render quota. Empty = no header sent.
  static String get proxifySharedSecret => _read('PROXIFY_SHARED_SECRET');

  /// Every endpoint we may want to warm up at launch.
  /// Sleeping free-tier hosts are the #1 cause of "no streams found".
  static List<Uri> get warmUpTargets => [
    if (remoteConfigUrl.isNotEmpty) Uri.tryParse(remoteConfigUrl),
    if (proxifyStreamsUrl.isNotEmpty) Uri.tryParse(proxifyStreamsUrl),
    if (stremioAddonUrl.isNotEmpty) Uri.tryParse(stremioAddonUrl),
  ].whereType<Uri>().toList(growable: false);

  /// Human-readable summary for the diagnostics screen. Never logs the
  /// Supabase anon key or TMDB token in full.
  static Map<String, String> get diagnostics => {
    'env file loaded': envFileLoaded ? 'yes' : 'no',
    'TMDB': hasTmdbCredentials ? 'configured' : 'MISSING',
    'Supabase': hasSupabaseCredentials ? 'configured' : 'MISSING',
    'remote config url': remoteConfigUrl.isEmpty
        ? 'bundled asset'
        : remoteConfigUrl,
    'HLS proxy': proxifyStreamsUrl.isEmpty ? 'disabled' : proxifyStreamsUrl,
    'Stremio addon': stremioAddonUrl.isEmpty ? 'disabled' : stremioAddonUrl,
    'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
  };
}
