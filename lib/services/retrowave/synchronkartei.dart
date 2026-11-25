import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';

/// German voice actors of a film or series from the Deutsche Synchronkartei.
class DubCast {
  const DubCast({required this.page, required this.voices});

  /// The title's page on synchronkartei.de.
  final Uri page;

  /// Normalized actor name (see [Synchronkartei.normalize]) to the German
  /// voice actor.
  final Map<String, String> voices;

  String? voiceFor(String actor) => voices[Synchronkartei.normalize(actor)];

  Map<String, Object> toJson() => {'page': page.toString(), 'voices': voices};

  static DubCast? fromJson(Object? json) {
    if (json is! Map) return null;
    final page = Uri.tryParse('${json['page']}');
    final voices = json['voices'];
    if (page == null || voices is! Map) return null;
    return DubCast(page: page, voices: {for (final e in voices.entries) '${e.key}': '${e.value}'});
  }
}

/// Fork: looks up the German dub cast of a title.
///
/// The title's Synchronkartei id comes from Wikidata by IMDb (or TMDB) id, so
/// no name search is needed; then the title page is read once. Results, and
/// titles without an entry, are cached on the device so a title is fetched
/// at most once every few weeks.
class Synchronkartei {
  Synchronkartei._();
  static final instance = Synchronkartei._();

  static const _prefsKey = 'retrowave_synchronkartei_v1';
  static const _maxEntries = 400;
  static const _hitTtl = Duration(days: 30);
  static const _missTtl = Duration(days: 7);
  static const _userAgent = 'PlezyRetrowave (https://github.com/thetwistedchi/plezy)';

  final _client = http.Client();
  final _inFlight = <String, Future<DubCast?>>{};
  Map<String, dynamic>? _cache;

  /// Lowercase letters and digits only, accents folded.
  static String normalize(String name) {
    const from = 'àáâãäåçèéêëìíîïñòóôõöøùúûüýÿōūāēī';
    const to = 'aaaaaaceeeeiiiinoooooouuuuyyouaei';
    final buffer = StringBuffer();
    for (final rune in name.toLowerCase().runes) {
      var c = String.fromCharCode(rune);
      final i = from.indexOf(c);
      if (i >= 0) c = to[i];
      if (c == 'ß') c = 'ss';
      if (RegExp(r'[a-z0-9]').hasMatch(c) || c == 'ss') buffer.write(c);
    }
    return buffer.toString();
  }

  Future<DubCast?> lookup(ExternalIds ids, {required bool isShow}) {
    final key = ids.imdb != null
        ? ids.imdb!
        : ids.tmdb != null
        ? '${isShow ? 'tv' : 'movie'}:${ids.tmdb}'
        : null;
    if (key == null) return Future.value();
    return _inFlight.putIfAbsent(key, () => _lookup(key, ids, isShow).whenComplete(() => _inFlight.remove(key)));
  }

  Future<DubCast?> _lookup(String key, ExternalIds ids, bool isShow) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = _cache ??= _readCache(prefs);
    final cached = cache[key];
    if (cached is Map) {
      final at = DateTime.fromMillisecondsSinceEpoch((cached['at'] as num?)?.toInt() ?? 0);
      final cast = DubCast.fromJson(cached['cast']);
      final ttl = cast == null ? _missTtl : _hitTtl;
      if (DateTime.now().difference(at) < ttl) return cast;
    }
    DubCast? cast;
    try {
      final page = await _pageFor(ids, isShow);
      if (page != null) cast = await _readPage(page);
    } catch (e) {
      // Offline or a site change: try again next time, keep the old entry.
      appLogger.d('Synchronkartei lookup failed for $key', error: e);
      return cached is Map ? DubCast.fromJson(cached['cast']) : null;
    }
    cache[key] = {'at': DateTime.now().millisecondsSinceEpoch, 'cast': ?cast?.toJson()};
    if (cache.length > _maxEntries) {
      final oldest = cache.entries.toList()
        ..sort((a, b) => ((a.value as Map)['at'] as num).compareTo((b.value as Map)['at'] as num));
      for (final e in oldest.take(cache.length - _maxEntries)) {
        cache.remove(e.key);
      }
    }
    await prefs.setString(_prefsKey, jsonEncode(cache));
    return cast;
  }

  Map<String, dynamic> _readCache(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_prefsKey);
      if (raw != null) return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    return {};
  }

  /// The title's synchronkartei.de page, from Wikidata.
  Future<Uri?> _pageFor(ExternalIds ids, bool isShow) async {
    final String match;
    if (ids.imdb != null) {
      match = '?i wdt:P345 "${ids.imdb!.replaceAll('"', '')}" .';
    } else {
      // TMDB movie id (P4947) or TV series id (P4983).
      match = '?i wdt:${isShow ? 'P4983' : 'P4947'} "${ids.tmdb}" .';
    }
    final query = 'SELECT ?f ?s WHERE { $match OPTIONAL { ?i wdt:P3844 ?f } OPTIONAL { ?i wdt:P4834 ?s } } LIMIT 5';
    final response = await _client
        .get(
          Uri.https('query.wikidata.org', '/sparql', {'query': query, 'format': 'json'}),
          headers: {'Accept': 'application/sparql-results+json', 'User-Agent': _userAgent},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Wikidata ${response.statusCode}');
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final bindings = (json['results'] as Map?)?['bindings'] as List? ?? const [];
    String? film;
    String? series;
    for (final b in bindings.whereType<Map>()) {
      film ??= (b['f'] as Map?)?['value'] as String?;
      series ??= (b['s'] as Map?)?['value'] as String?;
    }
    final preferSeries = isShow ? series ?? film : null;
    if (preferSeries != null) {
      return Uri.https('www.synchronkartei.de', '/${series != null ? 'serie' : 'film'}/$preferSeries');
    }
    if (film != null) return Uri.https('www.synchronkartei.de', '/film/$film');
    if (series != null) return Uri.https('www.synchronkartei.de', '/serie/$series');
    return null;
  }

  static final _personLink = RegExp(
    r'''<a\b[^>]*href=["'][^"']*/person/[^/"']+/(darsteller|sprecher)["'][^>]*>(.*?)</a>''',
    caseSensitive: false,
    dotAll: true,
  );

  /// Pairs each actor link on the page with the next voice actor link.
  Future<DubCast?> _readPage(Uri page) async {
    final response = await _client
        .get(page, headers: {'User-Agent': _userAgent, 'Accept-Language': 'de'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw Exception('Synchronkartei ${response.statusCode}');
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final voices = <String, String>{};
    String? actor;
    for (final m in _personLink.allMatches(html)) {
      final name = _text(m.group(2)!);
      if (name.isEmpty) continue;
      if (m.group(1)!.toLowerCase() == 'darsteller') {
        actor = name;
      } else if (actor != null) {
        voices.putIfAbsent(normalize(actor), () => name);
        actor = null;
      }
    }
    if (voices.isEmpty) return null;
    return DubCast(page: page, voices: voices);
  }

  static String _text(String html) {
    final stripped = html.replaceAll(RegExp(r'<[^>]*>'), '');
    return stripped
        .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
          final code = int.tryParse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16);
          return code == null ? m.group(0)! : String.fromCharCode(code);
        })
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
