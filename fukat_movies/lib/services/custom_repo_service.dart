/// User-supplied provider repo (paste a URL or scan a QR code).
///
/// Hardened: the URL must be HTTPS, the document must validate against the
/// provider schema before it is *saved* (not just before it is used), and the
/// user is shown exactly which hosts they are about to trust.
library;

import 'package:hive_flutter/hive_flutter.dart';

import '../core/errors.dart';
import '../core/http_json.dart';
import '../core/log.dart';
import 'remote_config_service.dart';

class RepoValidation {
  final bool ok;
  final int providerCount;
  final List<String> hosts;
  final String message;

  const RepoValidation({
    required this.ok,
    this.providerCount = 0,
    this.hosts = const [],
    required this.message,
  });
}

class CustomRepoService {
  CustomRepoService._();

  static const String _tag = 'CustomRepo';
  static const String _boxName = 'customRepoBox';
  static const String _keyUrl = 'custom_repo_url';

  static Future<Box> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
  }

  /// Fetches and validates without saving, so the UI can show a confirmation
  /// dialog ("this repo adds N providers on these hosts — continue?").
  static Future<RepoValidation> check(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.isAbsolute) {
      return const RepoValidation(
        ok: false,
        message: 'That is not a valid URL.',
      );
    }
    if (uri.scheme != 'https') {
      return const RepoValidation(
        ok: false,
        message: 'Only https:// repository URLs are accepted.',
      );
    }

    try {
      final data = await HttpJson.getJson(
        uri,
        timeout: const Duration(seconds: 12),
        context: 'custom repo',
      );
      final config = RemoteConfigService.validate(data, source: 'custom repo');

      if (config.providers.isEmpty) {
        return RepoValidation(
          ok: false,
          message: config.rejected.isEmpty
              ? 'That file contains no providers.'
              : 'No valid providers. Rejected:\n${config.rejected.take(3).join('\n')}',
        );
      }

      final hosts = <String>{};
      for (final p in config.providers) {
        for (final key in const ['movie_url', 'tv_url']) {
          final host = Uri.tryParse('${p[key] ?? ''}')?.host;
          if (host != null && host.isNotEmpty) hosts.add(host);
        }
      }

      return RepoValidation(
        ok: true,
        providerCount: config.providers.length,
        hosts: hosts.toList()..sort(),
        message:
            '${config.providers.length} provider(s)'
            '${config.rejected.isEmpty ? '' : ', ${config.rejected.length} rejected'}',
      );
    } on AppError catch (e) {
      return RepoValidation(ok: false, message: e.userMessage);
    } catch (e) {
      Log.w(_tag, 'check failed', e);
      return const RepoValidation(
        ok: false,
        message: 'Could not read that repo.',
      );
    }
  }

  static Future<bool> saveRepoUrl(String url) async {
    final validation = await check(url);
    if (!validation.ok) return false;
    final box = await _getBox();
    await box.put(_keyUrl, url.trim());
    return true;
  }

  static Future<String?> getRepoUrl() async {
    final box = await _getBox();
    return box.get(_keyUrl) as String?;
  }

  static Future<void> clearRepo() async {
    final box = await _getBox();
    await box.delete(_keyUrl);
  }

  /// Fetches and validates the saved repo. Returns null when unset or invalid.
  static Future<List<dynamic>?> fetchCustomProviders() async {
    final url = await getRepoUrl();
    if (url == null || url.isEmpty) return null;

    try {
      final data = await HttpJson.getJson(
        Uri.parse(url),
        timeout: const Duration(seconds: 12),
        context: 'custom repo',
      );
      final config = RemoteConfigService.validate(data, source: 'custom repo');
      return config.providers.isEmpty ? null : config.providers;
    } on AppError catch (e) {
      Log.w(_tag, 'fetch failed', e);
      return null;
    }
  }
}
