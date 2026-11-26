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
/// A person is matched by exact name, must be a human with a picture, and is
/// preferred with an IMDb id so the match is someone from film or TV. The
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
  Future<File?> forName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return Future.value();
    return _pending.putIfAbsent(clean.toLowerCase(), () => _resolve(clean));
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

  Future<File?> _resolve(String name) async {
    final dir = await _folder();
    final hash = sha1.convert(utf8.encode(name.toLowerCase())).toString();
    final file = File('${dir.path}${Platform.pathSeparator}$hash.jpg');
    if (await file.exists()) return file;

    final misses = await _loadMisses(dir);
    final missedAt = (misses[hash] as num?)?.toInt();
    if (missedAt != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(missedAt)) < _missMaxAge) {
      return null;
    }

    // One lookup at a time, to be gentle with Wikidata.
    final completer = Completer<File?>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await _fetch(name, file));
      } catch (e) {
        appLogger.d('Person picture lookup failed for $name', error: e);
        completer.complete(null);
      }
    });
    final result = await completer.future;
    if (result == null) {
      misses[hash] = DateTime.now().millisecondsSinceEpoch;
      _missesFile(dir).writeAsString(jsonEncode(misses)).ignore();
    }
    return result;
  }

  Future<File?> _fetch(String name, File target) async {
    final quoted = jsonEncode(name);
    final query =
        'SELECT ?img ?imdb WHERE { '
        'VALUES ?l { $quoted@en $quoted@de $quoted@mul } '
        '?p rdfs:label ?l ; wdt:P31 wd:Q5 ; wdt:P18 ?img . '
        'OPTIONAL { ?p wdt:P345 ?imdb } } LIMIT 6';
    final response = await _client
        .get(
          Uri.https('query.wikidata.org', '/sparql', {'query': query, 'format': 'json'}),
          headers: {'Accept': 'application/sparql-results+json', 'User-Agent': _userAgent},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
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
  const ExternalPersonPicture({super.key, required this.name, required this.fallback, this.fit = BoxFit.cover});

  final String name;
  final Widget fallback;
  final BoxFit fit;

  @override
  State<ExternalPersonPicture> createState() => _ExternalPersonPictureState();
}

class _ExternalPersonPictureState extends State<ExternalPersonPicture> {
  late Future<File?> _file = PersonPictures.instance.forName(widget.name);

  @override
  void didUpdateWidget(ExternalPersonPicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) _file = PersonPictures.instance.forName(widget.name);
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
