/// Proves the auto-server-selection logic against a real local HTTP server.
///
/// Each provider in these tests is a real endpoint that misbehaves in one of
/// the ways providers actually misbehave: 403 from a CDN, a 404 for a stale id,
/// an HTML interstitial served with 200, a hang, or a genuine HLS playlist.
/// The prober must rank the *only playable* one first, so the player never has
/// to be switched by hand.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fukat_MSA/player/stream_prober.dart';
import 'package:fukat_MSA/services/provider_reputation.dart';
import 'package:fukat_MSA/services/stream_resolver.dart';

StreamInfo stream(String name, String url, {String engine = 'native_stream'}) =>
    StreamInfo(providerName: name, engine: engine, url: url);

void main() {
  late HttpServer server;
  late String base;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    unawaited(
      server.forEach((request) async {
        final path = request.uri.path;
        final response = request.response;
        switch (path) {
          case '/ok.m3u8':
            response
              ..statusCode = 200
              ..headers.contentType = ContentType(
                'application',
                'vnd.apple.mpegurl',
              )
              ..write('#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:10,\nseg1.ts\n');
          case '/ok.mp4':
            response
              ..statusCode = 206
              ..headers.contentType = ContentType('video', 'mp4')
              ..add([0, 0, 0, 0x18, ...'ftypisom'.codeUnits]);
          case '/forbidden':
            response.statusCode = 403;
          case '/gone':
            response.statusCode = 404;
          case '/html.m3u8':
            // The classic trap: a real .m3u8 path, HTTP 200, HTML body.
            response
              ..statusCode = 200
              ..headers.contentType = ContentType.html
              ..write(
                '<!DOCTYPE html><html><head><title>Verify you are human'
                '</title></head><body>captcha</body></html>',
              );
          case '/empty':
            response
              ..statusCode = 200
              ..write('');
          case '/slow':
            await Future<void>.delayed(const Duration(seconds: 3));
            response
              ..statusCode = 200
              ..write('#EXTM3U\n');
          default:
            response.statusCode = 404;
        }
        await response.close();
      }),
    );
  });

  tearDown(() async {
    StreamProber.clearCache();
    await server.close(force: true);
  });

  group('StreamProber.verdicts', () {
    test('real HLS playlist is playable', () async {
      final r = await StreamProber.probeStream(stream('hls', '$base/ok.m3u8'));
      expect(r.verdict, ProbeVerdict.playable);
    });

    test('progressive MP4 header is playable', () async {
      final r = await StreamProber.probeStream(stream('mp4', '$base/ok.mp4'));
      expect(r.verdict, ProbeVerdict.playable);
    });

    test('403 is dead, with a CDN/Referer reason', () async {
      final r = await StreamProber.probeStream(
        stream('cdn', '$base/forbidden'),
      );
      expect(r.isDead, isTrue);
      expect(r.reason, contains('403'));
    });

    test('404 is dead', () async {
      final r = await StreamProber.probeStream(stream('stale', '$base/gone'));
      expect(r.isDead, isTrue);
    });

    test('HTML page served as .m3u8 is dead, not playable', () async {
      // This is the exact failure that made the user switch servers manually:
      // it looks like a successful resolve.
      final r = await StreamProber.probeStream(
        stream('trap', '$base/html.m3u8'),
      );
      expect(r.isDead, isTrue);
      expect(r.reason, contains('web page'));
    });

    test('empty body is dead', () async {
      final r = await StreamProber.probeStream(stream('empty', '$base/empty'));
      expect(r.isDead, isTrue);
    });

    test('timeout is dead, and is bounded by the supplied timeout', () async {
      final watch = Stopwatch()..start();
      final r = await StreamProber.probeStream(
        stream('slow', '$base/slow'),
        timeout: const Duration(milliseconds: 400),
      );
      watch.stop();
      expect(r.isDead, isTrue);
      expect(r.reason, contains('timed out'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('unreachable host is dead, not an unhandled exception', () async {
      final r = await StreamProber.probeStream(
        stream('nohost', 'http://127.0.0.1:1/none.m3u8'),
        timeout: const Duration(milliseconds: 800),
      );
      expect(r.isDead, isTrue);
    });

    test('non-HTTP scheme is "unknown" — the browser decides', () async {
      final r = await StreamProber.probeStream(stream('blob', 'blob:abc123'));
      expect(r.verdict, ProbeVerdict.unknown);
    });
  });

  group('automatic selection', () {
    test('ranks the only playable provider first', () async {
      final candidates = [
        stream('blocked-cdn', '$base/forbidden'),
        stream('html-trap', '$base/html.m3u8'),
        stream('stale-id', '$base/gone'),
        stream('good', '$base/ok.m3u8'),
      ];

      final ranked = await StreamProber.rank(candidates);

      expect(ranked.first.stream.providerName, 'good');
      expect(ranked.first.isPlayable, isTrue);
      expect(
        ranked.where((r) => r.probe.isDead).length,
        3,
        reason: 'the three broken ones must be marked dead, not "try anyway"',
      );
    });

    test('prefers the faster of two playable providers', () async {
      final ranked = await StreamProber.rank([
        stream('slow', '$base/slow'),
        stream('fast', '$base/ok.m3u8'),
      ]);
      expect(ranked.first.stream.providerName, 'fast');
    });

    test('reputation bonus breaks a tie toward what worked before', () async {
      final ranked = await StreamProber.rank(
        [
          stream('unknown-provider', '$base/ok.m3u8'),
          stream('proven-provider', '$base/ok.mp4'),
        ],
        latencyBonus: {'proven-provider': 40},
      );
      expect(ranked.first.stream.providerName, 'proven-provider');
    });

    test(
      'all-dead batch is fully dead (drives the "no source" screen)',
      () async {
        final ranked = await StreamProber.rank([
          stream('a', '$base/forbidden'),
          stream('b', '$base/gone'),
        ]);
        expect(ranked.every((r) => r.probe.isDead), isTrue);
      },
    );

    test('probing the same URL twice hits the cache', () async {
      final s = stream('cached', '$base/ok.m3u8');
      final first = await StreamProber.probeStream(s);
      final second = await StreamProber.probeStream(s);
      expect(identical(first, second), isTrue);
    });
  });

  group('ProviderReputation', () {
    test('unknown providers start at ~0.5, not 0 or 1', () {
      final stats = ProviderStats();
      expect(stats.reliability, closeTo(0.5, 0.01));
    });

    test('a proven provider outranks an unknown one', () {
      final proven = ProviderStats(played: 40, failed: 5);
      expect(proven.reliability, greaterThan(ProviderStats().reliability));
    });

    test('a provider that always fails ranks below unknown', () {
      final bad = ProviderStats(failed: 20);
      expect(bad.reliability, lessThan(ProviderStats().reliability));
    });

    test('1-for-1 does not beat 40-for-45 (smoothing works)', () {
      final lucky = ProviderStats(played: 1);
      final solid = ProviderStats(played: 40, failed: 5);
      expect(solid.reliability, greaterThanOrEqualTo(lucky.reliability));
    });
  });
}
