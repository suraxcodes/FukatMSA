/// Tests for provider URL construction.
///
/// This logic used to live inside `PlayerScreenState` (impossible to test
/// without a widget tree) and was duplicated, incorrectly, in
/// `PlaybackManager`. It is now a pure static function.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fukat_MSA/services/stream_resolver.dart';

void main() {
  group('StreamResolver.buildEmbedUrl', () {
    test('movies use the plain base + tmdb id', () async {
      final url = await StreamResolver.buildEmbedUrl(
        {
          'engine': 'webview',
          'id_type': 'tmdb',
          'format_style': 'slash',
          'movie_url': 'https://player.example/movie/',
        },
        tmdbId: '550',
        isMovie: true,
        season: 1,
        episode: 1,
      );
      expect(url, 'https://player.example/movie/550');
    });

    test('slash style builds /tv/id/season/episode', () async {
      final url = await StreamResolver.buildEmbedUrl(
        {
          'engine': 'webview',
          'id_type': 'tmdb',
          'format_style': 'slash',
          'tv_url': 'https://player.example/tv/',
        },
        tmdbId: '1399',
        isMovie: false,
        season: 2,
        episode: 7,
      );
      expect(url, 'https://player.example/tv/1399/2/7');
    });

    test('query style appends &s=&e=', () async {
      final url = await StreamResolver.buildEmbedUrl(
        {
          'engine': 'webview',
          'id_type': 'tmdb',
          'format_style': 'query',
          'tv_url': 'https://q.example/embed/tv?tmdb=',
        },
        tmdbId: '1399',
        isMovie: false,
        season: 1,
        episode: 3,
      );
      expect(url, 'https://q.example/embed/tv?tmdb=1399&s=1&e=3');
    });

    test('dash style builds id-season-episode', () async {
      final url = await StreamResolver.buildEmbedUrl(
        {
          'engine': 'webview',
          'id_type': 'tmdb',
          'format_style': 'dash',
          'tv_url': 'https://d.example/embed/',
        },
        tmdbId: '1399',
        isMovie: false,
        season: 3,
        episode: 4,
      );
      expect(url, 'https://d.example/embed/1399-3-4');
    });

    test('throws a typed error when the provider has no base url', () async {
      expect(
        () => StreamResolver.buildEmbedUrl(
          {'engine': 'webview', 'id_type': 'tmdb', 'format_style': 'slash'},
          tmdbId: '1',
          isMovie: true,
          season: 1,
          episode: 1,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
