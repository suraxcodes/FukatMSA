/// Regression test using the user's real `remote_config.json` verbatim.
///
/// It previously produced 0 usable providers: 9 of 12 entries were silently
/// dropped because the engine was either missing (7 hand-written embed servers)
/// or named something this client does not implement (`native_omss`,
/// `native_miruro`). The app needs to load a hand-written config *as written*.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fukat_MSA/services/remote_config_service.dart';

/// Copy of the user's file, unchanged.
const String userConfigJson = r'''
{
  "active_providers": [
    {"name": "OMSS Super Aggregator", "engine": "native_omss", "id_type": "tmdb"},
    {"name": "Anime Server", "engine": "native_miruro", "id_type": "tmdb"},
    {"name": "Server 1", "id_type": "imdb", "format_style": "query",
     "movie_url": "https://vidsrcme.ru/embed/movie?imdb=",
     "tv_url": "https://vidsrcme.ru/embed/tv?imdb="},
    {"name": "Server 2", "id_type": "tmdb", "format_style": "slash",
     "movie_url": "https://vidsrc.fyi/embed/movie/",
     "tv_url": "https://vidsrc.fyi/embed/tv/"},
    {"name": "Server 3", "id_type": "tmdb", "format_style": "slash",
     "movie_url": "https://vidnest.fun/movie/",
     "tv_url": "https://vidnest.fun/tv/",
     "anime_url": "https://vidnest.fun/anime/"},
    {"name": "Server 4", "id_type": "tmdb", "format_style": "slash",
     "movie_url": "https://vidlink.pro/movie/",
     "tv_url": "https://vidlink.pro/tv/"},
    {"name": "Server 5", "id_type": "tmdb", "format_style": "slash",
     "movie_url": "https://111movies.net/movie/",
     "tv_url": "https://111movies.net/tv/"},
    {"name": "Server 6", "id_type": "tmdb", "format_style": "slash",
     "movie_url": "https://www.vidfast.net/movie/",
     "tv_url": "https://www.vidfast.net/tv/"},
    {"name": "Server 7", "id_type": "tmdb", "format_style": "dash",
     "movie_url": "https://autoembed.co/movie/tmdb/",
     "tv_url": "https://autoembed.co/tv/tmdb/"},
    {"name": "Server 8", "engine": "webview", "id_type": "tmdb", "format_style": "slash",
     "movie_url": "https://vidsrc.mov/embed/movie/",
     "tv_url": "https://vidsrc.mov/embed/tv/"},
    {"name": "Server 9", "engine": "webview", "id_type": "tmdb", "format_style": "slash",
     "movie_url": "https://player.videasy.net/movie/",
     "tv_url": "https://player.videasy.net/tv/"},
    {"name": "Server 10", "engine": "webview", "id_type": "tmdb", "format_style": "slash",
     "movie_url": "https://www.vidking.net/embed/movie/",
     "tv_url": "https://www.vidking.net/embed/tv/"}
  ],
  "no_streams_text": "No working streams found. Please select another server."
}
''';

void main() {
  group("user's real remote_config.json", () {
    late ProviderConfig config;

    setUpAll(() {
      config = RemoteConfigService.validate(
        jsonDecode(userConfigJson),
        source: 'user file',
      );
    });

    test('loads 11 of 12 — only the URL-less dead-miruro entry is dropped', () {
      expect(config.providers, hasLength(11));
      expect(config.rejected, hasLength(1));
      // The one rejection must be actionable, not a silent disappearance.
      expect(config.rejected.single, contains('native_miruro'));
      expect(config.rejected.single, contains('suspended'));
      expect(config.rejected.single, contains('movie_url'));
    });

    test('a provider with no engine becomes webview', () {
      final serverOne = config.providers.firstWhere(
        (p) => p['name'] == 'Server 1',
      );
      expect(serverOne['engine'], 'webview');
    });

    test('native_omss is mapped to a real engine, not dropped', () {
      final omss = config.providers.firstWhere(
        (p) => p['name'] == 'OMSS Super Aggregator',
      );
      expect(omss['engine'], 'native_stremio');
      expect(omss['engine_alias'], 'native_omss');
    });

    test('native_miruro WITH urls would map to the extractor', () {
      final fixed = RemoteConfigService.validate({
        'active_providers': [
          {
            'name': 'Anime Server',
            'engine': 'native_miruro',
            'movie_url': 'https://example.invalid/anime/',
            'tv_url': 'https://example.invalid/anime/',
          },
        ],
      });
      expect(fixed.providers, hasLength(1));
      expect(fixed.providers.single['engine'], 'native_extractor');
      expect(fixed.providers.single['engine_alias'], 'native_miruro');
    });

    test('explicit webview engines are preserved', () {
      for (final name in ['Server 8', 'Server 9', 'Server 10']) {
        expect(
          config.providers.firstWhere((p) => p['name'] == name)['engine'],
          'webview',
        );
      }
    });

    test('unknown metadata keys are preserved, not stripped', () {
      final serverThree = config.providers.firstWhere(
        (p) => p['name'] == 'Server 3',
      );
      expect(serverThree['anime_url'], 'https://vidnest.fun/anime/');
    });
  });
}
