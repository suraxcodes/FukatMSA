/// Tests for provider-config validation — the security boundary that stops a
/// pasted-in or QR-scanned repo from injecting arbitrary URLs into the player.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fukat_MSA/core/errors.dart';
import 'package:fukat_MSA/services/remote_config_service.dart';

Map<String, dynamic> provider({
  required String engine,
  String? movieUrl,
  String? tvUrl,
  List<String>? platforms,
  bool? animeOnly,
}) {
  final map = <String, dynamic>{'name': 'p-$engine', 'engine': engine};
  if (movieUrl != null) map['movie_url'] = movieUrl;
  if (tvUrl != null) map['tv_url'] = tvUrl;
  if (platforms != null) map['platforms'] = platforms;
  if (animeOnly != null) map['anime_only'] = animeOnly;
  return map;
}

void main() {
  group('RemoteConfigService.validate', () {
    test('accepts a well-formed webview provider', () {
      final config = RemoteConfigService.validate({
        'active_providers': [
          provider(
            engine: 'webview',
            movieUrl: 'https://good.example/m/',
            tvUrl: 'https://good.example/t/',
          ),
        ],
      });

      expect(config.providers, hasLength(1));
      expect(config.rejected, isEmpty);
    });

    test('rejects unknown engines', () {
      final config = RemoteConfigService.validate({
        'active_providers': [
          provider(engine: 'spooky_engine', movieUrl: 'https://x.example/'),
        ],
      });

      expect(config.providers, isEmpty);
      expect(config.rejected.single, contains('unknown engine'));
    });

    test('rejects javascript: and data: URLs', () {
      final config = RemoteConfigService.validate({
        'active_providers': [
          provider(engine: 'webview', movieUrl: 'javascript:alert(1)'),
          provider(
            engine: 'webview',
            movieUrl: 'data:text/html,<script>x</script>',
          ),
        ],
      });

      expect(config.providers, isEmpty);
      expect(config.rejected, hasLength(2));
      expect(config.rejected.every((r) => r.contains('non-https')), isTrue);
    });

    test('rejects plain http even on a real host', () {
      final config = RemoteConfigService.validate({
        'active_providers': [
          provider(engine: 'webview', movieUrl: 'http://plain.example/m/'),
        ],
      });
      expect(config.providers, isEmpty);
    });

    test('rejects a provider with no URLs at all', () {
      final config = RemoteConfigService.validate({
        'active_providers': [provider(engine: 'webview')],
      });
      expect(config.rejected.single, contains('no movie_url or tv_url'));
    });

    test('keeps native engines that need no URLs', () {
      final config = RemoteConfigService.validate({
        'active_providers': [provider(engine: 'native_stremio')],
      });
      expect(config.providers, hasLength(1));
    });

    test('honours the platforms allow-list', () {
      final config = RemoteConfigService.validate({
        'active_providers': [
          provider(
            engine: 'webview',
            movieUrl: 'https://only-elsewhere.example/m/',
            platforms: ['plan9'],
          ),
        ],
      });
      expect(config.providers, isEmpty);
      expect(config.rejected.single, contains('not enabled on'));
    });

    test('partially valid config keeps the good entries', () {
      final config = RemoteConfigService.validate({
        'active_providers': [
          provider(engine: 'webview', movieUrl: 'https://good.example/m/'),
          provider(engine: 'nope'),
          'not even a map',
        ],
      });
      expect(config.providers, hasLength(1));
      expect(config.rejected, hasLength(2));
    });

    test('throws a typed parse error for non-object documents', () {
      expect(
        () => RemoteConfigService.validate([1, 2, 3]),
        throwsA(
          isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.parse),
        ),
      );
    });

    test('throws a typed parse error when active_providers is missing', () {
      expect(
        () => RemoteConfigService.validate({'providers': []}),
        throwsA(isA<AppError>()),
      );
    });
  });
}
