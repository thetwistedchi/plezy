import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../media/media_kind.dart';
import '../../media/media_rating.dart';
import '../../utils/external_ids.dart';

/// A provider answered with an error status (down, rate limited, bad key).
/// Thrown so the cache keeps it only briefly and the next visit asks again.
class ProviderUnavailable implements Exception {
  const ProviderUnavailable(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'HTTP $statusCode';
}

/// What one provider returned for a title: scores by [MediaRatingSource] key
/// (0-10 scale) plus ids other lookups can use.
class ProviderScores {
  const ProviderScores({this.ratings = const {}, this.malId, this.traktId});

  final Map<String, MediaRatingSource> ratings;
  final int? malId;
  final int? traktId;

  static const empty = ProviderScores();
}

/// MDBList: one JSON request returns IMDb, TMDB, Trakt, Letterboxd, Rotten
/// Tomatoes (critics and audience), Metacritic and MyAnimeList scores.
/// Needs a free API key (mdblist.com, 1,000 requests a day).
class MdbListProvider {
  MdbListProvider(this._client);

  final http.Client _client;

  /// MDBList source names to [MediaRatingSource] keys.
  static const _sources = {
    'imdb': 'imdb',
    'tmdb': 'tmdb',
    'trakt': 'trakt',
    'letterboxd': 'letterboxd',
    'tomatoes': 'rottenTomatoesCritic',
    'popcorn': 'rottenTomatoesAudience',
    'metacritic': 'metacritic',
    'myanimelist': 'mal',
  };

  Future<ProviderScores> fetch({required String apiKey, required MediaKind kind, required ExternalIds ids}) async {
    final type = kind == MediaKind.movie ? 'movie' : 'show';
    final (provider, id) = switch (ids) {
      ExternalIds(:final tmdb?) => ('tmdb', '$tmdb'),
      ExternalIds(:final imdb?) when imdb.isNotEmpty => ('imdb', imdb),
      ExternalIds(:final tvdb?) when kind == MediaKind.show => ('tvdb', '$tvdb'),
      _ => (null, null),
    };
    if (provider == null) return ProviderScores.empty;
    final uri = Uri.https('api.mdblist.com', '/$provider/$type/$id', {'apikey': apiKey});
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw ProviderUnavailable(response.statusCode);
    return parse(jsonDecode(response.body));
  }

  static ProviderScores parse(Object? json) {
    if (json is! Map) return ProviderScores.empty;
    final ratings = <String, MediaRatingSource>{};
    final list = json['ratings'];
    if (list is List) {
      for (final entry in list) {
        if (entry is! Map) continue;
        final key = _sources[entry['source']];
        if (key == null) continue;
        final votes = entry['votes'];
        // `score` is MDBList's 0-100 normalization of `value`.
        final score = entry['score'];
        final rating = MediaRatingSource.fromScale(
          key,
          score is num ? score : null,
          scale: 100,
          votes: votes is num && votes > 0 ? votes : null,
        );
        if (rating != null) ratings[key] = rating;
      }
    }
    final idMap = json['ids'];
    int? asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
    return ProviderScores(
      ratings: ratings,
      malId: idMap is Map ? asInt(idMap['mal']) : null,
      traktId: idMap is Map ? asInt(idMap['trakt']) : null,
    );
  }
}

/// OMDb: IMDb, Rotten Tomatoes (critics) and the Metascore by IMDb id.
/// Needs a free API key (omdbapi.com, 1,000 requests a day).
class OmdbProvider {
  OmdbProvider(this._client);

  final http.Client _client;

  Future<ProviderScores> fetch({required String apiKey, required ExternalIds ids}) async {
    final imdb = ids.imdb?.trim();
    if (imdb == null || imdb.isEmpty) return ProviderScores.empty;
    final uri = Uri.https('www.omdbapi.com', '/', {'i': imdb, 'apikey': apiKey});
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw ProviderUnavailable(response.statusCode);
    return parse(jsonDecode(response.body));
  }

  static ProviderScores parse(Object? json) {
    if (json is! Map || json['Response'] == 'False') return ProviderScores.empty;
    final ratings = <String, MediaRatingSource>{};
    final votes = num.tryParse('${json['imdbVotes']}'.replaceAll(',', ''));
    final imdb = MediaRatingSource.fromScale('imdb', num.tryParse('${json['imdbRating']}'), scale: 10, votes: votes);
    if (imdb != null) ratings['imdb'] = imdb;
    final meta = MediaRatingSource.fromScale('metacritic', num.tryParse('${json['Metascore']}'), scale: 100);
    if (meta != null) ratings['metacritic'] = meta;
    final list = json['Ratings'];
    if (list is List) {
      for (final entry in list) {
        if (entry is! Map || entry['Source'] != 'Rotten Tomatoes') continue;
        final percent = num.tryParse('${entry['Value']}'.replaceAll('%', ''));
        final rt = MediaRatingSource.fromScale('rottenTomatoesCritic', percent, scale: 100);
        if (rt != null) ratings['rottenTomatoesCritic'] = rt;
      }
    }
    return ProviderScores(ratings: ratings);
  }
}

/// Jikan, the unofficial MyAnimeList API: anime scores, no key. Rate limited
/// (3 requests a second), so it is only asked about anime.
class JikanProvider {
  JikanProvider(this._client);

  final http.Client _client;

  /// By MAL id when known, otherwise the best title match of the right year.
  Future<ProviderScores> fetch({int? malId, required String title, int? year}) async {
    Map? anime;
    if (malId != null) {
      final response = await _client
          .get(Uri.https('api.jikan.moe', '/v4/anime/$malId'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw ProviderUnavailable(response.statusCode);
      final json = jsonDecode(response.body);
      anime = json is Map && json['data'] is Map ? json['data'] as Map : null;
    } else {
      if (title.trim().isEmpty) return ProviderScores.empty;
      final response = await _client
          .get(Uri.https('api.jikan.moe', '/v4/anime', {'q': title, 'limit': '5'}))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw ProviderUnavailable(response.statusCode);
      final json = jsonDecode(response.body);
      final data = json is Map ? json['data'] : null;
      if (data is! List) return ProviderScores.empty;
      for (final entry in data) {
        if (entry is! Map) continue;
        final aired = entry['aired'];
        final from = aired is Map ? aired['prop'] : null;
        final entryYear = from is Map && from['from'] is Map ? (from['from'] as Map)['year'] : null;
        // A title search is fuzzy: without a matching year, no score.
        if (year == null || entryYear == year) {
          anime = entry;
          break;
        }
      }
    }
    if (anime == null) return ProviderScores.empty;
    final score = anime['score'];
    final votes = anime['scored_by'];
    final id = anime['mal_id'];
    final rating = MediaRatingSource.fromScale(
      'mal',
      score is num ? score : null,
      scale: 10,
      votes: votes is num && votes > 0 ? votes : null,
    );
    return ProviderScores(ratings: {'mal': ?rating}, malId: id is num ? id.toInt() : malId);
  }
}
