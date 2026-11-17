import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/services/ratings/title_links_service.dart';
import 'package:plezy/utils/external_ids.dart';
import 'package:plezy/widgets/ratings_links_row.dart';

const _letterboxdPage = '''
<html><head>
<script type="application/ld+json">
/* <![CDATA[ */
{"@type":"Movie","name":"Neon Horizon","aggregateRating":{"bestRating":5,"reviewCount":1200,"@type":"aggregateRating","ratingValue":3.9,"worstRating":0,"ratingCount":48211}}
/* ]]> */
</script>
</head><body></body></html>
''';

void main() {
  group('parseLetterboxdRating', () {
    test('reads aggregateRating onto the 0-10 scale', () {
      final rating = TitleLinksService.parseLetterboxdRating(_letterboxdPage)!;
      expect(rating.source, 'letterboxd');
      expect(rating.value, closeTo(7.8, 1e-9));
      expect(rating.votes, 48211);
    });

    test('null when the page has no rating yet', () {
      expect(TitleLinksService.parseLetterboxdRating('<html></html>'), isNull);
      expect(
        TitleLinksService.parseLetterboxdRating(
          '<script type="application/ld+json">{"@type":"Movie","name":"x"}</script>',
        ),
        isNull,
      );
    });
  });

  group('linksFor', () {
    final service = TitleLinksService(client: MockClient((_) async => http.Response('', 404)));

    test('a movie gets Letterboxd, Trakt, IMDb, Rotten Tomatoes and TMDB links in order', () {
      final links = service.linksFor(
        kind: MediaKind.movie,
        ids: const ExternalIds(imdb: 'tt0083658', tmdb: 78),
        title: 'Blade Runner',
        year: 1982,
        known: const [MediaRatingSource(source: 'imdb', value: 8.1)],
      );
      expect(links.map((l) => l.source), ['letterboxd', 'trakt', 'imdb', 'rottenTomatoesCritic', 'tmdb']);
      expect(links[0].url.toString(), 'https://letterboxd.com/tmdb/78/');
      expect(links[1].url.toString(), 'https://trakt.tv/search/tmdb/78?id_type=movie');
      expect(links[2].url.toString(), 'https://www.imdb.com/title/tt0083658/');
      expect(links[2].rating?.value, 8.1);
      expect(links[3].url.queryParameters['search'], 'Blade Runner 1982');
      expect(links[4].url.toString(), 'https://www.themoviedb.org/movie/78');
    });

    test('a show gets no Letterboxd link and a TMDB tv link', () {
      final links = service.linksFor(kind: MediaKind.show, ids: const ExternalIds(tmdb: 1399), title: 'Show');
      expect(links.map((l) => l.source), isNot(contains('letterboxd')));
      expect(links.last.url.toString(), 'https://www.themoviedb.org/tv/1399');
    });

    test('episodes and other kinds get nothing', () {
      expect(service.linksFor(kind: MediaKind.episode, ids: const ExternalIds(tmdb: 1), title: 'x'), isEmpty);
    });
  });

  test('withFetchedScores fills Letterboxd and Trakt and uses the Trakt slug', () async {
    final service = TitleLinksService(
      client: MockClient((request) async {
        final url = request.url.toString();
        if (url.startsWith('https://letterboxd.com/')) return http.Response(_letterboxdPage, 200);
        if (url.contains('/search/tmdb/78')) {
          return http.Response('[{"type":"movie","movie":{"ids":{"slug":"blade-runner-1982"}}}]', 200);
        }
        if (url.endsWith('/movies/blade-runner-1982/ratings')) {
          return http.Response('{"rating":8.4,"votes":12000}', 200);
        }
        return http.Response('', 404);
      }),
    );
    const ids = ExternalIds(imdb: 'tt0083658', tmdb: 78);
    final links = await service.withFetchedScores(
      service.linksFor(kind: MediaKind.movie, ids: ids, title: 'Blade Runner'),
      kind: MediaKind.movie,
      ids: ids,
    );
    final letterboxd = links.firstWhere((l) => l.source == 'letterboxd');
    final trakt = links.firstWhere((l) => l.source == 'trakt');
    expect(letterboxd.rating?.value, closeTo(7.8, 1e-9));
    expect(trakt.rating?.value, closeTo(8.4, 1e-9));
    expect(trakt.url.toString(), 'https://trakt.tv/movies/blade-runner-1982');
  });

  test('compactCount', () {
    expect(compactCount(950), '950');
    expect(compactCount(1260), '1.3K');
    expect(compactCount(48211), '48K');
    expect(compactCount(1260000), '1.3M');
  });
}
