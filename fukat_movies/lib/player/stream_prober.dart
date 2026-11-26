/// Decides whether a resolved stream is *actually* playable, before the player
/// ever opens it.
///
/// ## Why this exists
///
/// The resolver used to treat "provider returned a URL" as success. That is a
/// different thing from "the URL plays": a huge share of resolved links answer
/// 403 (CDN wants a Referer we did not send), 404 (stale id), or hand back an
/// HTML error page with a 200. The player then opened it, `media_kit` failed,
/// and the user had to switch servers by hand until one worked — which is
/// exactly the complaint this fixes.
///
/// The probe is deliberately cheap: a `Range: bytes=0-2047` GET that reads only
/// the first 2 KB. For HLS that is enough to see the `#EXTM3U` header; for
/// progressive MP4 it is enough to see real bytes instead of an error page.
/// It costs one round trip (~100–400 ms) and runs concurrently across
/// candidates.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/log.dart';
import '../services/stream_resolver.dart';

enum ProbeVerdict {
  /// Verified: real media bytes came back.
  playable,

  /// Verified: definitely will not play (403/404/timeout/HTML).
  unplayable,

  /// Cannot be judged without a browser (embed page, blob:, weird scheme).
  unknown,
}

class ProbeResult {
  final ProbeVerdict verdict;
  final String? reason;
  final int latencyMs;

  /// Headers that were used for the winning request, so the player reuses them.
  final Map<String, String> headers;

  const ProbeResult({
    required this.verdict,
    this.reason,
    this.latencyMs = 0,
    this.headers = const {},
  });

  bool get isPlayable => verdict == ProbeVerdict.playable;
  bool get isDead => verdict == ProbeVerdict.unplayable;

  @override
  String toString() =>
      'ProbeResult(${verdict.name}'
      '${reason == null ? '' : ' — $reason'}${latencyMs > 0 ? ', ${latencyMs}ms' : ''})';
}

class StreamProber {
  StreamProber._();

  static const String _tag = 'Probe';

  /// UA used for probing. Must match what the player sends, or a CDN that
  /// allow-lists by UA will pass the probe and fail playback.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Session cache: the same URL resolved by two providers is probed once.
  static final Map<String, ProbeResult> _cache = {};

  static const Duration _defaultTimeout = Duration(seconds: 8);

  /// Probes every candidate concurrently and returns them ranked, best first.
  ///
  /// Ranking: playable (fastest) → unknown → dead. Providers with a known-good
  /// track record get a small latency bonus so ties break toward what has
  /// worked for this user before.
  static Future<List<RankedCandidate>> rank(
    List<StreamInfo> candidates, {
    Map<String, double> latencyBonus = const {},
    Duration timeout = _defaultTimeout,
  }) async {
    if (candidates.isEmpty) return const [];

    final results = await Future.wait(
      candidates.map((candidate) async {
        final probe = await probeStream(candidate, timeout: timeout);
        return RankedCandidate(
          stream: candidate,
          probe: probe,
          score: _score(probe, latencyBonus[candidate.providerName] ?? 0),
        );
      }),
    );

    results.sort((a, b) => b.score.compareTo(a.score));
    Log.i(
      _tag,
      'ranked: ${results.map((r) => '${r.stream.providerName}=${r.probe.verdict.name}').join(', ')}',
    );
    return results;
  }

  static double _score(ProbeResult probe, double bonus) =>
      switch (probe.verdict) {
        ProbeVerdict.playable =>
          1000 + bonus - (probe.latencyMs / 1000).clamp(0, 100),
        ProbeVerdict.unknown => 500 + bonus,
        ProbeVerdict.unplayable => 0,
      };

  static Future<ProbeResult> probeStream(
    StreamInfo stream, {
    Duration timeout = _defaultTimeout,
  }) {
    final cached = _cache['${stream.providerName}|${stream.url}'];
    if (cached != null) return Future.value(cached);

    final future = _probeRaw(stream.url, stream.headers, timeout);
    return future.then((result) {
      _cache['${stream.providerName}|${stream.url}'] = result;
      return result;
    });
  }

  static Future<ProbeResult> _probeRaw(
    String url,
    Map<String, String>? providedHeaders,
    Duration timeout,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      // blob:, data:, javascript: — nothing to probe, the browser decides.
      return const ProbeResult(
        verdict: ProbeVerdict.unknown,
        reason: 'not an HTTP url',
      );
    }

    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept': '*/*',
      'Range': 'bytes=0-2047',
      ...?providedHeaders,
    };

    final started = DateTime.now();
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = null; // we set UA explicitly above

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);

      final code = response.statusCode;
      final elapsed = DateTime.now().difference(started).inMilliseconds;

      // Read at most 2 KB, then bail out — we never stream the whole file.
      final buffer = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        buffer.addAll(chunk);
        if (buffer.length >= 2048) break;
      }

      if (code == 401 || code == 403) {
        return ProbeResult(
          verdict: ProbeVerdict.unplayable,
          reason: 'blocked by CDN ($code) — needs a different Referer',
          latencyMs: elapsed,
          headers: headers,
        );
      }
      if (code == 404 || code == 410) {
        return ProbeResult(
          verdict: ProbeVerdict.unplayable,
          reason: 'gone ($code) — this provider has no copy of this title',
          latencyMs: elapsed,
          headers: headers,
        );
      }
      if (code >= 500) {
        return ProbeResult(
          verdict: ProbeVerdict.unplayable,
          reason: 'provider error ($code)',
          latencyMs: elapsed,
          headers: headers,
        );
      }
      if (code >= 400) {
        return ProbeResult(
          verdict: ProbeVerdict.unplayable,
          reason: 'HTTP $code',
          latencyMs: elapsed,
          headers: headers,
        );
      }

      if (buffer.isEmpty) {
        return ProbeResult(
          verdict: ProbeVerdict.unplayable,
          reason: 'empty response body',
          latencyMs: elapsed,
          headers: headers,
        );
      }

      final head = latin1.decode(buffer, allowInvalid: true).toLowerCase();

      // An HTML error/consent/interstitial page served with HTTP 200 is the
      // single most common "looks fine, plays nothing" failure.
      if (head.contains('<html') ||
          head.contains('<!doctype') ||
          head.contains('<head') ||
          head.contains('<script')) {
        return ProbeResult(
          verdict: ProbeVerdict.unplayable,
          reason: 'returned a web page, not video',
          latencyMs: elapsed,
          headers: headers,
        );
      }

      final looksHls = head.contains('#extm3u');
      final looksMp4 =
          head.length > 8 &&
          (head.contains('ftyp') ||
              head.contains('moov') ||
              head.contains('mdat'));

      if (looksHls || looksMp4) {
        return ProbeResult(
          verdict: ProbeVerdict.playable,
          latencyMs: elapsed,
          headers: headers,
        );
      }

      // Some CDNs answer with a playlist that omits #EXTM3U on ranged reads.
      if (uri.path.toLowerCase().endsWith('.m3u8') && code == 206) {
        return ProbeResult(
          verdict: ProbeVerdict.playable,
          latencyMs: elapsed,
          headers: headers,
        );
      }

      return ProbeResult(
        verdict: ProbeVerdict.unknown,
        reason: 'unrecognised payload',
        latencyMs: elapsed,
        headers: headers,
      );
    } on TimeoutException {
      return ProbeResult(
        verdict: ProbeVerdict.unplayable,
        reason: 'timed out after ${timeout.inSeconds}s',
        latencyMs: DateTime.now().difference(started).inMilliseconds,
        headers: headers,
      );
    } on SocketException catch (e) {
      return ProbeResult(
        verdict: ProbeVerdict.unplayable,
        reason: 'host unreachable (${e.message})',
        latencyMs: DateTime.now().difference(started).inMilliseconds,
        headers: headers,
      );
    } catch (e) {
      return ProbeResult(
        verdict: ProbeVerdict.unplayable,
        reason: 'probe failed: $e',
        latencyMs: DateTime.now().difference(started).inMilliseconds,
        headers: headers,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Cheap reachability check for an embed *page* (webview / extractor
  /// candidates). We cannot know whether its player will work, but a 404/403
  /// here means it is definitively dead and not worth opening.
  static Future<ProbeResult> probeEmbedPage(
    String url, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return const ProbeResult(
        verdict: ProbeVerdict.unknown,
        reason: 'bad url',
      );
    }

    final client = HttpClient()..connectionTimeout = timeout;
    final started = DateTime.now();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(timeout);
      await response.drain<void>().catchError((_) {});

      final elapsed = DateTime.now().difference(started).inMilliseconds;
      if (response.statusCode >= 400) {
        return ProbeResult(
          verdict: ProbeVerdict.unplayable,
          reason: 'embed page returned ${response.statusCode}',
          latencyMs: elapsed,
        );
      }
      return ProbeResult(verdict: ProbeVerdict.unknown, latencyMs: elapsed);
    } on TimeoutException {
      return ProbeResult(
        verdict: ProbeVerdict.unplayable,
        reason: 'embed page timed out',
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );
    } on SocketException {
      return ProbeResult(
        verdict: ProbeVerdict.unplayable,
        reason: 'embed host unreachable',
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );
    } catch (e) {
      return ProbeResult(
        verdict: ProbeVerdict.unknown,
        reason: 'probe inconclusive: $e',
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );
    } finally {
      client.close(force: true);
    }
  }

  static void clearCache() => _cache.clear();
}

class RankedCandidate {
  final StreamInfo stream;
  final ProbeResult probe;
  final double score;

  const RankedCandidate({
    required this.stream,
    required this.probe,
    required this.score,
  });

  bool get isPlayable => probe.isPlayable;
  bool get isUnknown => probe.verdict == ProbeVerdict.unknown;

  /// True when this candidate can only be played by handing it to a WebView.
  bool get needsWebView =>
      !stream.engine.startsWith('native_') &&
      stream.engine != 'native_extractor' &&
      !probe.isPlayable;
}
