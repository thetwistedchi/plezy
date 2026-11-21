import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';

/// Fork: a Tubi title as the website lists it.
class TubiTitle {
  const TubiTitle({
    required this.id,
    required this.title,
    required this.isSeries,
    this.year,
    this.description,
    this.posterUrl,
    this.backdropUrl,
    this.minutes,
    this.imdb,
  });

  /// The website's id: a movie's, or a series' without its leading zeros.
  final String id;
  final String title;
  final bool isSeries;
  final int? year;
  final String? description;
  final String? posterUrl;
  final String? backdropUrl;
  final int? minutes;
  final String? imdb;

  /// Where it plays on the website; `start=true` starts playback.
  String get watchUrl => isSeries ? TubiClient.seriesUrl(id) : 'https://tubitv.com/movies/$id?start=true';
}

class TubiRow {
  const TubiRow(this.title, this.items);
  final String title;
  final List<TubiTitle> items;
}

typedef TubiEpisode = ({String id, int? number, String title, String? summary, int? minutes});
typedef TubiSeason = ({String number, List<TubiEpisode> episodes});

/// Tubi is not offered where the request comes from (outside its countries).
class TubiUnavailableException implements Exception {
  @override
  String toString() => 'Tubi is not available in this region';
}

/// Fork: Tubi's free catalog, read from the data its website pages carry
/// (`window.__data`, `window.__REACT_QUERY_STATE__`). Not an official
/// interface: what it finds and misses is logged.
class TubiClient {
  TubiClient();

  static const _base = 'https://tubitv.com';
  final http.Client _http = http.Client();
  static bool _structureLogged = false;

  static String seriesUrl(String id) => '$_base/series/$id?start=true';
  static String episodeUrl(String id) => '$_base/tv-shows/$id?start=true';

  void dispose() => _http.close();

  Future<String> _html(String path) async {
    final response = await _http
        .get(
          Uri.parse('$_base$path'),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'en-US,en;q=0.8',
          },
        )
        .timeout(const Duration(seconds: 20));
    final finalPath = response.request?.url.path ?? '';
    appLogger.d('Tubi GET $path → ${response.statusCode} ($finalPath, ${response.bodyBytes.length} bytes)');
    if (response.statusCode == 451 ||
        finalPath.contains('unavailable') ||
        finalPath.contains('geo') ||
        response.body.contains('not available in your') ||
        response.body.contains('not available in Europe') ||
        (response.bodyBytes.length < 8000 && response.body.contains('not available'))) {
      throw TubiUnavailableException();
    }
    if (response.statusCode >= 400) throw Exception('Tubi answered ${response.statusCode}');
    return response.body;
  }

  /// The object assigned to `window.<name>` in a page, as JSON.
  static Future<Map<String, dynamic>?> _state(String html, String name) async {
    final start = html.indexOf('window.$name');
    if (start < 0) return null;
    final open = html.indexOf('{', start);
    if (open < 0) return null;
    final text = _balanced(html, open);
    if (text == null) return null;
    final decoded = await compute(_decode, text);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// The `{...}` starting at [open], with JavaScript's `undefined` as `null`.
  static String? _balanced(String s, int open) {
    final out = StringBuffer();
    var depth = 0;
    String? quote;
    for (var i = open; i < s.length; i++) {
      final c = s[i];
      if (quote != null) {
        out.write(c);
        if (c == r'\' && i + 1 < s.length) {
          out.write(s[++i]);
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
        out.write(c);
        continue;
      }
      if (s.startsWith('undefined', i)) {
        out.write('null');
        i += 'undefined'.length - 1;
        continue;
      }
      out.write(c);
      if (c == '{' || c == '[') depth++;
      if (c == '}' || c == ']') {
        depth--;
        if (depth == 0) return out.toString();
      }
    }
    return null;
  }

  static Object? _decode(String text) => jsonDecode(text);

  static String? _url(Object? value) {
    var v = value;
    if (v is List && v.isNotEmpty) v = v.first;
    if (v is Map) v = v['url'] ?? v.values.firstOrNull;
    if (v is! String || v.isEmpty) return null;
    return v.startsWith('//') ? 'https:$v' : v;
  }

  static TubiTitle? _title(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString();
    final title = raw['title']?.toString();
    if (id == null || id.isEmpty || title == null || title.isEmpty) return null;
    final type = raw['type']?.toString();
    // Series carry a leading zero in the website's lists.
    final isSeries = type == 's' || type == 'series' || (id.startsWith('0') && id.length > 1);
    final seconds = int.tryParse('${raw['duration']}');
    return TubiTitle(
      id: isSeries ? id.replaceFirst(RegExp('^0+'), '') : id,
      title: title,
      isSeries: isSeries,
      year: int.tryParse('${raw['year']}'),
      description: raw['description']?.toString(),
      posterUrl: _url(raw['posterarts']) ?? _url(raw['poster_art']) ?? _url(raw['thumbnails']),
      backdropUrl: _url(raw['backgrounds']) ?? _url(raw['hero_images']) ?? _url(raw['landscape_images']),
      minutes: seconds != null && seconds > 0 ? (seconds / 60).round() : null,
      imdb: switch (raw['imdb_id']?.toString()) {
        final String v when v.startsWith('tt') => v,
        _ => null,
      },
    );
  }

  static Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : const {};

  /// Tubi's home rows.
  Future<List<TubiRow>> home() async {
    final html = await _html('/home');
    final data = await _state(html, '__data');
    if (data == null) {
      // What came instead (a check page, a redirect, a notice).
      final text = html.replaceAll(RegExp(r'\s+'), ' ');
      appLogger.w('Tubi page without data: ${text.substring(0, text.length.clamp(0, 1500))}');
      throw Exception('Tubi page carried no data');
    }
    final videos = _map(_map(data['video'])['byId']);
    final container = _map(data['container']);
    if (!_structureLogged) {
      _structureLogged = true;
      final sample = videos.values.whereType<Map>().firstOrNull;
      appLogger.i(
        'Tubi data: ${data.keys.take(30).join(',')} | container: ${container.keys.join(',')} | '
        '${videos.length} videos, fields: ${sample?.keys.take(40).join(',')}',
      );
    }
    final titles = _map(container['containerIdMap']);
    final children = _map(container['containerChildrenIdMap']);
    final order = [
      for (final id in (container['containersList'] as List?) ?? titles.keys.toList()) id.toString(),
    ];
    final rows = <TubiRow>[];
    for (final id in order) {
      final ids = children[id];
      if (ids is! List) continue;
      final items = [
        for (final v in ids)
          if (_title(videos[v.toString()]) case final TubiTitle t) t,
      ];
      if (items.isEmpty) continue;
      rows.add(TubiRow(_map(titles[id])['title']?.toString() ?? id, items));
    }
    if (rows.isEmpty && videos.isNotEmpty) {
      appLogger.w('Tubi: no rows found, showing every title of the page');
      rows.add(TubiRow('Tubi', [for (final v in videos.values) ?_title(v)]));
    }
    return rows;
  }

  /// Search results for [query].
  Future<List<TubiTitle>> search(String query) async {
    final data = await _state(await _html('/search/${Uri.encodeComponent(query)}'), '__data');
    if (data == null) return const [];
    final videos = _map(_map(data['video'])['byId']);
    final search = _map(data['search']);
    // The result ids: the first list in the search state that names videos.
    List<Object?>? ids;
    void find(Object? node, int depth) {
      if (ids != null || depth > 4) return;
      if (node is List && node.isNotEmpty && node.every((e) => videos.containsKey(e.toString()))) {
        ids = node;
      } else if (node is Map) {
        for (final v in node.values) {
          find(v, depth + 1);
        }
      }
    }

    find(search, 0);
    appLogger.d('Tubi search: ${ids?.length ?? 0} results (search keys: ${search.keys.join(',')})');
    final list = ids ?? const [];
    return [for (final id in list) ?_title(videos[id.toString()])];
  }

  /// A series' seasons with their episodes.
  Future<List<TubiSeason>> seasons(String seriesId) async {
    final html = await _html('/series/$seriesId');
    final state = await _state(html, '__REACT_QUERY_STATE__');
    Map<String, dynamic>? withSeasons;
    for (final q in (state?['queries'] as List?) ?? const []) {
      final d = _map(_map(_map(q)['state'])['data']);
      if (d['seasons'] is List && (d['seasons'] as List).isNotEmpty) {
        withSeasons = d;
        break;
      }
    }
    final seasons = <TubiSeason>[];
    for (final s in (withSeasons?['seasons'] as List?) ?? const []) {
      final season = _map(s);
      final episodes = <TubiEpisode>[];
      for (final e in (season['episodes'] as List?) ?? const []) {
        final ep = _map(e);
        final id = ep['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final seconds = int.tryParse('${ep['duration']}');
        final number = int.tryParse('${ep['num'] ?? ep['episode_number']}');
        episodes.add((
          id: id,
          number: number,
          title: (ep['title'] ?? ep['episode_title'])?.toString() ?? 'Episode ${number ?? ''}',
          summary: ep['description']?.toString(),
          minutes: seconds != null && seconds > 0 ? (seconds / 60).round() : null,
        ));
      }
      if (episodes.isNotEmpty) seasons.add((number: '${season['number'] ?? seasons.length + 1}', episodes: episodes));
    }
    appLogger.d('Tubi series $seriesId: ${seasons.length} seasons');
    return seasons;
  }
}
