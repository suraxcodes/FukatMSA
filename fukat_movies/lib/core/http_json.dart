/// A single shared HTTP layer for every outbound call.
///
/// Why this exists:
///  * The app previously created a fresh `http.get(...)` per call, so no
///    connection was ever reused and no call was ever cached. `getImdbId()`
///    alone was being refetched per provider per episode switch.
///  * Every service re-implemented its own timeout/retry/error mapping and
///    every one of them swallowed failures into `null`.
///
/// [HttpJson] gives you: shared client, timeout, bounded retry with backoff on
/// transient failures only, typed [AppError]s, and an optional TTL cache.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'log.dart';

class _CacheEntry<T> {
  final T value;
  final DateTime expiresAt;
  _CacheEntry(this.value, this.expiresAt);
  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

class HttpJson {
  HttpJson._();

  static const _tag = 'Http';

  /// One client for the process: enables keep-alive / connection pooling.
  static final http.Client _client = http.Client();

  /// In-memory TTL cache. Keyed by full URL (+ auth variant).
  /// Deliberately not persisted: a stale stream URL is worse than a refetch.
  static final Map<String, _CacheEntry<dynamic>> _cache = {};
  static const int _maxCacheEntries = 300;

  static const Duration _defaultTimeout = Duration(seconds: 15);
  static const int _maxAttempts = 3;

  /// GET + decode JSON, with retry and typed errors.
  ///
  /// [cacheFor] enables caching for that duration. Pass null (default) to skip.
  /// [retryOn404] is false by default because a 404 is a real answer.
  static Future<dynamic> getJson(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = _defaultTimeout,
    Duration? cacheFor,
    bool retryOn404 = false,
    String? context,
  }) async {
    final cacheKey = cacheFor == null
        ? null
        : '$uri|${headers?['Authorization'] ?? ''}';

    if (cacheKey != null) {
      final hit = _cache[cacheKey];
      if (hit != null && hit.isFresh) {
        Log.d(_tag, 'cache HIT $uri');
        return hit.value;
      }
    }

    final decoded = await _request(
      uri,
      headers: headers,
      timeout: timeout,
      retryOn404: retryOn404,
      context: context,
    );

    if (cacheKey != null) {
      _putCache(cacheKey, decoded, cacheFor);
    }
    return decoded;
  }

  /// POST + decode JSON. Used by AniList GraphQL.
  static Future<dynamic> postJson(
    Uri uri, {
    required Object body,
    Map<String, String>? headers,
    Duration timeout = _defaultTimeout,
    String? context,
  }) {
    return _request(
      uri,
      method: 'POST',
      body: body,
      headers: headers,
      timeout: timeout,
      retryOn404: false,
      context: context,
    );
  }

  static Future<dynamic> _request(
    Uri uri, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
    required Duration timeout,
    required bool retryOn404,
    String? context,
  }) async {
    final mergedHeaders = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      ...?headers,
    };
    final payload = body == null ? null : jsonEncode(body);

    AppError? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final request = http.Request(method, uri)
          ..headers.addAll(mergedHeaders);
        if (payload != null) request.body = payload;

        final streamed = await _client.send(request).timeout(timeout);
        final response = await http.Response.fromStream(streamed);

        final kind = AppError.kindForStatus(response.statusCode);
        if (kind == null) {
          if (response.body.isEmpty) return null;
          try {
            return jsonDecode(response.body);
          } on FormatException catch (e) {
            throw AppError(
              AppErrorKind.parse,
              '${context ?? ''} malformed JSON from $uri',
              cause: e,
            );
          }
        }

        final error = AppError(
          kind,
          '${context ?? ''} HTTP ${response.statusCode} from $uri',
        );

        // Only retry things that can plausibly succeed on a second try.
        final isRetryable =
            kind == AppErrorKind.serverError ||
            kind == AppErrorKind.rateLimited ||
            (kind == AppErrorKind.notFound && retryOn404);
        if (!isRetryable) throw error;
        lastError = error;
      } on AppError {
        rethrow;
      } catch (raw) {
        final mapped = raw is AppError
            ? raw
            : AppError.from(raw, context: context);
        // offline/timeout are worth retrying; parse errors are not.
        final isRetryable =
            mapped.kind == AppErrorKind.offline ||
            mapped.kind == AppErrorKind.timeout;
        if (!isRetryable) throw mapped;
        lastError = mapped;
      }

      if (attempt < _maxAttempts) {
        // Exponential backoff: 400ms, 1200ms.
        final delay = Duration(
          milliseconds: 400 * (attempt * attempt + attempt),
        );
        Log.w(
          _tag,
          'retry $attempt/$_maxAttempts in ${delay.inMilliseconds}ms — $uri',
        );
        await Future<void>.delayed(delay);
      }
    }

    throw lastError ??
        AppError(AppErrorKind.unknown, '${context ?? ''} request failed: $uri');
  }

  static void _putCache(String key, dynamic value, Duration? ttl) {
    if (ttl == null) return;
    if (_cache.length >= _maxCacheEntries) {
      // Cheap eviction: drop everything expired, then the oldest third.
      _cache.removeWhere((_, entry) => !entry.isFresh);
      if (_cache.length >= _maxCacheEntries) {
        final keys = _cache.keys.take(_maxCacheEntries ~/ 3).toList();
        for (final k in keys) {
          _cache.remove(k);
        }
      }
    }
    _cache[key] = _CacheEntry<dynamic>(value, DateTime.now().add(ttl));
  }

  /// True if a host answers at all within [timeout]. Used by the
  /// provider health check; never throws.
  static Future<bool> isReachable(
    Uri uri, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final request = http.Request('GET', uri);
      final streamed = await _client.send(request).timeout(timeout);
      // Drain so the socket can be reused.
      await streamed.stream.drain<void>();
      return streamed.statusCode < 500;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (e) {
      Log.d(_tag, 'reachability check failed for $uri: $e');
      return false;
    }
  }

  /// Warm a sleeping free-tier backend (Render/Fly spin-down) without
  /// caring about the result.
  static void warmUp(Uri uri) {
    unawaited(
      isReachable(uri, timeout: const Duration(seconds: 30)).then((ok) {
        Log.d(_tag, 'warm-up ${ok ? "ok" : "failed"}: $uri');
      }),
    );
  }

  static void clearCache() => _cache.clear();
}
