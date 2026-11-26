import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/retro_strings.dart';
import '../../media/library_query.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import '../settings_service.dart';

/// One upcoming episode of a show in the library.
class UpcomingEpisode {
  const UpcomingEpisode({required this.show, required this.airs, this.name, this.season, this.number, this.network});

  /// The show as the server knows it (opens its details page).
  final MediaItem show;
  final DateTime airs;
  final String? name;
  final int? season;
  final int? number;
  final String? network;

  String get code => season != null && number != null ? 'S$season E$number' : '';
}

/// Fork: next air dates from TVmaze (no account or key), shared by the
/// Upcoming episodes screen, the Home row and the TV library tab.
///
/// TVmaze allows about 20 calls per 10 seconds, so calls are spaced out and
/// answers are kept on the device: a show's TVmaze id and status for 30
/// days, the next episode for 12 hours. Ended shows cost no calls after the
/// first check.
class UpcomingEpisodes {
  UpcomingEpisodes._();
  static final instance = UpcomingEpisodes._();

  /// Hub identifier of the Home row.
  static const hubIdentifier = '_retrowave_upcoming_';

  static const _cacheKey = 'retrowave_upcoming_v1';
  static const _showMaxAge = Duration(days: 30);
  static const _nextMaxAge = Duration(hours: 12);
  static const _missMaxAge = Duration(days: 7);
  static const _spacing = Duration(milliseconds: 550);

  Map<String, dynamic>? _cache;
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _queue = Future.value();
  Timer? _saveTimer;

  /// Card captions for the Home row and library tab, keyed by
  /// `serverId:itemId`. Only read under an [UpcomingLabelScope].
  final _labels = <String, String>{};

  String? labelFor(MediaItem item) => _labels['${item.serverId}:${item.id}'];

  /// Fork: shows left out of Upcoming (`serverId:id`).
  Set<String> get hidden => SettingsService.instance.read(SettingsService.upcomingHiddenShows).toSet();

  Future<void> hide(MediaItem show) async {
    final key = '${show.serverId}:${show.id}';
    final cache = await _load();
    ((cache['titles'] ??= <String, dynamic>{}) as Map<String, dynamic>)[key] = show.title;
    _scheduleSave();
    await SettingsService.instance.write(SettingsService.upcomingHiddenShows, [...hidden, key]);
    final list = all.value;
    if (list != null) {
      final title = (show.title ?? '').trim().toLowerCase();
      final next = [
        for (final e in list)
          if ('${e.show.serverId}:${e.show.id}' != key && (e.show.title ?? '').trim().toLowerCase() != title) e,
      ];
      all.value = next;
      unawaited(_storeAll(next));
    }
  }

  /// Title of a hidden show, as it was when hidden.
  Future<String> hiddenTitle(String key) async =>
      ((await _load())['titles'] as Map?)?[key] as String? ?? key;

  /// Shows again what [hide] left out; it turns up with the next scan.
  Future<void> unhide(String key) async {
    await SettingsService.instance.write(SettingsService.upcomingHiddenShows, [
      for (final k in hidden) if (k != key) k,
    ]);
  }

  /// Upcoming episodes for [shows] (show items), soonest first. [onProgress]
  /// reports partial results as lookups finish. [isCancelled] stops early.
  Future<List<UpcomingEpisode>> forShows(
    List<MediaItem> shows,
    MediaServerClient? Function(MediaItem show) clientFor, {
    void Function(List<UpcomingEpisode> soFar, int done)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = <UpcomingEpisode>[];
    // Fork: the same show on several servers (or libraries) is listed once.
    final seen = <String>{};
    final hiddenShows = hidden;
    // A hidden show stays hidden on every server, matched by its title.
    final titles = ((await _load())['titles'] as Map?) ?? const {};
    final hiddenTitles = {
      for (final k in hiddenShows)
        if (titles[k] is String) (titles[k] as String).trim().toLowerCase(),
    };
    var done = 0;
    for (final show in shows) {
      if (isCancelled?.call() ?? false) break;
      if (hiddenShows.contains('${show.serverId}:${show.id}') ||
          hiddenTitles.contains((show.title ?? '').trim().toLowerCase())) {
        done++;
        continue;
      }
      try {
        final client = clientFor(show);
        if (client != null) {
          final ids = await _idsFor(show, client);
          final title = (show.title ?? '').trim().toLowerCase();
          final keys = [
            if (ids.tvdb != null) 'tvdb:${ids.tvdb}',
            if (ids.imdb != null) 'imdb:${ids.imdb}',
            if (title.isNotEmpty) 'title:$title:${show.year ?? ''}',
          ];
          final duplicate = keys.any(seen.contains);
          seen.addAll(keys);
          final found = duplicate ? null : await _next(tvdb: ids.tvdb, imdb: ids.imdb);
          // The same TVmaze show reached through different ids.
          final next = found != null && seen.add('tvmaze:${found.show}') ? found : null;
          if (next != null) {
            final e = UpcomingEpisode(
              show: show,
              airs: next.airs,
              name: next.name,
              season: next.season,
              number: next.number,
              network: next.network,
            );
            results.add(e);
            _labels['${show.serverId}:${show.id}'] = caption(e);
          }
        }
      } catch (e) {
        appLogger.d('Upcoming: lookup failed for ${show.title}', error: e);
      }
      done++;
      if (onProgress != null) {
        results.sort((a, b) => a.airs.compareTo(b.airs));
        onProgress(List.of(results), done);
      }
    }
    results.sort((a, b) => a.airs.compareTo(b.airs));
    return results;
  }

  /// The show's TVDB / IMDb id, kept on the device so later scans need no
  /// server request per show.
  Future<({int? tvdb, String? imdb})> _idsFor(MediaItem show, MediaServerClient client) async {
    final cache = await _load();
    final ids = (cache['ids'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    final key = '${show.serverId}:${show.id}';
    final known = ids[key];
    if (known is Map) return (tvdb: (known['t'] as num?)?.toInt(), imdb: known['i'] as String?);
    final fetched = await client.fetchExternalIds(show.id);
    ids[key] = {'t': fetched.tvdb, 'i': fetched.imdb};
    _scheduleSave();
    return (tvdb: fetched.tvdb, imdb: fetched.imdb);
  }

  /// The latest scan over every visible TV library (Home row, Upcoming
  /// screen). Null until the first scan finished.
  final ValueNotifier<List<UpcomingEpisode>?> all = ValueNotifier(null);
  final ValueNotifier<({int done, int total})?> allProgress = ValueNotifier(null);
  DateTime? _allAt;
  Future<void>? _allRunning;

  /// Scans the shows of [libraries] (TV libraries), unless a scan finished
  /// in the last [maxAge] or one is running.
  Future<void> refreshAll(
    List<MediaLibrary> libraries,
    MediaServerClient? Function(String serverId) clientFor, {
    Duration maxAge = const Duration(hours: 1),
    bool force = false,
  }) async {
    await _restoreAll();
    final at = _allAt;
    if (!force && at != null && DateTime.now().difference(at) < maxAge) return Future.value();
    final running = _allRunning;
    if (!force && running != null) return running;
    // A forced scan (other servers picked) replaces a running one.
    final generation = ++_generation;
    final scan = _scanAll(libraries, clientFor, () => generation != _generation);
    _allRunning = scan;
    return scan.whenComplete(() {
      if (generation == _generation) _allRunning = null;
    });
  }

  int _generation = 0;

  static const _listKey = 'retrowave_upcoming_list_v1';
  bool _restored = false;

  /// Fork: the last finished scan, kept on the device, so Upcoming and the
  /// Home row show at once after a restart while a new scan runs.
  Future<void> _restoreAll() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_listKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final list = [
        for (final e in (json['items'] as List).whereType<Map>())
          UpcomingEpisode(
            show: MediaItem.fromJson(Map<String, dynamic>.from(e['show'] as Map)),
            airs: DateTime.parse(e['airs'] as String).toLocal(),
            name: e['name'] as String?,
            season: (e['season'] as num?)?.toInt(),
            number: (e['number'] as num?)?.toInt(),
            network: e['network'] as String?,
          ),
      ];
      // Episodes that aired since are dropped until the next scan.
      final now = DateTime.now().subtract(const Duration(hours: 3));
      final current = [for (final e in list) if (e.airs.isAfter(now)) e];
      for (final e in current) {
        _labels['${e.show.serverId}:${e.show.id}'] = caption(e);
      }
      all.value ??= current;
      _allAt ??= DateTime.fromMillisecondsSinceEpoch((json['at'] as num?)?.toInt() ?? 0);
    } catch (e) {
      appLogger.d('Upcoming: stored list unreadable', error: e);
    }
  }

  Future<void> _storeAll(List<UpcomingEpisode> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _listKey,
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'items': [
            for (final e in list)
              {
                'show': e.show.copyWith(raw: null).toJson(),
                'airs': e.airs.toUtc().toIso8601String(),
                'name': e.name,
                'season': e.season,
                'number': e.number,
                'network': e.network,
              },
          ],
        }),
      );
    } catch (e) {
      appLogger.d('Upcoming: storing the list failed', error: e);
    }
  }

  Future<void> _scanAll(
    List<MediaLibrary> libraries,
    MediaServerClient? Function(String serverId) clientFor,
    bool Function() isStale,
  ) async {
    final off = SettingsService.instance.read(SettingsService.upcomingServersOff).toSet();
    final showLibraries = libraries
        .where((l) => l.kind == MediaKind.show && l.serverId != null && !off.contains(l.serverId))
        .toList();
    // Clients are looked up now: the caller's context may be gone (Home
    // rebuilt, screen closed) long before the scan ends.
    final clients = <String, MediaServerClient?>{
      for (final l in showLibraries) l.serverId!: clientFor(l.serverId!),
    };
    if (showLibraries.isEmpty) {
      // Every server switched off: nothing to show.
      if (libraries.any((l) => l.kind == MediaKind.show)) {
        all.value = const [];
        _allAt = DateTime.now();
        unawaited(_storeAll(const []));
      }
      return;
    }
    final shows = <MediaItem>[];
    for (final library in showLibraries) {
      if (isStale()) return;
      final client = clients[library.serverId!];
      if (client == null) continue;
      try {
        final page = await client.fetchLibraryPagedContent(
          library.id,
          libraryKind: library.kind,
          query: LibraryQuery(kind: library.kind, limit: 5000),
        );
        shows.addAll(page.items.where((i) => i.kind == MediaKind.show));
      } catch (e) {
        appLogger.d('Upcoming: library ${library.title} failed', error: e);
      }
    }
    // Shows being watched first, so the likely ones turn up early.
    shows.sort((a, b) => ((b.viewedLeafCount ?? 0) > 0 ? 1 : 0).compareTo((a.viewedLeafCount ?? 0) > 0 ? 1 : 0));
    allProgress.value = (done: 0, total: shows.length);
    if (isStale()) return;
    final hadList = all.value?.isNotEmpty ?? false;
    final results = await forShows(
      shows,
      (show) => clients[show.serverId],
      isCancelled: isStale,
      onProgress: (soFar, done) {
        if (isStale()) return;
        allProgress.value = (done: done, total: shows.length);
        // With a stored list on screen, only the finished scan replaces it.
        if (!hadList && (all.value == null || soFar.length != (all.value?.length ?? 0))) all.value = soFar;
      },
    );
    if (isStale()) return;
    all.value = results;
    unawaited(_storeAll(results));
    allProgress.value = null;
    _allAt = DateTime.now();
  }

  /// "S2 E5 · Tomorrow 21:00".
  static String caption(UpcomingEpisode e) {
    final time = '${e.airs.hour.toString().padLeft(2, '0')}:${e.airs.minute.toString().padLeft(2, '0')}';
    return [e.code, '${dayLabel(e.airs)} $time'].where((s) => s.isNotEmpty).join(' · ');
  }

  static String dayLabel(DateTime d) {
    final today = DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (days == 0) return RetroStrings.today;
    if (days == 1) return RetroStrings.tomorrow;
    return '${d.day}.${d.month}.${d.year}';
  }

  Future<({int show, String? name, int? season, int? number, DateTime airs, String? network})?> _next({
    int? tvdb,
    String? imdb,
  }) async {
    final key = tvdb != null ? 'tvdb:$tvdb' : (imdb != null ? 'imdb:$imdb' : null);
    if (key == null) return null;
    final cache = await _load();
    final now = DateTime.now();

    var show = cache[key] as Map<String, dynamic>?;
    final showAt = DateTime.fromMillisecondsSinceEpoch((show?['at'] as num?)?.toInt() ?? 0);
    final showMax = show?['id'] == null ? _missMaxAge : _showMaxAge;
    if (show == null || now.difference(showAt) > showMax) {
      final query = tvdb != null ? {'thetvdb': '$tvdb'} : {'imdb': imdb!};
      final json = await _get(Uri.https('api.tvmaze.com', '/lookup/shows', query));
      show = {
        'at': now.millisecondsSinceEpoch,
        'id': json?['id'],
        'ended': json?['status'] == 'Ended',
        'network': ((json?['network'] ?? json?['webChannel']) as Map?)?['name'],
      };
      cache[key] = show;
      _scheduleSave();
    }
    final id = (show['id'] as num?)?.toInt();
    if (id == null || show['ended'] == true) return null;

    var next = show['next'] as Map<String, dynamic>?;
    final nextAt = DateTime.fromMillisecondsSinceEpoch((next?['at'] as num?)?.toInt() ?? 0);
    final stored = DateTime.tryParse(next?['airs'] as String? ?? '');
    final stale = next == null || now.difference(nextAt) > _nextMaxAge || (stored != null && stored.isBefore(now));
    if (stale) {
      final json = await _get(Uri.https('api.tvmaze.com', '/shows/$id', {'embed': 'nextepisode'}));
      if (json == null) return null;
      final ep = (json['_embedded'] as Map?)?['nextepisode'] as Map?;
      final airs = ep == null
          ? null
          : (DateTime.tryParse(ep['airstamp'] as String? ?? '') ?? DateTime.tryParse(ep['airdate'] as String? ?? ''));
      next = {
        'at': now.millisecondsSinceEpoch,
        'airs': airs?.toUtc().toIso8601String(),
        'name': ep?['name'],
        'season': ep?['season'],
        'number': ep?['number'],
      };
      show['ended'] = json['status'] == 'Ended';
      show['next'] = next;
      _scheduleSave();
    }
    final airs = DateTime.tryParse(next['airs'] as String? ?? '');
    if (airs == null) return null;
    return (
      show: id,
      name: next['name'] as String?,
      season: (next['season'] as num?)?.toInt(),
      number: (next['number'] as num?)?.toInt(),
      airs: airs.toLocal(),
      network: show['network'] as String?,
    );
  }

  /// One TVmaze call at a time, spaced to stay under the rate limit.
  Future<Map<String, dynamic>?> _get(Uri uri) {
    final completer = Completer<Map<String, dynamic>?>();
    _queue = _queue.then((_) async {
      final wait = _spacing - DateTime.now().difference(_lastCall);
      if (!wait.isNegative) await Future<void>.delayed(wait);
      _lastCall = DateTime.now();
      try {
        var response = await http.get(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode == 429) {
          await Future<void>.delayed(const Duration(seconds: 10));
          response = await http.get(uri).timeout(const Duration(seconds: 10));
        }
        completer.complete(response.statusCode == 200 ? jsonDecode(response.body) as Map<String, dynamic> : null);
      } catch (e) {
        completer.completeError(e);
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>> _load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    try {
      _cache = jsonDecode(prefs.getString(_cacheKey) ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      final cache = _cache;
      if (cache == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(cache));
    });
  }
}

/// Marks a subtree whose media cards show the upcoming episode caption
/// instead of their usual metadata line.
class UpcomingLabelScope extends InheritedWidget {
  const UpcomingLabelScope({super.key, required super.child});

  static bool active(BuildContext context) => context.getInheritedWidgetOfExactType<UpcomingLabelScope>() != null;

  /// The caption for [item] when [context] is under a scope.
  static String? labelIn(BuildContext context, MediaItem item) =>
      active(context) ? UpcomingEpisodes.instance.labelFor(item) : null;

  @override
  bool updateShouldNotify(UpcomingLabelScope oldWidget) => false;
}
