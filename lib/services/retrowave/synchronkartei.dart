import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';

/// German voice actors of a film or series.
class DubCast {
  const DubCast({required this.page, required this.voices});

  /// Where the voices come from (synchronkartei.de or German Wikipedia).
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
/// Wikidata maps the title's IMDb (or TMDB) id to its Deutsche Synchronkartei
/// page and its German Wikipedia article, so no name search is needed. The
/// Synchronkartei cast table is read first; without one, the "Synchronisation"
/// section of the Wikipedia article. Results, and titles without voices, are
/// cached on the device.
class Synchronkartei {
  Synchronkartei._();
  static final instance = Synchronkartei._();

  static const _prefsKey = 'retrowave_synchronkartei_v3';
  static const _maxEntries = 400;
  static const _hitTtl = Duration(days: 30);
  static const _missTtl = Duration(days: 3);
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
      if (c == 'ss' || RegExp(r'[a-z0-9]').hasMatch(c)) buffer.write(c);
    }
    return buffer.toString();
  }

  Future<DubCast?> lookup(ExternalIds ids, {required bool isShow, String? title, int? year}) {
    final key = ids.imdb != null
        ? ids.imdb!
        : ids.tmdb != null
        ? '${isShow ? 'tv' : 'movie'}:${ids.tmdb}'
        : null;
    if (key == null) {
      appLogger.i('Synchronkartei: no IMDb or TMDB id for "$title"');
      return Future.value();
    }
    // The block body matters: `=> _inFlight.remove(key)` would hand back the
    // removed future itself, and whenComplete would wait on it forever.
    return _inFlight.putIfAbsent(
      key,
      () => _lookup(key, ids, isShow).whenComplete(() {
        _inFlight.remove(key);
      }),
    );
  }

  Future<DubCast?> _lookup(String key, ExternalIds ids, bool isShow) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = _cache ??= _readCache(prefs);
    final cached = cache[key];
    if (cached is Map) {
      final at = DateTime.fromMillisecondsSinceEpoch((cached['at'] as num?)?.toInt() ?? 0);
      final cast = DubCast.fromJson(cached['cast']);
      final ttl = cast == null ? _missTtl : _hitTtl;
      if (DateTime.now().difference(at) < ttl) {
        appLogger.i('Synchronkartei: $key from cache (${cast?.voices.length ?? 0} voices)');
        return cast;
      }
    }
    appLogger.i('Synchronkartei: looking up $key');
    final watch = Stopwatch()..start();
    DubCast? cast;
    var failed = false;
    ({Uri? synchronkartei, String? dewiki}) links;
    try {
      links = await _linksFor(ids, isShow);
      appLogger.i('Synchronkartei: Wikidata answered in ${watch.elapsedMilliseconds} ms');
    } catch (e) {
      // Offline: try again next time, keep the old entry.
      appLogger.w('Synchronkartei: Wikidata lookup failed for $key', error: e);
      return cached is Map ? DubCast.fromJson(cached['cast']) : null;
    }
    final page = links.synchronkartei;
    if (page != null) {
      try {
        cast = await _readPage(page);
        appLogger.i('Synchronkartei: $page gave ${cast?.voices.length ?? 0} voices after ${watch.elapsedMilliseconds} ms');
      } catch (e) {
        failed = true;
        appLogger.w('Synchronkartei: reading $page failed', error: e);
      }
    } else {
      appLogger.i('Synchronkartei: Wikidata has no Synchronkartei link for $key');
    }
    final article = links.dewiki;
    if (cast == null && article != null) {
      try {
        cast = await _readWikipedia(article);
        appLogger.i('Synchronkartei: German Wikipedia "$article" gave ${cast?.voices.length ?? 0} voices');
      } catch (e) {
        failed = true;
        appLogger.w('Synchronkartei: reading Wikipedia "$article" failed', error: e);
      }
    } else if (cast == null) {
      appLogger.i('Synchronkartei: no German Wikipedia article for $key');
    }
    // A failed request is not remembered as "no voices".
    if (cast == null && failed) return null;
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

  /// The title's synchronkartei.de page and German Wikipedia article title,
  /// from Wikidata.
  Future<({Uri? synchronkartei, String? dewiki})> _linksFor(ExternalIds ids, bool isShow) async {
    final String match;
    if (ids.imdb != null) {
      match = '?i wdt:P345 "${ids.imdb!.replaceAll('"', '')}" .';
    } else {
      // TMDB movie id (P4947) or TV series id (P4983).
      match = '?i wdt:${isShow ? 'P4983' : 'P4947'} "${ids.tmdb}" .';
    }
    final query =
        'SELECT ?f ?s ?w WHERE { $match '
        'OPTIONAL { ?i wdt:P3844 ?f } OPTIONAL { ?i wdt:P4834 ?s } '
        'OPTIONAL { ?a schema:about ?i ; schema:isPartOf <https://de.wikipedia.org/> ; schema:name ?w } } LIMIT 5';
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
    String? wiki;
    for (final b in bindings.whereType<Map>()) {
      film ??= (b['f'] as Map?)?['value'] as String?;
      series ??= (b['s'] as Map?)?['value'] as String?;
      wiki ??= (b['w'] as Map?)?['value'] as String?;
    }
    if (bindings.isEmpty) appLogger.i('Synchronkartei: title not on Wikidata');
    Uri? page;
    if (isShow && series != null) {
      page = Uri.https('www.synchronkartei.de', '/serie/$series');
    } else if (film != null) {
      page = Uri.https('www.synchronkartei.de', '/film/$film');
    } else if (series != null) {
      page = Uri.https('www.synchronkartei.de', '/serie/$series');
    }
    return (synchronkartei: page, dewiki: wiki);
  }

  static final _row = RegExp(r'<tr\b[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
  static final _cell = RegExp(r'<td\b[^>]*>(.*?)</td>', caseSensitive: false, dotAll: true);
  static final _personLink = RegExp(
    r'''<a\b[^>]*href=["'][^"']*/person/[^/"']+/(darsteller|sprecher)["'][^>]*>(.*?)</a>''',
    caseSensitive: false,
    dotAll: true,
  );

  /// Reads the cast table (Darsteller | Sprecher | Rolle). Actors without an
  /// entry of their own are shown in parentheses; those count too.
  Future<DubCast?> _readPage(Uri page) async {
    final response = await _client
        .get(
          page,
          headers: {
            // The site answers plain HTTP clients differently than browsers.
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/130.0 Safari/537.36 PlezyRetrowave',
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'de-DE,de;q=0.9',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw Exception('Synchronkartei ${response.statusCode}');
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final voices = <String, String>{};
    for (final row in _row.allMatches(html)) {
      final cells = _cell.allMatches(row.group(1)!).map((m) => m.group(1)!).toList();
      if (cells.length < 2) continue;
      final actor = _stripParens(_text(cells[0]));
      final voice = _text(cells[1]);
      if (actor.isEmpty || voice.isEmpty) continue;
      voices.putIfAbsent(normalize(actor), () => voice);
    }
    if (voices.isEmpty) {
      // No table rows: pair each actor link with the next voice link.
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
    }
    if (voices.isEmpty) return null;
    return DubCast(page: page, voices: voices);
  }

  static String _stripParens(String name) {
    final t = name.trim();
    if (t.startsWith('(') && t.endsWith(')')) return t.substring(1, t.length - 1).trim();
    return t;
  }

  static final _heading = RegExp(
    r'^(=+)\s*(Synchronisation|Synchronisation und Besetzung|Deutsche Fassung|Synchronfassung)\s*\1\s*$',
    multiLine: true,
  );

  /// Fallback: the "Synchronisation" section of the German Wikipedia article,
  /// as a table (Darsteller and Synchronsprecher columns) or a list
  /// ("Actor (Role): Voice").
  Future<DubCast?> _readWikipedia(String article) async {
    final response = await _client
        .get(
          Uri.https('de.wikipedia.org', '/w/api.php', {
            'action': 'parse',
            'page': article,
            'prop': 'wikitext',
            'format': 'json',
            'formatversion': '2',
            'redirects': '1',
          }),
          headers: {'User-Agent': _userAgent},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Wikipedia ${response.statusCode}');
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final wikitext = (json['parse'] as Map?)?['wikitext'] as String?;
    if (wikitext == null) return null;
    final heading = _heading.firstMatch(wikitext);
    if (heading == null) return null;
    final level = heading.group(1)!.length;
    final rest = wikitext.substring(heading.end);
    final next = RegExp('^={1,$level}[^=]', multiLine: true).firstMatch(rest);
    final section = next == null ? rest : rest.substring(0, next.start);
    final voices = <String, String>{};

    // Table: a header row of "!" cells, rows split by "|-".
    final table = RegExp(r'\{\|(.*?)\n\|\}', dotAll: true).firstMatch(section);
    if (table != null) {
      int? actorCol;
      int? voiceCol;
      for (final rowText in table.group(1)!.split(RegExp(r'\n\|-[^\n]*'))) {
        final lines = rowText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
        if (lines.any((l) => l.startsWith('!'))) {
          final headers = [
            for (final l in lines.where((l) => l.startsWith('!')))
              ...l.substring(1).split('!!').map((h) => _wikiText(_afterAttributes(h)).toLowerCase()),
          ];
          for (var i = 0; i < headers.length; i++) {
            final h = headers[i];
            if (h.contains('darsteller') || h.contains('schauspieler')) actorCol ??= i;
            if (h.contains('sprecher') || h.contains('stimme') || h.contains('synchron')) voiceCol ??= i;
          }
          continue;
        }
        final a = actorCol;
        final v = voiceCol;
        if (a == null || v == null) continue;
        final cells = [
          for (final l in lines.where((l) => l.startsWith('|') && !l.startsWith('|+')))
            ...l.substring(1).split('||').map((c) => _wikiText(_afterAttributes(c))),
        ];
        if (cells.length <= a || cells.length <= v) continue;
        final actor = cells[a];
        final voice = cells[v];
        if (actor.isNotEmpty && voice.isNotEmpty) voices.putIfAbsent(normalize(actor), () => voice);
      }
    }

    // List: "* Actor (Role): Voice" or "* Actor: Voice".
    if (voices.isEmpty) {
      final entry = RegExp(r'^(.+?)(?:\s*\([^)]*\))?\s*[:–]\s*(.+)$');
      for (final line in section.split('\n')) {
        if (!line.startsWith('*')) continue;
        final text = _wikiText(line.replaceFirst(RegExp(r'^\*+'), ''));
        final m = entry.firstMatch(text);
        if (m == null) continue;
        final left = m.group(1)!.trim();
        final right = m.group(2)!.trim();
        if (left.isEmpty || right.isEmpty) continue;
        // Articles write either "Actor: Voice" or "Voice: Actor als Role";
        // both directions are kept, only the cast's names will match.
        voices.putIfAbsent(normalize(left), () => right.split(RegExp(r'\s+als\s+')).first.trim());
        voices.putIfAbsent(normalize(right.split(RegExp(r'\s+als\s+')).first), () => left);
      }
    }
    if (voices.isEmpty) return null;
    return DubCast(
      page: Uri(
        scheme: 'https',
        host: 'de.wikipedia.org',
        path: '/wiki/${article.replaceAll(' ', '_')}',
        fragment: 'Synchronisation',
      ),
      voices: voices,
    );
  }

  /// Cell text after an optional `style="..." |` attribute prefix.
  static String _afterAttributes(String cell) {
    final bar = cell.indexOf('|');
    if (bar < 0) return cell;
    final before = cell.substring(0, bar);
    if (before.contains('[[') || before.contains('{{')) return cell;
    return before.contains('=') ? cell.substring(bar + 1) : cell;
  }

  static final _wikiLink = RegExp(r'\[\[(?:[^|\]]*\|)?([^\]]*)\]\]');

  /// Plain text from wiki markup: links, templates, references, bold/italic.
  static String _wikiText(String markup) {
    final t = markup
        .replaceAll(RegExp(r'<ref[^>]*/>'), '')
        .replaceAll(RegExp(r'<ref[^>]*>.*?</ref>', dotAll: true), '')
        .replaceAll(RegExp(r'\{\{[^{}]*\}\}'), '')
        .replaceAllMapped(_wikiLink, (m) => m.group(1)!)
        .replaceAll(RegExp("'{2,}"), '');
    return _text(t);
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
