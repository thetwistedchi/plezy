import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../media/media_kind.dart';
import '../../media/media_rating.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import '../settings_service.dart';
import '../trackers/trakt/trakt_constants.dart';
import 'rating_providers.dart';

/// One site a title can be opened on, with the score that site gives it when
/// one is known. [source] uses the [MediaRatingSource] keys so the card can
/// reuse the existing brand badges.
class TitleLink {
  const TitleLink({required this.source, required this.siteName, required this.url, this.rating});

  final String source;
  final String siteName;
  final Uri url;
  final MediaRatingSource? rating;

  TitleLink withRating(MediaRatingSource? rating) =>
      TitleLink(source: source, siteName: siteName, url: url, rating: rating ?? this.rating);
}

/// Builds the "Ratings & links" row of a movie or show: a link per site and
/// whatever score is already known, topped up with Letterboxd and Trakt scores
/// fetched directly when no connected tracker supplied them.
///
/// Letterboxd has no public API. Its film page embeds a schema.org JSON-LD
/// block with `aggregateRating`, which is read here; when the page changes or
/// refuses the request, the card keeps its link and simply shows no score.
class TitleLinksService {
  TitleLinksService({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  static final TitleLinksService instance = TitleLinksService();

  static const Duration cacheTtl = Duration(hours: 24);

  /// How long a failed lookup (timeout, error status) is remembered: short,
  /// so a site that was down is asked again soon.
  static const Duration failureTtl = Duration(minutes: 15);

  final http.Client _client;
  final DateTime Function() _now;
  final Map<String, ({DateTime until, _Fetched value})> _cache = {};

  /// Order the row shows the sites in.
  static const List<String> siteOrder = [
    'letterboxd',
    'trakt',
    'imdb',
    'rottenTomatoesCritic',
    'rottenTomatoesAudience',
    'metacritic',
    'tmdb',
    'mal',
  ];

  /// Every link for a title. [known] are the scores the server and the
  /// connected trackers already reported (0-10 scale).
  List<TitleLink> linksFor({
    required MediaKind kind,
    required ExternalIds ids,
    required String title,
    int? year,
    List<MediaRatingSource> known = const [],
    String? traktSlug,
  }) {
    if (kind != MediaKind.movie && kind != MediaKind.show) return const [];
    MediaRatingSource? score(String key) {
      for (final rating in known) {
        if (rating.source == key) return rating;
      }
      return null;
    }

    final isMovie = kind == MediaKind.movie;
    final imdb = ids.imdb?.trim();
    final tmdb = ids.tmdb;
    final query = Uri.encodeQueryComponent(year == null ? title : '$title $year');
    final links = <TitleLink>[];

    // Letterboxd only lists films.
    if (isMovie && (tmdb != null || imdb != null)) {
      links.add(
        TitleLink(
          source: 'letterboxd',
          siteName: 'Letterboxd',
          url: letterboxdUrl(tmdb: tmdb, imdb: imdb)!,
          rating: score('letterboxd'),
        ),
      );
    }

    final trakt = traktUrl(kind: kind, tmdb: tmdb, imdb: imdb, tvdb: ids.tvdb, slug: traktSlug);
    if (trakt != null) {
      links.add(TitleLink(source: 'trakt', siteName: 'Trakt', url: trakt, rating: score('trakt')));
    }

    if (imdb != null && imdb.isNotEmpty) {
      links.add(
        TitleLink(
          source: 'imdb',
          siteName: 'IMDb',
          url: Uri.parse('https://www.imdb.com/title/$imdb/'),
          rating: score('imdb'),
        ),
      );
    }

    // Rotten Tomatoes has no public id mapping, so the link searches by title.
    final rtCritic = score('rottenTomatoesCritic') ?? score('rottenTomatoes');
    final rtAudience = score('rottenTomatoesAudience');
    final rtUrl = Uri.parse('https://www.rottentomatoes.com/search?search=$query');
    links.add(
      TitleLink(source: 'rottenTomatoesCritic', siteName: 'Rotten Tomatoes', url: rtUrl, rating: rtCritic),
    );
    if (rtAudience != null) {
      links.add(
        TitleLink(source: 'rottenTomatoesAudience', siteName: 'Rotten Tomatoes', url: rtUrl, rating: rtAudience),
      );
    }

    if (tmdb != null) {
      links.add(
        TitleLink(
          source: 'tmdb',
          siteName: 'TMDB',
          url: Uri.parse('https://www.themoviedb.org/${isMovie ? 'movie' : 'tv'}/$tmdb'),
          rating: score('tmdb'),
        ),
      );
    }
    return links;
  }

  /// Letterboxd resolves `/tmdb/{id}/` and `/imdb/{id}/` to the film page.
  static Uri? letterboxdUrl({int? tmdb, String? imdb}) {
    if (tmdb != null) return Uri.parse('https://letterboxd.com/tmdb/$tmdb/');
    if (imdb != null && imdb.isNotEmpty) return Uri.parse('https://letterboxd.com/imdb/$imdb/');
    return null;
  }

  /// The title's Trakt page: exact when the slug is known, otherwise Trakt's
  /// id search, which redirects to the title when the id matches one.
  static Uri? traktUrl({required MediaKind kind, int? tmdb, String? imdb, int? tvdb, String? slug}) {
    final type = kind == MediaKind.movie ? 'movie' : 'show';
    if (slug != null && slug.isNotEmpty) return Uri.parse('https://trakt.tv/${type}s/$slug');
    if (tmdb != null) return Uri.parse('https://trakt.tv/search/tmdb/$tmdb?id_type=$type');
    if (imdb != null && imdb.isNotEmpty) return Uri.parse('https://trakt.tv/search/imdb/$imdb?id_type=$type');
    if (tvdb != null && kind == MediaKind.show) return Uri.parse('https://trakt.tv/search/tvdb/$tvdb?id_type=show');
    return null;
  }

  /// Fills in scores missing from [links], and adds Metacritic, MyAnimeList
  /// and Rotten Tomatoes audience cards when a provider knows them:
  ///
  /// 1. MDBList (API key): one request for nearly every site.
  /// 2. OMDb (API key): IMDb, Tomatometer and Metascore, only for what is
  ///    still missing.
  /// 3. Jikan (no key, anime only): the MyAnimeList score.
  /// 4. Letterboxd's page and Trakt's API, only for what is still missing,
  ///    in parallel.
  ///
  /// Every lookup is cached for [cacheTtl], failures too.
  Future<List<TitleLink>> withFetchedScores(
    List<TitleLink> links, {
    required MediaKind kind,
    required ExternalIds ids,
    String title = '',
    int? year,
    bool isAnime = false,
  }) async {
    final have = <String>{for (final link in links) if (link.rating != null) link.source};
    final found = <String, MediaRatingSource>{};
    bool missing(String source) => !have.contains(source) && !found.containsKey(source);
    void take(ProviderScores scores) {
      scores.ratings.forEach((source, rating) {
        if (missing(source)) found[source] = rating;
      });
    }

    final idKey = '${kind.name}:${ids.tmdb ?? ids.imdb ?? ids.tvdb}';
    final settings = SettingsService.instanceOrNull;
    int? malId;

    final mdbKey = settings?.read(SettingsService.mdblistApiKey).trim() ?? '';
    if (mdbKey.isNotEmpty) {
      final scores = await _cachedScores('mdb:$idKey', () => _mdbList.fetch(apiKey: mdbKey, kind: kind, ids: ids));
      take(scores);
      malId = scores.malId;
    }

    final omdbKey = settings?.read(SettingsService.omdbApiKey).trim() ?? '';
    if (omdbKey.isNotEmpty &&
        (missing('metacritic') || missing('imdb') || missing('rottenTomatoesCritic'))) {
      take(await _cachedScores('omdb:$idKey', () => _omdb.fetch(apiKey: omdbKey, ids: ids)));
    }

    if (isAnime && (settings?.read(SettingsService.jikanRatings) ?? true) && missing('mal')) {
      final scores = await _cachedScores(
        'jikan:${malId ?? '$title:$year'}',
        () => _jikan.fetch(malId: malId, title: title, year: year),
      );
      take(scores);
      malId ??= scores.malId;
    }

    // Letterboxd and Trakt directly, for what the providers left open.
    final result = await Future.wait([
      for (final link in links)
        () async {
          final rating = link.rating ?? found[link.source];
          if (rating != null) return link.withRating(rating);
          switch (link.source) {
            case 'letterboxd':
              final fetched = await _cached('lb:${ids.tmdb ?? ids.imdb}', () => _fetchLetterboxd(link.url));
              return link.withRating(fetched.rating);
            case 'trakt':
              final fetched = await _cached('trakt:$idKey', () => _fetchTrakt(kind, ids));
              final slugUrl = fetched.slug == null ? null : traktUrl(kind: kind, slug: fetched.slug);
              return TitleLink(
                source: link.source,
                siteName: link.siteName,
                url: slugUrl ?? link.url,
                rating: fetched.rating,
              );
            default:
              return link;
          }
        }(),
    ]);

    // Sites the base row has no card for.
    final present = {for (final link in result) link.source};
    final query = Uri.encodeComponent(title);
    for (final MapEntry(key: source, value: rating) in found.entries) {
      if (present.contains(source)) continue;
      final link = switch (source) {
        'metacritic' => TitleLink(
          source: source,
          siteName: 'Metacritic',
          url: Uri.parse('https://www.metacritic.com/search/$query/'),
          rating: rating,
        ),
        'mal' => TitleLink(
          source: source,
          siteName: 'MyAnimeList',
          url: malId != null
              ? Uri.parse('https://myanimelist.net/anime/$malId')
              : Uri.parse('https://myanimelist.net/anime.php?q=$query'),
          rating: rating,
        ),
        'rottenTomatoesAudience' => TitleLink(
          source: source,
          siteName: 'Rotten Tomatoes',
          url: Uri.parse('https://www.rottentomatoes.com/search?search=$query'),
          rating: rating,
        ),
        _ => null,
      };
      if (link != null) result.add(link);
    }
    int order(TitleLink link) {
      final i = siteOrder.indexOf(link.source);
      return i < 0 ? siteOrder.length : i;
    }

    result.sort((a, b) => order(a).compareTo(order(b)));
    return result;
  }

  late final _mdbList = MdbListProvider(_client);
  late final _omdb = OmdbProvider(_client);
  late final _jikan = JikanProvider(_client);
  final Map<String, ({DateTime until, ProviderScores value})> _scoreCache = {};

  Future<ProviderScores> _cachedScores(String key, Future<ProviderScores> Function() load) async {
    final hit = _scoreCache[key];
    if (hit != null && _now().isBefore(hit.until)) return hit.value;
    try {
      final value = await load();
      _scoreCache[key] = (until: _now().add(cacheTtl), value: value);
      return value;
    } on Exception catch (e) {
      // The caller falls back to the direct lookups for this visit.
      appLogger.d('Ratings & links: $key unavailable', error: e);
      _scoreCache[key] = (until: _now().add(failureTtl), value: ProviderScores.empty);
      return ProviderScores.empty;
    }
  }

  Future<_Fetched> _cached(String key, Future<_Fetched> Function() load) async {
    final hit = _cache[key];
    if (hit != null && _now().isBefore(hit.until)) return hit.value;
    try {
      final value = await load();
      _cache[key] = (until: _now().add(cacheTtl), value: value);
      return value;
    } on Exception catch (e) {
      appLogger.d('Ratings & links: $key unavailable', error: e);
      _cache[key] = (until: _now().add(failureTtl), value: const _Fetched());
      return const _Fetched();
    }
  }

  Future<_Fetched> _fetchLetterboxd(Uri url) async {
    final response = await _client
        .get(url, headers: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) PlezyRetrowave'})
        .timeout(const Duration(seconds: 8));
    // 404: no such film page (a real answer). Anything else: unavailable.
    if (response.statusCode == 404) return const _Fetched();
    if (response.statusCode != 200) throw ProviderUnavailable(response.statusCode);
    return _Fetched(rating: parseLetterboxdRating(response.body));
  }

  /// The `aggregateRating` of a Letterboxd film page's JSON-LD, moved onto the
  /// 0-10 scale. Null when the page carries none (too few ratings yet).
  static MediaRatingSource? parseLetterboxdRating(String html) {
    final blocks = RegExp(
      r'<script[^>]*type="application/ld\+json"[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html);
    for (final block in blocks) {
      // Letterboxd wraps the JSON in a CDATA comment.
      final raw = block
          .group(1)!
          .replaceAll(RegExp(r'/\*\s*<!\[CDATA\[\s*\*/'), '')
          .replaceAll(RegExp(r'/\*\s*\]\]>\s*\*/'), '')
          .trim();
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final aggregate = decoded['aggregateRating'];
        if (aggregate is! Map) continue;
        final value = aggregate['ratingValue'];
        final count = aggregate['ratingCount'];
        return MediaRatingSource.fromScale(
          'letterboxd',
          value is num ? value : num.tryParse('$value'),
          scale: 5,
          votes: count is num ? count : num.tryParse('$count'),
        );
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  Future<_Fetched> _fetchTrakt(MediaKind kind, ExternalIds ids) async {
    final type = kind == MediaKind.movie ? 'movie' : 'show';
    final (idType, id) = switch (ids) {
      ExternalIds(:final tmdb?) => ('tmdb', '$tmdb'),
      ExternalIds(:final imdb?) => ('imdb', imdb),
      ExternalIds(:final tvdb?) when kind == MediaKind.show => ('tvdb', '$tvdb'),
      _ => (null, null),
    };
    if (idType == null || id == null) return const _Fetched();

    final search = await _traktGet('/search/$idType/$id?type=$type');
    if (search is! List || search.isEmpty) return const _Fetched();
    final entry = search.first;
    final media = entry is Map ? entry[type] : null;
    final traktIds = media is Map ? media['ids'] : null;
    final slug = traktIds is Map ? traktIds['slug'] as String? : null;
    if (slug == null) return const _Fetched();

    final ratings = await _traktGet('/${type}s/$slug/ratings');
    if (ratings is! Map) return _Fetched(slug: slug);
    final rating = ratings['rating'];
    final votes = ratings['votes'];
    return _Fetched(
      slug: slug,
      rating: MediaRatingSource.fromScale(
        'trakt',
        rating is num ? rating : null,
        scale: 10,
        votes: votes is num ? votes : null,
      ),
    );
  }

  Future<Object?> _traktGet(String path) async {
    final response = await _client
        .get(Uri.parse('${TraktConstants.apiBase}$path'), headers: TraktConstants.headers())
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw ProviderUnavailable(response.statusCode);
    return jsonDecode(response.body);
  }
}

class _Fetched {
  const _Fetched({this.rating, this.slug});

  final MediaRatingSource? rating;
  final String? slug;
}
