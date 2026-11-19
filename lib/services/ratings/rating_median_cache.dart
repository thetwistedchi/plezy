import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pathlib;
import 'package:path_provider/path_provider.dart';

import 'package:http/http.dart' as http;

import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_rating.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import '../poster_info_cache.dart' show fetchItemLight;
import '../../utils/platform_detector.dart';
import '../../utils/rating_median.dart';
import 'rating_keys.dart';
import 'rating_providers.dart';

/// Rating medians for posters, kept on disk across sessions.
///
/// Library listings carry at most two scores per title (often only the
/// Tomatometer, which the median leaves out), so posters get their median
/// from here:
/// - a details page stores the full median of its Ratings & links row;
/// - posters without one ask the title's own Plex server for the item
///   (IMDb, Rotten Tomatoes, TMDB). That is the user's server, not an outside
///   site: a few at a time, newest request first, each title once a fortnight.
class RatingMedianCache extends ChangeNotifier {
  RatingMedianCache._();
  static final instance = RatingMedianCache._();

  static const _maxEntries = 8000;
  /// One at a time on TV boxes, whose CPU also decodes every response.
  static int get _maxConcurrent => PlatformDetector.isTV() ? 1 : 3;
  static const _maxQueued = 120;

  /// A median from a details page is kept longer than one from the server
  /// alone, which it also replaces.
  static const _detailTtl = Duration(days: 30);
  static const _serverTtl = Duration(days: 14);

  final Map<String, _Entry> _entries = {};
  final List<({_Target target, MediaServerClient client})> _queue = [];
  final Set<String> _pending = {};
  int _running = 0;
  Future<void>? _loading;
  Timer? _saveTimer;
  Timer? _notifyTimer;

  Future<void> _load() => _loading ??= () async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      final now = DateTime.now();
      for (final e in json.entries) {
        final v = e.value;
        if (v is! List || v.length != 4) continue;
        final entry = _Entry((v[0] as num).toInt(), (v[1] as num).toInt(), v[2] == 1, DateTime.fromMillisecondsSinceEpoch((v[3] as num).toInt()));
        if (!entry.expired(now)) _entries['${e.key}'] = entry;
      }
      _notify();
    } catch (e) {
      appLogger.d('Rating median cache not loaded: $e');
    }
  }();

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(pathlib.join(dir.path, 'rating_medians_v2.json'));
  }

  /// The cached median for [item], if any. Starts loading the cache file on
  /// first use (listeners hear when it is in).
  ({int score, int sources})? medianFor(MediaItem item) => _medianForKey(_Target.of(item).key);

  ({int score, int sources})? _medianForKey(String key) {
    unawaited(_load());
    final entry = _entries[key];
    if (entry == null || entry.score < 0 || entry.expired(DateTime.now())) return null;
    return (score: entry.score, sources: entry.sources);
  }

  /// A details page's median of every source.
  void storeFromDetail(MediaItem item, ({int score, int sources})? median) {
    if (median == null) return;
    final key = _Target.of(item).key;
    final old = _entries[key];
    if (old != null && old.fromDetail && old.score == median.score && old.sources == median.sources) return;
    _put(key, _Entry(median.score, median.sources, true, DateTime.now()));
  }

  final Set<String> _noClientLogged = {};
  final Set<String> _requestLogged = {};

  /// Diagnostics: a poster had no server client to ask (logged once each).
  void noteNoClient(MediaItem item) {
    if (_noClientLogged.length < 200 && _noClientLogged.add(item.globalKey)) {
      appLogger.d('Rating median: no server for "${item.title}" (serverId: ${item.serverId})');
    }
  }

  /// Asks [client] for [item]'s scores when no median is cached yet and the
  /// listing's own scores are too few ([listingSources]).
  void request(MediaItem item, MediaServerClient client, {required int listingSources}) {
    final target = _Target.of(item);
    // A season's or episode's own listing scores are not the series'.
    if (listingSources >= 2 && !target.isSeries) return;
    final key = target.key;
    if (_requestLogged.length < 200 && _requestLogged.add(key)) {
      appLogger.d('Rating median: queued "${target.title}" (${item.kind.name}, listing sources: $listingSources)');
    }
    if (_pending.contains(key)) return;
    unawaited(
      _load().then((_) {
        if (_entries[key]?.expired(DateTime.now()) == false || _pending.contains(key)) return;
        _pending.add(key);
        _queue.add((target: target, client: client));
        // Newest first: what is on screen now. The oldest requests are
        // dropped once the user has scrolled far past them.
        while (_queue.length > _maxQueued) {
          _pending.remove(_queue.removeAt(0).target.key);
        }
        _pump();
      }),
    );
  }

  void _pump() {
    while (_running < _maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeLast();
      _running++;
      unawaited(
        _fetch(job.target, job.client).whenComplete(() {
          _running--;
          _pending.remove(job.target.key);
          _pump();
        }),
      );
    }
  }

  Future<void> _fetch(_Target item, MediaServerClient client) async {
    final key = item.key;
    try {
      final full = await fetchItemLight(client, item.id).timeout(const Duration(seconds: 10));
      final ratings = <String, MediaRatingSource>{
        for (final rating in [...?full?.ratings, ...item.listingRatings]) rating.source: rating,
      };
      var median = ratingMedian(ratings.values);
      // Too few scores on the server (often only the Tomatometer): MDBList,
      // when the user has a key for it.
      if ((median?.sources ?? 0) < 2) {
        final mdbKey = await _mdbListKey();
        if (mdbKey.isNotEmpty) {
          try {
            final ids = await client.fetchExternalIds(item.id).timeout(const Duration(seconds: 10));
            final scores = await _mdbList.fetch(apiKey: mdbKey, kind: full?.kind ?? item.kind, ids: ids);
            for (final rating in scores.ratings.values) {
              ratings.putIfAbsent(rating.source, () => rating);
            }
            median = ratingMedian(ratings.values);
          } catch (e) {
            appLogger.d('Rating median: MDBList for ${item.id} unavailable: $e');
          }
        }
      }
      appLogger.d(
        'Rating median for "${item.title}": ${median?.score ?? 'none'} '
        '(sources: ${ratings.keys.join(', ')})',
      );
      // No score at all is remembered too, for two days, so the title is not
      // asked again on every scroll.
      _put(
        key,
        _Entry(median?.score ?? -1, median?.sources ?? 0, false, median == null ? DateTime.now().subtract(_serverTtl - const Duration(days: 2)) : DateTime.now()),
      );
    } catch (e) {
      appLogger.d('Rating median for ${item.id} unavailable: $e');
    }
  }

  late final _mdbList = MdbListProvider(http.Client());

  static Future<String> _mdbListKey() async {
    final keys = RatingKeys.instance;
    await keys.load();
    return keys.status(RatingKeys.mdblist) == RatingKeyStatus.rejected ? '' : keys.key(RatingKeys.mdblist);
  }

  void _put(String key, _Entry entry) {
    final old = _entries[key];
    // A details page's median wins over the server's until it expires.
    if (old != null && old.fromDetail && !entry.fromDetail && !old.expired(DateTime.now())) return;
    _entries.remove(key);
    _entries[key] = entry;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _notify();
    _saveTimer ??= Timer(const Duration(seconds: 5), () => unawaited(_save()));
  }

  /// Bundled, so a burst of results redraws the posters once.
  void _notify() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 300), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> _save() async {
    _saveTimer = null;
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          for (final e in _entries.entries)
            e.key: [e.value.score, e.value.sources, e.value.fromDetail ? 1 : 0, e.value.at.millisecondsSinceEpoch],
        }),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (e) {
      appLogger.d('Rating median cache not saved: $e');
    }
  }
}

class _Entry {
  const _Entry(this.score, this.sources, this.fromDetail, this.at);

  /// -1: the server knows no usable score.
  final int score;
  final int sources;
  final bool fromDetail;
  final DateTime at;

  bool expired(DateTime now) =>
      now.difference(at) > (fromDetail ? RatingMedianCache._detailTtl : RatingMedianCache._serverTtl);
}

/// What a poster's median belongs to: the item itself, or for a season or an
/// episode shown with its series poster, the series.
class _Target {
  const _Target(this.key, this.id, this.title, this.kind, this.listingRatings, {this.isSeries = false});

  factory _Target.of(MediaItem item) {
    final seriesId = switch (item.kind) {
      MediaKind.episode => item.grandparentId,
      MediaKind.season => item.parentId,
      _ => null,
    };
    final seriesKey = item.seriesGlobalKey;
    if (seriesId != null && seriesKey != null) {
      return _Target(
        seriesKey,
        seriesId,
        item.grandparentTitle ?? item.parentTitle ?? item.title ?? '',
        MediaKind.show,
        const [],
        isSeries: true,
      );
    }
    return _Target(item.globalKey, item.id, item.title ?? '', item.kind, item.ratings ?? const []);
  }

  final String key;
  final String id;
  final String title;
  final MediaKind kind;
  final List<MediaRatingSource> listingRatings;
  final bool isSeries;
}
