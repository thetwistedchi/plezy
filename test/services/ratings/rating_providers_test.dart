import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/services/ratings/rating_providers.dart';
import 'package:plezy/utils/rating_median.dart';

void main() {
  group('MdbListProvider.parse', () {
    test('maps every known source onto the 0-10 scale and reads ids', () {
      final scores = MdbListProvider.parse({
        'ratings': [
          {'source': 'imdb', 'value': 8.7, 'score': 87, 'votes': 2000000},
          {'source': 'letterboxd', 'value': 4.2, 'score': 84},
          {'source': 'tomatoes', 'value': 83, 'score': 83},
          {'source': 'popcorn', 'value': 85, 'score': 85},
          {'source': 'metacritic', 'value': 73, 'score': 73},
          {'source': 'myanimelist', 'value': null, 'score': null},
          {'source': 'rogerebert', 'value': 4, 'score': 100},
        ],
        'ids': {'mal': 123, 'trakt': '456'},
      });
      expect(scores.ratings['imdb']!.value, closeTo(8.7, 1e-9));
      expect(scores.ratings['imdb']!.votes, 2000000);
      expect(scores.ratings['letterboxd']!.value, closeTo(8.4, 1e-9));
      expect(scores.ratings['rottenTomatoesCritic']!.value, closeTo(8.3, 1e-9));
      expect(scores.ratings['rottenTomatoesAudience']!.value, closeTo(8.5, 1e-9));
      expect(scores.ratings['metacritic']!.value, closeTo(7.3, 1e-9));
      expect(scores.ratings.containsKey('mal'), isFalse);
      expect(scores.ratings.length, 5);
      expect(scores.malId, 123);
      expect(scores.traktId, 456);
    });

    test('tolerates garbage', () {
      expect(MdbListProvider.parse('nope').ratings, isEmpty);
      expect(MdbListProvider.parse({'ratings': 'x'}).ratings, isEmpty);
    });
  });

  group('OmdbProvider.parse', () {
    test('reads IMDb, Metascore and the Tomatometer', () {
      final scores = OmdbProvider.parse({
        'Response': 'True',
        'imdbRating': '8.7',
        'imdbVotes': '2,100,000',
        'Metascore': '73',
        'Ratings': [
          {'Source': 'Internet Movie Database', 'Value': '8.7/10'},
          {'Source': 'Rotten Tomatoes', 'Value': '83%'},
        ],
      });
      expect(scores.ratings['imdb']!.value, closeTo(8.7, 1e-9));
      expect(scores.ratings['imdb']!.votes, 2100000);
      expect(scores.ratings['metacritic']!.value, closeTo(7.3, 1e-9));
      expect(scores.ratings['rottenTomatoesCritic']!.value, closeTo(8.3, 1e-9));
    });

    test('N/A and failed responses give nothing', () {
      expect(OmdbProvider.parse({'Response': 'False', 'Error': 'Movie not found!'}).ratings, isEmpty);
      expect(OmdbProvider.parse({'Response': 'True', 'imdbRating': 'N/A', 'Metascore': 'N/A'}).ratings, isEmpty);
    });
  });

  group('JikanProvider', () {
    Map<String, Object?> entry(int id, String title, int year, double score) => {
      'mal_id': id,
      'title': title,
      'title_english': null,
      'score': score,
      'scored_by': 1000,
      'aired': {
        'prop': {
          'from': {'year': year},
        },
      },
    };

    JikanProvider provider(List<Map<String, Object?>> results) => JikanProvider(
      MockClient((request) async {
        expect(request.url.host, 'api.jikan.moe');
        return http.Response(jsonEncode({'data': results}), 200);
      }),
    );

    test('takes the result of the right year', () async {
      final scores = await provider([
        entry(1, 'Fullmetal Alchemist', 2003, 8.1),
        entry(2, 'Fullmetal Alchemist: Brotherhood', 2009, 9.1),
      ]).fetch(title: 'Fullmetal Alchemist', year: 2009);
      expect(scores.malId, 2);
      expect(scores.ratings['mal']!.value, closeTo(9.1, 1e-9));
    });

    test('without a year only an exact title counts', () async {
      final none = await provider([entry(3, 'Naruto: Shippuden', 2007, 8.3)]).fetch(title: 'Naruto');
      expect(none.ratings, isEmpty);
      final exact = await provider([entry(4, 'Naruto', 2002, 8.0)]).fetch(title: 'naruto!');
      expect(exact.malId, 4);
    });
  });

  group('ratingMedian', () {
    test('leaves the Tomatometer out and uses one score per source', () {
      final median = ratingMedian(const [
        MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.8),
        MediaRatingSource(source: 'imdb', value: 7.0),
        MediaRatingSource(source: 'imdb', value: 1.0),
        MediaRatingSource(source: 'letterboxd', value: 8.0),
        MediaRatingSource(source: 'tmdb', value: 7.6),
      ]);
      expect(median!.score, 76);
      expect(median.sources, 3);
    });

    test('even count averages the middle two, nothing gives null', () {
      expect(
        ratingMedian(const [
          MediaRatingSource(source: 'imdb', value: 7.0),
          MediaRatingSource(source: 'tmdb', value: 8.0),
        ])!.score,
        75,
      );
      expect(ratingMedian(const [MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.0)]), isNull);
    });
  });
}

