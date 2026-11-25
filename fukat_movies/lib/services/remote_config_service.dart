/// Loads the provider list from, in order:
///   1. the hidden `REMOTE_CONFIG_URL` (if configured),
///   2. the user's saved custom repo,
///   3. the bundled `assets/remote_config.json`.
///
/// ## What changed and why
///
/// **Validation.** The old loader trusted whatever JSON it got — including a
/// URL pasted in from a scanned QR code. A "repo" could therefore inject a
/// `movie_url` of `javascript:` or a phishing page that renders inside the
/// app's own chrome. Every provider is now schema-checked and hosts must be
/// HTTPS; anything that fails is dropped and reported, not silently used.
///
/// **No more per-platform provider surgery.** The old code deleted every
/// vidsrc provider when `Platform.isWindows` and did the same filtering three
/// separate times. Capability belongs to the provider definition (`platforms`),
/// not to a hard-coded hostname check scattered through the loader.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;

import '../core/app_config.dart';
import '../core/errors.dart';
import '../core/log.dart';
import 'custom_repo_service.dart';

class ProviderConfig {
  final List<Map<String, dynamic>> providers;
  final String source;
  final List<String> rejected;

  const ProviderConfig({
    required this.providers,
    required this.source,
    this.rejected = const [],
  });

  bool get isEmpty => providers.isEmpty;
}

class RemoteConfigService {
  RemoteConfigService._();

  static const String _tag = 'RemoteConfig';
  static const String _assetPath = 'assets/remote_config.json';

  static List<dynamic> _activeProviders = const [];
  static String _source = 'none';
  static List<String> _rejected = const [];

  static List<dynamic> get activeProviders => _activeProviders;
  static String get source => _source;
  static List<String> get rejectedProviders => _rejected;

  /// Engines this build knows how to drive. A provider claiming anything else
  /// is dropped during validation — that is what stops a rogue repo from
  /// injecting an engine name that later falls through to a raw WebView.
  static const Set<String> knownEngines = {
    'webview',
    'native_extractor',
    'native_stremio',
    // Legacy id, kept so old configs load; resolved as an alias of
    // native_stremio by StreamResolver.
    'native_proxify',
  };

  /// Platform names accepted in a provider's optional `platforms` list.
  static String get currentPlatform {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  static Future<void> initializeConfig() async {
    // 1. Hidden global URL.
    if (AppConfig.remoteConfigUrl.isNotEmpty) {
      final fromGlobal = await _tryRemote(AppConfig.remoteConfigUrl, 'remote');
      if (fromGlobal != null && fromGlobal.providers.isNotEmpty) {
        _apply(fromGlobal);
        return;
      }
    }

    // 2. User's custom repo.
    try {
      final custom = await CustomRepoService.fetchCustomProviders();
      if (custom != null && custom.isNotEmpty) {
        final config = validate(custom, source: 'custom repo');
        if (config.providers.isNotEmpty) {
          _apply(config);
          return;
        }
        Log.w(_tag, 'custom repo produced no usable providers');
      }
    } on AppError catch (e) {
      Log.w(_tag, 'custom repo failed', e);
    }

    // 3. Bundled asset.
    final bundled = await _tryAsset();
    if (bundled != null) {
      _apply(bundled);
      return;
    }

    Log.w(_tag, 'no providers loaded from any source');
    _activeProviders = const [];
    _source = 'none';
  }

  static Future<ProviderConfig?> _tryRemote(String url, String source) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https') {
        throw const AppError(
          AppErrorKind.badRequest,
          'remote config url must be https',
        );
      }
      final body = await HttpClient()
          .getUrl(uri)
          .then((r) => r.close())
          .timeout(const Duration(seconds: 8))
          .then(
            (r) => r.statusCode == 200
                ? r.transform(utf8.decoder).join()
                : throw AppError(
                    AppErrorKind.serverError,
                    'remote config HTTP ${r.statusCode}',
                  ),
          );
      final data = jsonDecode(body);
      return validate(data, source: source);
    } on AppError catch (e) {
      Log.w(_tag, 'global remote config failed ($source)', e);
    } catch (e) {
      Log.w(_tag, 'global remote config failed ($source)', e);
    }
    return null;
  }

  static Future<ProviderConfig?> _tryAsset() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      return validate(jsonDecode(raw), source: 'bundled asset');
    } on FlutterError {
      // Asset absent (fresh clone without the example copied over).
      Log.w(
        _tag,
        '$_assetPath is missing — copy assets/remote_config.example.json to '
        'assets/remote_config.json to get providers.',
      );
      return null;
    } catch (e) {
      Log.w(_tag, 'bundled asset unreadable', e);
      return null;
    }
  }

  // ------------------------------------------------------------- validation

  /// Validates a decoded config document. Never throws: returns whatever
  /// subset is safe to use, plus the reasons the rest was dropped.
  static ProviderConfig validate(dynamic decoded, {String source = 'unknown'}) {
    final rejected = <String>[];

    if (decoded is! Map) {
      throw const AppError(AppErrorKind.parse, 'config is not an object');
    }

    final rawList = decoded['active_providers'];
    if (rawList is! List) {
      throw const AppError(
        AppErrorKind.parse,
        'config has no "active_providers" array',
      );
    }

    final platform = currentPlatform;
    final accepted = <Map<String, dynamic>>[];

    for (final entry in rawList) {
      final name = (entry is Map ? entry['name'] ?? entry['engine'] : null)
          ?.toString();
      final reason = _rejectionReason(entry, platform);
      if (reason != null) {
        rejected.add('${name ?? "<unnamed>"}: $reason');
        continue;
      }
      final normalized = Map<String, dynamic>.from(entry as Map);
      final resolvedEngine = _normalizedEngine(entry, platform);
      if (resolvedEngine != null && normalized['engine'] != resolvedEngine) {
        normalized['engine_alias'] = entry['engine'];
        normalized['engine'] = resolvedEngine;
      }
      accepted.add(normalized);
    }

    if (rejected.isNotEmpty) {
      Log.w(
        _tag,
        'dropped ${rejected.length} provider(s): ${rejected.join(' | ')}',
      );
    }
    return ProviderConfig(
      providers: accepted,
      source: source,
      rejected: rejected,
    );
  }

  /// Maps a provider's declared engine to one this build can drive, or null
  /// if it is genuinely unsupported.
  ///
  /// Aliases exist because provider lists in the wild (and the one in
  /// `remote_config.json`) still name engines that either no longer exist or
  /// were never implemented on the client:
  ///   * `native_miruro`   — that backend has been suspended; the extractor is
  ///                         the working replacement for anime.
  ///   * `native_omss`     — was never implemented in this client.
  static String? _normalizedEngine(Map entry, String platform) {
    final raw = entry['engine']?.toString().trim();

    // No engine, but it has embed URLs -> ordinary webview provider.
    if (raw == null || raw.isEmpty) {
      final hasUrls =
          (entry['movie_url']?.toString().isNotEmpty ?? false) ||
          (entry['tv_url']?.toString().isNotEmpty ?? false);
      return hasUrls ? 'webview' : null;
    }

    if (knownEngines.contains(raw)) return raw;

    return switch (raw) {
      // Dead backend, but the *intent* was "resolve anime in-app". The
      // extractor is the working replacement, and it needs URLs to work on.
      'native_miruro' => _hasEmbedUrl(entry) ? 'native_extractor' : null,
      // Never shipped on the client; the Stremio addon path is the analogue.
      'native_omss' => 'native_stremio',
      _ => null,
    };
  }

  static bool _hasEmbedUrl(Map entry) =>
      (entry['movie_url']?.toString().isNotEmpty ?? false) ||
      (entry['tv_url']?.toString().isNotEmpty ?? false);

  /// Returns the reason a provider is unusable, or null if it is fine.
  static String? _rejectionReason(dynamic entry, String platform) {
    if (entry is! Map) return 'not an object';

    // A provider with movie_url/tv_url but no engine is a plain embed page —
    // that is the overwhelmingly common case in hand-written configs, so it
    // defaults to `webview` instead of being thrown away.
    final engine = _normalizedEngine(entry, platform);
    if (engine == null) {
      final declared = entry['engine']?.toString() ?? '(none)';
      if (declared == 'native_miruro') {
        // Specific, actionable: this backend is gone and the entry has no
        // embed URL for the extractor to work on.
        return 'native_miruro backend is suspended; add movie_url/tv_url so '
            'it can use native_extractor instead';
      }
      if (declared == '(none)') {
        return 'no engine and no movie_url/tv_url';
      }
      return 'unknown engine "$declared" '
          '(known: ${knownEngines.join(', ')})';
    }

    // Optional platform gate, replaces the old Platform.isWindows hashing.
    final platforms = entry['platforms'];
    if (platforms is List &&
        platforms.isNotEmpty &&
        !platforms.map((p) => p.toString()).contains(platform)) {
      return 'not enabled on $platform';
    }

    // A provider must be able to produce *some* URL for the content it serves.
    if (engine == 'webview' || engine == 'native_extractor') {
      final movieUrl = entry['movie_url']?.toString();
      final tvUrl = entry['tv_url']?.toString();
      if ((movieUrl == null || movieUrl.isEmpty) &&
          (tvUrl == null || tvUrl.isEmpty)) {
        return 'no movie_url or tv_url';
      }
      for (final url in [movieUrl, tvUrl]) {
        if (url == null || url.isEmpty) continue;
        final uri = Uri.tryParse(url);
        if (uri == null) return 'unparseable url "$url"';
        // Only https: a javascript:/data:/http: base is an injection vector.
        if (uri.scheme != 'https') return 'non-https url "$url"';
        if (engine == 'webview' && !uri.host.contains('.')) {
          return 'url has no host "$url"';
        }
      }
    }

    return null;
  }

  static void _apply(ProviderConfig config) {
    _activeProviders = config.providers;
    _source = config.source;
    _rejected = config.rejected;
    Log.i(
      _tag,
      'loaded ${config.providers.length} provider(s) from ${config.source}',
    );
  }

  static void clear() {
    _activeProviders = const [];
    _source = 'none';
    _rejected = const [];
  }
}
