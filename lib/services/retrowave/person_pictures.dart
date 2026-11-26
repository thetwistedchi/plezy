import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../utils/app_logger.dart';

/// Fork: pictures of people the server has none for, from Wikidata and
/// Wikimedia Commons (no account or key).
///
/// With the title's IMDb id the person is looked up among that title's cast
/// and crew, which makes the match unique. Otherwise (or if that finds no
/// one) by exact name: a human with a picture, preferably with an IMDb id. The
/// picture is fetched once at 300 px wide and kept on the device; misses are
/// remembered for 30 days.
class PersonPictures {
  PersonPictures._();
  static final instance = PersonPictures._();

  static const _userAgent = 'PlezyRetrowave (https://github.com/thetwistedchi/plezy)';
  static const _missMaxAge = Duration(days: 30);
  static const _width = 300;

  final _client = http.Client();
  final _pending = <String, Future<File?>>{};
  Future<void> _queue = Future.value();
  Directory? _dir;
  Map<String, dynamic>? _misses;

  /// The stored picture for [name], fetched on first use; null if none.
  /// [titleImdb] is the IMDb id (tt…) of a film or show they are in.
  Future<File?> forName(String name, {String? titleImdb}) {
    final clean = name.trim();
    if (clean.isEmpty) return Future.value();
    final title = titleImdb != null && RegExp(r'^tt\d+$').hasMatch(titleImdb) ? titleImdb : null;
    final key = title == null ? clean.toLowerCase() : '${clean.toLowerCase()}|$title';
    return _pending.putIfAbsent(key, () => _resolve(clean, title));
  }

  Future<Directory> _folder() async {
    if (_dir case final dir?) return dir;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}person_pictures');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  File _missesFile(Directory dir) => File('${dir.path}${Platform.pathSeparator}misses.json');

  Future<Map<String, dynamic>> _loadMisses(Directory dir) async {
    if (_misses case final m?) return m;
    try {
      final file = _missesFile(dir);
      if (await file.exists()) {
        return _misses = Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
      }
    } catch (_) {}
    return _misses = {};
  }

  Future<File?> _resolve(String name, String? titleImdb) async {
    final dir = await _folder();
    final hash = sha1.convert(utf8.encode(name.toLowerCase())).toString();
    // A picture found through the title is kept under its own key.
    if (titleImdb != null) {
      final titleHash = sha1.convert(utf8.encode('${name.toLowerCase()}|$titleImdb')).toString();
      final viaTitle = File('${dir.path}${Platform.pathSeparator}$titleHash.jpg');
      if (await viaTitle.exists()) return viaTitle;
      final misses = await _loadMisses(dir);
      final missedAt = (misses[titleHash] as num?)?.toInt();
      final recentMiss =
          missedAt != null && DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(missedAt)) < _missMaxAge;
      if (!recentMiss) {
        final found = await _queued(() => _fetchViaTitle(name, titleImdb, viaTitle));
        if (found != null) return found;
        misses[titleHash] = DateTime.now().millisecondsSinceEpoch;
        _missesFile(dir).writeAsString(jsonEncode(misses)).ignore();
      }
    }
    final file = File('${dir.path}${Platform.pathSeparator}$hash.jpg');
    if (await file.exists()) return file;

    final misses = await _loadMisses(dir);
    final missedAt = (misses[hash] as num?)?.toInt();
    if (missedAt != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(missedAt)) < _missMaxAge) {
      return null;
    }

    final result = await _queued(() => _fetch(name, file));
    if (result == null) {
      misses[hash] = DateTime.now().millisecondsSinceEpoch;
      _missesFile(dir).writeAsString(jsonEncode(misses)).ignore();
    }
    return result;
  }

  /// One lookup at a time, to be gentle with Wikidata.
  Future<File?> _queued(Future<File?> Function() lookup) {
    final completer = Completer<File?>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await lookup());
      } catch (e) {
        appLogger.d('Person picture lookup failed', error: e);
        completer.complete(null);
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>?> _sparql(String query) async {
    final response = await _client
        .get(
          Uri.https('query.wikidata.org', '/sparql', {'query': query, 'format': 'json'}),
          headers: {'Accept': 'application/sparql-results+json', 'User-Agent': _userAgent},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// The person among the title's cast (P161), directors (P57),
  /// screenwriters (P58), producers (P162) and voice actors (P725).
  Future<File?> _fetchViaTitle(String name, String titleImdb, File target) async {
    final quoted = jsonEncode(name);
    final query =
        'SELECT ?img WHERE { ?t wdt:P345 "$titleImdb" . '
        '?t wdt:P161|wdt:P57|wdt:P58|wdt:P162|wdt:P725 ?p . '
        'VALUES ?l { $quoted@en $quoted@de $quoted@mul } ?p rdfs:label ?l ; wdt:P18 ?img . } LIMIT 1';
    final json = await _sparql(query);
    final bindings = ((json?['results'] as Map?)?['bindings'] as List? ?? const []).whereType<Map>();
    final image = bindings.map((b) => (b['img'] as Map?)?['value'] as String?).nonNulls.firstOrNull;
    return image == null ? null : _download(image, target);
  }

  Future<File?> _fetch(String name, File target) async {
    final quoted = jsonEncode(name);
    final query =
        'SELECT ?img ?imdb WHERE { '
        'VALUES ?l { $quoted@en $quoted@de $quoted@mul } '
        '?p rdfs:label ?l ; wdt:P31 wd:Q5 ; wdt:P18 ?img . '
        'OPTIONAL { ?p wdt:P345 ?imdb } } LIMIT 6';
    final json = await _sparql(query);
    if (json == null) return null;
    final bindings = ((json['results'] as Map?)?['bindings'] as List? ?? const []).whereType<Map>().toList();
    String? image;
    final people = <String>{};
    for (final b in bindings) {
      final img = (b['img'] as Map?)?['value'] as String?;
      if (img == null) continue;
      people.add(img);
      final imdb = (b['imdb'] as Map?)?['value'] as String?;
      if (imdb != null && imdb.startsWith('nm')) {
        image = img;
        break;
      }
    }
    // Without an IMDb id, only a single unambiguous match is trusted.
    image ??= people.length == 1 ? people.first : null;
    if (image == null) return null;
    return _download(image, target);
  }

  Future<File?> _download(String image, File target) async {
    final uri = Uri.parse(image.replaceFirst('http://', 'https://'));
    final sized = uri.replace(queryParameters: {...uri.queryParameters, 'width': '$_width'});
    final picture = await _client
        .get(sized, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    final type = picture.headers['content-type'] ?? '';
    if (picture.statusCode != 200 || !type.startsWith('image/') || picture.bodyBytes.isEmpty) return null;
    await target.writeAsBytes(picture.bodyBytes, flush: true);
    return target;
  }
}

/// A person's picture from [PersonPictures], or [fallback] while it loads
/// and when there is none.
class ExternalPersonPicture extends StatefulWidget {
  const ExternalPersonPicture({
    super.key,
    required this.name,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.titleImdb,
  });

  final String name;

  /// IMDb id of a title the person is in, for an exact match.
  final String? titleImdb;
  final Widget fallback;
  final BoxFit fit;

  @override
  State<ExternalPersonPicture> createState() => _ExternalPersonPictureState();
}

class _ExternalPersonPictureState extends State<ExternalPersonPicture> {
  late Future<File?> _file = PersonPictures.instance.forName(widget.name, titleImdb: widget.titleImdb);

  @override
  void didUpdateWidget(ExternalPersonPicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name || oldWidget.titleImdb != widget.titleImdb) {
      _file = PersonPictures.instance.forName(widget.name, titleImdb: widget.titleImdb);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snapshot) {
      final file = snapshot.data;
      if (file == null) return widget.fallback;
      return Image.file(
        file,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => widget.fallback,
      );
    },
  );
}
