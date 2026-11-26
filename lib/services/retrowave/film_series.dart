import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/strings.g.dart';
import '../../utils/app_logger.dart';

/// One film of a series, in the series' order.
class FilmSeriesPart {
  const FilmSeriesPart({required this.title, this.imdb, this.year, this.ordinal});

  final String title;
  final String? imdb;
  final int? year;
  final double? ordinal;

  Map<String, Object?> toJson() => {'t': title, 'i': imdb, 'y': year, 'o': ordinal};

  static FilmSeriesPart fromJson(Map<String, dynamic> j) => FilmSeriesPart(
    title: j['t'] as String? ?? '',
    imdb: j['i'] as String?,
    year: (j['y'] as num?)?.toInt(),
    ordinal: (j['o'] as num?)?.toDouble(),
  );
}

/// Fork: the film series a movie belongs to (Wikidata "part of the series",
/// P179) with every part, so the details page can show which are missing
/// from the library. Cached on the device for 30 days (misses for 7).
class FilmSeries {
  FilmSeries._();
  static final instance = FilmSeries._();

  static const _cacheKey = 'retrowave_film_series_v1';
  static const _userAgent = 'PlezyRetrowave/1.0 (https://github.com/thetwistedchi/plezy)';
  final _inFlight = <String, Future<({String name, List<FilmSeriesPart> parts})?>>{};

  Future<({String name, List<FilmSeriesPart> parts})?> lookup(String imdb) {
    return _inFlight[imdb] ??= _lookup(imdb).whenComplete(() {
      _inFlight.remove(imdb);
    });
  }

  Future<({String name, List<FilmSeriesPart> parts})?> _lookup(String imdb) async {
    final prefs = await SharedPreferences.getInstance();
    final lang = LocaleSettings.currentLocale.languageCode;
    final cacheId = '$lang:$imdb';
    Map<String, dynamic> cache;
    try {
      cache = jsonDecode(prefs.getString(_cacheKey) ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      cache = {};
    }
    final hit = cache[cacheId];
    if (hit is Map<String, dynamic>) {
      final at = DateTime.fromMillisecondsSinceEpoch((hit['at'] as num?)?.toInt() ?? 0);
      final name = hit['name'] as String?;
      final maxAge = name == null ? const Duration(days: 7) : const Duration(days: 30);
      if (DateTime.now().difference(at) < maxAge) {
        if (name == null) return null;
        return (
          name: name,
          parts: [for (final p in (hit['parts'] as List? ?? const [])) FilmSeriesPart.fromJson(p as Map<String, dynamic>)],
        );
      }
    }

    final id = imdb.replaceAll('"', '');
    final query =
        'SELECT ?s ?sLabel ?m ?mLabel ?imdb ?date ?ord WHERE { '
        '?film wdt:P345 "$id" ; wdt:P179 ?s . '
        '?m wdt:P179 ?s . '
        'VALUES ?type { wd:Q11424 wd:Q24869 wd:Q506240 wd:Q202866 wd:Q24862 } ?m wdt:P31 ?type . '
        'OPTIONAL { ?m wdt:P345 ?imdb } OPTIONAL { ?m wdt:P577 ?date } '
        'OPTIONAL { ?m p:P179 ?st . ?st ps:P179 ?s ; pq:P1545 ?ord } '
        'SERVICE wikibase:label { bd:serviceParam wikibase:language "$lang,en". } } LIMIT 200';
    ({String name, List<FilmSeriesPart> parts})? result;
    try {
      final response = await http
          .get(
            Uri.https('query.wikidata.org', '/sparql', {'query': query, 'format': 'json'}),
            headers: {'Accept': 'application/sparql-results+json', 'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw Exception('Wikidata ${response.statusCode}');
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final rows = ((json['results'] as Map?)?['bindings'] as List? ?? const []).whereType<Map>();
      String? value(Map row, String key) => (row[key] as Map?)?['value'] as String?;
      // A film can sit in several series (a trilogy and a wider franchise);
      // the smallest one is the closest.
      final bySeries = <String, Map<String, FilmSeriesPart>>{};
      final names = <String, String>{};
      for (final row in rows) {
        final series = value(row, 's');
        final film = value(row, 'm');
        if (series == null || film == null) continue;
        names[series] = value(row, 'sLabel') ?? '';
        final parts = bySeries.putIfAbsent(series, () => {});
        final date = value(row, 'date');
        parts[film] = FilmSeriesPart(
          title: value(row, 'mLabel') ?? '',
          imdb: value(row, 'imdb') ?? parts[film]?.imdb,
          year: date != null && date.length >= 4 ? int.tryParse(date.substring(0, 4)) : parts[film]?.year,
          ordinal: double.tryParse(value(row, 'ord') ?? '') ?? parts[film]?.ordinal,
        );
      }
      final candidates = bySeries.entries.where((e) => e.value.length >= 2).toList()
        ..sort((a, b) => a.value.length.compareTo(b.value.length));
      if (candidates.isNotEmpty) {
        final pick = candidates.first;
        final parts = pick.value.values.where((p) => p.title.isNotEmpty && !RegExp(r'^Q\d+$').hasMatch(p.title)).toList()
          ..sort((a, b) {
            final o = (a.ordinal ?? 1e9).compareTo(b.ordinal ?? 1e9);
            return o != 0 ? o : (a.year ?? 9999).compareTo(b.year ?? 9999);
          });
        if (parts.length >= 2) result = (name: names[pick.key] ?? '', parts: parts);
      }
    } catch (e) {
      appLogger.d('Film series lookup failed for $imdb', error: e);
      return null;
    }
    cache[cacheId] = {
      'at': DateTime.now().millisecondsSinceEpoch,
      'name': result?.name,
      if (result != null) 'parts': [for (final p in result.parts) p.toJson()],
    };
    if (cache.length > 800) cache.remove(cache.keys.first);
    await prefs.setString(_cacheKey, jsonEncode(cache));
    return result;
  }
}
