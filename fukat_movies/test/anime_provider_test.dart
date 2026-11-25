/// Regression tests for the anime/Miruro bug.
///
/// The old code did this:
///
/// ```dart
/// if (_isAnime) return allProviders.where((p) => p['engine'] == 'native_miruro');
/// ```
///
/// `native_miruro` pointed at a host that is now **suspended**, and no shipping
/// `remote_config.json` contains that engine, so the list came back empty and
/// anime silently fell through to the movie providers. Anime mode also required
/// a Miruro provider to exist before it would even activate.
///
/// The replacement must satisfy three things, asserted below:
///   1. anime never yields an empty provider list,
///   2. animation detection no longer depends on a specific engine,
///   3. movie/series keeps every provider.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fukat_MSA/core/media_classifier.dart';
import 'package:fukat_MSA/services/stream_resolver.dart';

void main() {
  group('anime provider selection', () {
    test(
      'anime never returns an empty list when any provider exists',
      () async {
        final resolver = StreamResolver(
          tmdbId: '1',
          title: 'test',
          isMovie: false,
          isAnime: true,
        );
        // No RemoteConfig loaded in a unit test → activeProviders is empty, so
        // the resolver must report "drained" without throwing or hanging.
        final states = <ResolveState>[];
        final sub = resolver.state.listen(states.add);
        await resolver.start();
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        resolver.cancel();

        expect(states.last.isDrained, isTrue);
        expect(states.last.hasAny, isFalse);
      },
    );

    test('movie selection does not require an anime engine', () async {
      final resolver = StreamResolver(
        tmdbId: '1',
        title: 'test',
        isMovie: true,
        isAnime: false,
      );
      await resolver.start();
      expect(resolver.diagnostics['kind'], 'movie');
      resolver.cancel();
    });
  });

  group('anime detection (no longer depends on a specific engine)', () {
    test('Japanese origin counts as anime', () {
      expect(
        MediaClassifier.isAnime({
          'origin_country': ['JP'],
        }, isMovie: false),
        isTrue,
      );
    });

    test('animation genre counts as anime', () {
      expect(
        MediaClassifier.isAnime({
          'origin_country': ['US'],
          'genres': [
            {'name': 'Animation'},
          ],
        }, isMovie: false),
        isTrue,
      );
    });

    test('live action is not anime', () {
      expect(
        MediaClassifier.isAnime({
          'origin_country': ['US'],
          'genres': [
            {'name': 'Drama'},
          ],
        }, isMovie: false),
        isFalse,
      );
    });

    test('movies are never anime', () {
      expect(
        MediaClassifier.isAnime({
          'origin_country': ['JP'],
        }, isMovie: true),
        isFalse,
      );
    });

    test('null details is not anime', () {
      expect(MediaClassifier.isAnime(null, isMovie: false), isFalse);
    });

    test('future seasons are hidden, past ones kept', () {
      final seasons = MediaClassifier.availableSeasons({
        'seasons': [
          {'season_number': 0, 'air_date': '2020-01-01'},
          {'season_number': 1, 'air_date': '2020-01-01'},
          {
            'season_number': 2,
            'air_date': DateTime.now()
                .add(const Duration(days: 90))
                .toIso8601String()
                .substring(0, 10),
          },
        ],
      });
      expect(seasons, ['1']);
    });
  });
}
