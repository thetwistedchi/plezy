import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../media/library_query.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';

/// One watched film or episode, as kept on the device for the statistics.
class WatchRecord {
  const WatchRecord({
    required this.isMovie,
    required this.server,
    required this.library,
    required this.minutes,
    required this.plays,
    this.watchedAt,
    this.year,
    this.genres = const [],
    this.people = const [],
    this.showId,
    this.title,
  });

  final bool isMovie;
  final String server;

  /// The library's global key.
  final String library;
  final double minutes;
  final int plays;

  /// When it was last watched (local time), if the server says.
  final DateTime? watchedAt;
  final int? year;
  final List<String> genres;

  /// Directors first, then the leading actors (films).
  final List<String> people;
  final String? showId;

  /// Film title, or the show's title for an episode.
  final String? title;

  Map<String, Object?> toJson() => {
    'm': isMovie,
    's': server,
    'l': library,
    'n': minutes,
    'c': plays,
    'd': watchedAt?.millisecondsSinceEpoch,
    'y': year,
    'g': genres,
    'p': people,
    'h': showId,
    't': title,
  };

  factory WatchRecord.fromJson(Map<String, dynamic> j) => WatchRecord(
    isMovie: j['m'] == true,
    server: j['s'] as String? ?? '',
    library: j['l'] as String? ?? '',
    minutes: (j['n'] as num?)?.toDouble() ?? 0,
    plays: (j['c'] as num?)?.toInt() ?? 1,
    watchedAt: j['d'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['d'] as num).toInt()),
    year: (j['y'] as num?)?.toInt(),
    genres: [for (final g in j['g'] as List? ?? const []) g as String],
    people: [for (final p in j['p'] as List? ?? const []) p as String],
    showId: j['h'] as String?,
    title: j['t'] as String?,
  );
}

/// A show with its progress, for finished / in progress / abandoned.
class ShowRecord {
  const ShowRecord({
    required this.id,
    required this.server,
    required this.library,
    required this.title,
    required this.episodes,
    required this.watched,
    this.lastWatched,
  });

  final String id;
  final String server;
  final String library;
  final String title;
  final int episodes;
  final int watched;
  final DateTime? lastWatched;

  Map<String, Object?> toJson() => {
    'i': id,
    's': server,
    'l': library,
    't': title,
    'e': episodes,
    'w': watched,
    'd': lastWatched?.millisecondsSinceEpoch,
  };

  factory ShowRecord.fromJson(Map<String, dynamic> j) => ShowRecord(
    id: j['i'] as String? ?? '',
    server: j['s'] as String? ?? '',
    library: j['l'] as String? ?? '',
    title: j['t'] as String? ?? '',
    episodes: (j['e'] as num?)?.toInt() ?? 0,
    watched: (j['w'] as num?)?.toInt() ?? 0,
    lastWatched: j['d'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['d'] as num).toInt()),
  );
}

class WatchData {
  const WatchData({required this.records, required this.shows, required this.updatedAt});
  final List<WatchRecord> records;
  final List<ShowRecord> shows;
  final DateTime updatedAt;
}

/// Fork: collects what was watched from the libraries (films, every episode,
/// shows) and keeps it in a file, so the statistics open at once and only a
/// refresh asks the servers again.
class WatchStatsStore {
  WatchStatsStore._();

  static const _pageSize = 2000;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}watch_stats.json');
  }

  static Future<WatchData?> loadCached() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return WatchData(
        records: [for (final r in json['r'] as List) WatchRecord.fromJson(r as Map<String, dynamic>)],
        shows: [for (final s in json['s'] as List) ShowRecord.fromJson(s as Map<String, dynamic>)],
        updatedAt: DateTime.fromMillisecondsSinceEpoch((json['u'] as num).toInt()),
      );
    } catch (e) {
      appLogger.d('Watch stats: cache unreadable', error: e);
      return null;
    }
  }

  static DateTime? _date(int? raw) {
    if (raw == null || raw <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw > 100000000000 ? raw : raw * 1000);
  }

  static Future<List<MediaItem>> _all(MediaServerClient client, MediaLibrary library, MediaKind kind) async {
    final items = <MediaItem>[];
    for (var offset = 0; ; offset += _pageSize) {
      final page = await client.fetchLibraryPagedContent(
        library.id,
        libraryKind: library.kind,
        query: LibraryQuery(kind: kind, offset: offset, limit: _pageSize),
      );
      items.addAll(page.items);
      if (page.items.length < _pageSize || items.length >= page.totalCount) break;
    }
    return items;
  }

  /// Reads every film and TV library. [onProgress] gets the library being read.
  static Future<WatchData> collect(
    List<MediaLibrary> libraries,
    MediaServerClient? Function(String serverId) clientFor, {
    void Function(String library)? onProgress,
  }) async {
    final records = <WatchRecord>[];
    final shows = <ShowRecord>[];
    for (final library in libraries) {
      final serverId = library.serverId;
      if (serverId == null || (library.kind != MediaKind.movie && library.kind != MediaKind.show)) continue;
      final client = clientFor(serverId);
      if (client == null) continue;
      onProgress?.call(library.title);
      try {
        if (library.kind == MediaKind.movie) {
          for (final m in await _all(client, library, MediaKind.movie)) {
            final plays = m.viewCount ?? 0;
            if (plays <= 0) continue;
            records.add(
              WatchRecord(
                isMovie: true,
                server: serverId,
                library: library.globalKey,
                minutes: (m.durationMs ?? 0) / 60000,
                plays: plays,
                watchedAt: _date(m.lastViewedAt),
                year: m.year,
                genres: m.genres ?? const [],
                people: [...?m.directors?.take(2), ...?m.roles?.take(3).map((r) => r.tag)],
                title: m.title,
              ),
            );
          }
        } else {
          final showList = await _all(client, library, MediaKind.show);
          final byId = {for (final s in showList) s.id: s};
          for (final s in showList) {
            shows.add(
              ShowRecord(
                id: s.id,
                server: serverId,
                library: library.globalKey,
                title: s.title ?? '',
                episodes: s.leafCount ?? 0,
                watched: s.viewedLeafCount ?? 0,
                lastWatched: _date(s.lastViewedAt),
              ),
            );
          }
          for (final e in await _all(client, library, MediaKind.episode)) {
            final plays = e.viewCount ?? 0;
            if (plays <= 0) continue;
            final show = byId[e.grandparentId];
            records.add(
              WatchRecord(
                isMovie: false,
                server: serverId,
                library: library.globalKey,
                minutes: (e.durationMs ?? show?.durationMs ?? 0) / 60000,
                plays: plays,
                watchedAt: _date(e.lastViewedAt),
                year: show?.year ?? e.year,
                genres: show?.genres ?? const [],
                showId: e.grandparentId,
                title: e.grandparentTitle ?? show?.title,
              ),
            );
          }
        }
      } catch (e) {
        appLogger.d('Watch stats: ${library.title} failed', error: e);
      }
    }
    final data = WatchData(records: records, shows: shows, updatedAt: DateTime.now());
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'u': data.updatedAt.millisecondsSinceEpoch,
          'r': [for (final r in records) r.toJson()],
          's': [for (final s in shows) s.toJson()],
        }),
      );
    } catch (e) {
      appLogger.d('Watch stats: cache not written', error: e);
    }
    return data;
  }
}

enum StatsPeriod { allTime, thisYear, last12Months }

/// Everything the statistics screen shows, for one filter.
class WatchSummary {
  WatchSummary(WatchData data, {String? server, String? library, StatsPeriod period = StatsPeriod.allTime}) {
    final now = DateTime.now();
    bool inPeriod(DateTime? d) => switch (period) {
      StatsPeriod.allTime => true,
      StatsPeriod.thisYear => d != null && d.year == now.year,
      StatsPeriod.last12Months => d != null && d.isAfter(DateTime(now.year - 1, now.month, now.day)),
    };
    bool inScope(String s, String l) => (server == null || s == server) && (library == null || l == library);

    final showsWatched = <String>{};
    final showEpisodes = <String, int>{};
    final days = <DateTime>{};
    for (final r in data.records) {
      if (!inScope(r.server, r.library) || !inPeriod(r.watchedAt)) continue;
      // Within a period only the last viewing has a date: count one play.
      final plays = period == StatsPeriod.allTime ? r.plays : 1;
      hours += r.minutes * plays / 60;
      if (r.isMovie) {
        movies++;
        if (r.title != null && r.plays > 1) rewatched[r.title!] = r.plays;
        for (final p in r.people) {
          people[p] = (people[p] ?? 0) + 1;
        }
      } else {
        episodes++;
        if (r.showId != null) {
          showsWatched.add('${r.server}:${r.showId}');
          final name = r.title ?? '';
          showEpisodes[name] = (showEpisodes[name] ?? 0) + 1;
        }
      }
      for (final g in r.genres) {
        genres[g] = (genres[g] ?? 0) + 1;
      }
      if (r.year case final y?) {
        final decade = '${y ~/ 10 * 10}s';
        decades[decade] = (decades[decade] ?? 0) + 1;
      }
      final d = r.watchedAt;
      if (d != null) {
        weekdays[d.weekday - 1]++;
        hoursOfDay[d.hour]++;
        days.add(DateTime(d.year, d.month, d.day));
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        months[key] = (months[key] ?? 0) + 1;
      }
    }
    shows = showsWatched.length;
    topShows = (showEpisodes.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(10).toList();

    // Streaks: days in a row with something watched.
    final sorted = days.toList()..sort();
    var run = 0;
    DateTime? previous;
    for (final day in sorted) {
      run = previous != null && day.difference(previous).inDays == 1 ? run + 1 : 1;
      if (run > longestStreak) longestStreak = run;
      previous = day;
    }
    final today = DateTime(now.year, now.month, now.day);
    if (previous != null && today.difference(previous).inDays <= 1) currentStreak = run;
    activeDays = days.length;

    // Shows: finished, still going, put aside (nothing for half a year).
    final halfYearAgo = now.subtract(const Duration(days: 183));
    for (final s in data.shows) {
      if (!inScope(s.server, s.library) || s.watched == 0) continue;
      if (s.episodes > 0 && s.watched >= s.episodes) {
        finished.add(s.title);
      } else if (s.lastWatched != null && s.lastWatched!.isBefore(halfYearAgo)) {
        abandoned.add(s.title);
      } else {
        inProgress.add(s.title);
      }
    }
  }

  int movies = 0;
  int episodes = 0;
  int shows = 0;
  double hours = 0;
  final genres = <String, int>{};
  final decades = <String, int>{};
  final people = <String, int>{};
  final rewatched = <String, int>{};
  final months = <String, int>{};
  final weekdays = List<int>.filled(7, 0);
  final hoursOfDay = List<int>.filled(24, 0);
  int longestStreak = 0;
  int currentStreak = 0;
  int activeDays = 0;
  List<MapEntry<String, int>> topShows = const [];
  final finished = <String>[];
  final inProgress = <String>[];
  final abandoned = <String>[];

  String? get topGenre => _top(genres);
  String? get topPerson => _top(people);
  String? get busiestMonth => _top(months);

  static String? _top(Map<String, int> map) {
    if (map.isEmpty) return null;
    return map.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}
