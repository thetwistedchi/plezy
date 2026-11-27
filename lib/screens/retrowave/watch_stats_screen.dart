import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/retro_strings.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/media_server_client.dart';
import '../../providers/libraries_provider.dart';
import '../../services/retrowave/person_pictures.dart';
import '../../services/retrowave/watch_stats.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_tokens.dart';
import '../../theme/player_style.dart';
import '../../theme/retrowave_colors.dart';
import '../../utils/media_image_helper.dart';
import '../../utils/media_navigation_helper.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/optimized_media_image.dart';
import '../../services/retrowave/audio/music_listen_tracker.dart';

/// Fork: watch statistics from the libraries' watched states, kept on the
/// device so they open at once. Filters by server, library and period;
/// every number opens the titles behind it.
class WatchStatsScreen extends StatefulWidget {
  const WatchStatsScreen({super.key});

  @override
  State<WatchStatsScreen> createState() => _WatchStatsScreenState();
}

/// One title in a detail view or poster strip.
class _Entry {
  const _Entry({
    required this.server,
    required this.title,
    this.id,
    this.thumb,
    this.badge,
    this.isMovie = false,
    this.plays = 1,
  });
  final String server;
  final String? id;
  final String? thumb;
  final String title;
  final String? badge;
  final bool isMovie;
  final int plays;

  /// The key it is excluded by (see [WatchSummary.keyOf]).
  String? get key => id == null ? null : '$server:$id';
}

/// Opens the statistics menu of an entry at a position.
typedef _EntryMenu = Future<bool> Function(_Entry entry, Offset position);

class _WatchStatsScreenState extends State<WatchStatsScreen> {
  WatchData? _data;
  bool _loading = false;
  String? _reading;
  String? _server;
  String? _library;
  StatsPeriod _period = StatsPeriod.allTime;

  /// Fork: music statistics instead of films and shows.
  bool _music = false;
  int _listLength = SettingsService.instance.read(SettingsService.statsListLength);
  Set<String> _excluded = SettingsService.instance.read(SettingsService.statsExcluded).toSet();
  Set<String> _countOnce = SettingsService.instance.read(SettingsService.statsCountOnce).toSet();

  WatchSummary _summary(WatchData data, StatsPeriod period) => WatchSummary(
    data,
    server: _server,
    library: _library,
    period: period,
    excluded: _excluded,
    countOnce: _countOnce,
  );

  Future<void> _saveExclusions() async {
    final svc = SettingsService.instance;
    await svc.write(SettingsService.statsExcluded, _excluded.toList());
    await svc.write(SettingsService.statsCountOnce, _countOnce.toList());
  }

  /// Right click or long press on a title. True when it was excluded.
  Future<bool> _entryMenu(_Entry entry, Offset position) async {
    final key = entry.key;
    if (key == null) return false;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final once = _countOnce.contains(key);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        if (entry.isMovie && (entry.plays > 1 || once))
          PopupMenuItem(
            value: 'once',
            child: ListTile(
              leading: AppIcon.retro(once ? Symbols.replay_rounded : Symbols.looks_one_rounded),
              title: Text(once ? RetroStrings.statsCountAll : RetroStrings.statsCountOnce),
            ),
          ),
        PopupMenuItem(
          value: 'exclude',
          child: ListTile(
            leading: const AppIcon.retro(Symbols.visibility_off_rounded),
            title: Text(RetroStrings.statsExclude),
          ),
        ),
      ],
    );
    if (choice == null || !mounted) return false;
    setState(() {
      if (choice == 'exclude') {
        _excluded = {..._excluded, key};
      } else {
        _countOnce = once ? (_countOnce.toSet()..remove(key)) : {..._countOnce, key};
      }
    });
    await _saveExclusions();
    return choice == 'exclude';
  }

  /// Title of an excluded key, from the collected data.
  String _titleOf(String key) {
    final data = _data;
    if (data == null) return key;
    for (final sh in data.shows) {
      if ('${sh.server}:${sh.id}' == key) return sh.title;
    }
    for (final r in data.records) {
      if (WatchSummary.keyOf(r) == key && r.title != null) return r.title!;
    }
    return key;
  }

  Future<void> _showExcluded() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          final keys = [
            for (final k in _excluded) (k, false),
            for (final k in _countOnce) (k, true),
          ];
          void restore(String key, bool once) {
            setState(() {
              if (once) {
                _countOnce = _countOnce.toSet()..remove(key);
              } else {
                _excluded = _excluded.toSet()..remove(key);
              }
            });
            setDialog(() {});
            unawaited(_saveExclusions());
          }

          return AlertDialog(
            title: Text(RetroStrings.statsExcludedTitles),
            content: SizedBox(
              width: 420,
              child: keys.isEmpty
                  ? Text(RetroStrings.statsExcludedNone)
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final (key, once) in keys)
                          ListTile(
                            title: Text(_titleOf(key), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: once ? Text(RetroStrings.statsCountedOnce) : null,
                            trailing: TextButton(
                              onPressed: () => restore(key, once),
                              child: Text(RetroStrings.statsRestore),
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              if (keys.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _excluded = {};
                      _countOnce = {};
                    });
                    setDialog(() {});
                    unawaited(_saveExclusions());
                  },
                  child: Text(RetroStrings.statsRestoreAll),
                ),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(RetroStrings.close)),
            ],
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final cached = await WatchStatsStore.loadCached();
    if (!mounted) return;
    if (cached != null) {
      setState(() => _data = cached);
      if (DateTime.now().difference(cached.updatedAt) > const Duration(days: 1)) unawaited(_refresh());
    } else {
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    final libraries = context.read<LibrariesProvider>().libraries;
    MediaServerClient? clientFor(String serverId) => context.tryGetMediaClientForServer(ServerId(serverId));
    final data = await WatchStatsStore.collect(
      libraries,
      clientFor,
      onProgress: (library) {
        if (mounted) setState(() => _reading = library);
      },
    );
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _reading = null;
    });
  }

  List<MediaLibrary> get _libraries => [
    for (final l in context.read<LibrariesProvider>().libraries)
      if (l.serverId != null && (l.kind == MediaKind.movie || l.kind == MediaKind.show)) l,
  ];

  MediaServerClient? _client(String server) => context.tryGetMediaClientForServer(ServerId(server));

  Future<void> _openItem(String server, String? id) async {
    if (id == null) return;
    final item = await _client(server)?.fetchItem(id);
    if (item != null && mounted) unawaited(navigateToMediaItem(context, item));
  }

  void _openDetail(String title, List<_Entry> entries) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _StatsDetailScreen(
            title: title,
            entries: entries,
            client: _client,
            onOpen: _openItem,
            onMenu: _entryMenu,
          ),
        ),
      ),
    );
  }

  List<_Entry> _movieEntries(Iterable<WatchRecord> records) => [
    for (final r in records)
      if (r.isMovie)
        _Entry(
          server: r.server,
          id: r.id,
          thumb: r.thumb,
          title: r.title ?? '',
          badge: r.plays > 1 && !_countOnce.contains(WatchSummary.keyOf(r)) ? '×${r.plays}' : null,
          isMovie: true,
          plays: r.plays,
        ),
  ];

  /// Shows of [records] (episodes), most episodes first, plus films.
  List<_Entry> _titleEntries(WatchSummary s, List<WatchRecord> records) {
    final perShow = <String, int>{};
    for (final r in records.where((r) => !r.isMovie && r.showId != null)) {
      final key = '${r.server}:${r.showId}';
      perShow[key] = (perShow[key] ?? 0) + 1;
    }
    final shows = perShow.keys.toList()..sort((a, b) => perShow[b]!.compareTo(perShow[a]!));
    return [
      for (final key in shows) _showEntry(s, key, perShow[key]!),
      ..._movieEntries(records),
    ];
  }

  _Entry _showEntry(WatchSummary s, String key, int episodes) {
    final info = s.showInfo[key];
    final first = s.byShow[key]?.first;
    return _Entry(
      server: info?.server ?? first?.server ?? '',
      id: info?.id ?? first?.showId,
      thumb: info?.thumb,
      title: s.showTitle(key),
      badge: RetroStrings.statsEpisodeCount(episodes),
    );
  }

  List<_Entry> _showRecordEntries(List<ShowRecord> shows) => [
    for (final sh in shows)
      _Entry(server: sh.server, id: sh.id, thumb: sh.thumb, title: sh.title, badge: '${sh.watched}/${sh.episodes}'),
  ];

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final data = _data;
    final libraries = _libraries;
    final servers = <String, String>{for (final l in libraries) l.serverId!: l.serverName ?? l.serverId!};
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CustomAppBar(
            title: Text(RetroStrings.watchStats),
            actions: [
              if (_excluded.isNotEmpty || _countOnce.isNotEmpty)
                IconButton(
                  tooltip: '${RetroStrings.statsExcludedTitles} (${_excluded.length + _countOnce.length})',
                  onPressed: () => unawaited(_showExcluded()),
                  icon: const AppIcon.retro(Symbols.visibility_off_rounded),
                ),
              IconButton(
                tooltip: RetroStrings.statsRefresh,
                onPressed: _loading ? null : () => unawaited(_refresh()),
                icon: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const AppIcon.retro(Symbols.refresh_rounded),
              ),
            ],
          ),
          if (data == null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (_reading != null) ...[
                      const SizedBox(height: 12),
                      Text(RetroStrings.statsReading(_reading!), style: TextStyle(color: mono.textMuted)),
                    ],
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
              sliver: SliverList.list(
                children: [
                  Text(
                    _loading && _reading != null
                        ? RetroStrings.statsReading(_reading!)
                        : RetroStrings.statsUpdated(_ago(data.updatedAt)),
                    style: TextStyle(color: mono.textMuted),
                  ),
                  const SizedBox(height: 12),
                  _filters(servers, libraries),
                  const SizedBox(height: 20),
                  if (_music)
                    ..._musicContent(context)
                  else ...[
                    ..._content(
                      context,
                      _summary(data, _period),
                      libraries,
                    ),
                    const SizedBox(height: 28),
                    _yearInReview(
                      context,
                      _summary(data, StatsPeriod.thisYear),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return RetroStrings.justNow;
    if (d.inHours < 1) return '${d.inMinutes} min';
    if (d.inDays < 1) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  Widget _filters(Map<String, String> servers, List<MediaLibrary> libraries) {
    final shown = [
      for (final l in libraries)
        if (_server == null || l.serverId == _server) l,
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text(RetroStrings.statsVideo)),
            ButtonSegment(value: true, label: Text(RetroStrings.statsMusic)),
          ],
          selected: {_music},
          onSelectionChanged: (s) {
            setState(() => _music = s.first);
            if (s.first) unawaited(MusicListenTracker.instance.load().then((_) => mounted ? setState(() {}) : null));
          },
        ),
        SegmentedButton<StatsPeriod>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: StatsPeriod.allTime, label: Text(RetroStrings.statsAllTime)),
            ButtonSegment(value: StatsPeriod.thisYear, label: Text(RetroStrings.statsThisYear)),
            ButtonSegment(value: StatsPeriod.last12Months, label: Text(RetroStrings.statsLast12)),
          ],
          selected: {_period},
          onSelectionChanged: (s) => setState(() => _period = s.first),
        ),
        Tooltip(
          message: RetroStrings.statsShowCount,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 10, label: Text('10')),
              ButtonSegment(value: 20, label: Text('20')),
              ButtonSegment(value: 50, label: Text('50')),
            ],
            selected: {_listLength},
            onSelectionChanged: (s) {
              setState(() => _listLength = s.first);
              unawaited(SettingsService.instance.write(SettingsService.statsListLength, s.first));
            },
          ),
        ),
        if (servers.length > 1)
          DropdownButton<String?>(
            value: _server,
            items: [
              DropdownMenuItem(value: null, child: Text(RetroStrings.statsAllServers)),
              for (final e in servers.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() {
              _server = v;
              _library = null;
            }),
          ),
        if (!_music)
        DropdownButton<String?>(
          value: shown.any((l) => l.globalKey == _library) ? _library : null,
          items: [
            DropdownMenuItem(value: null, child: Text(RetroStrings.statsAllLibraries)),
            for (final l in shown) DropdownMenuItem(value: l.globalKey, child: Text(l.title)),
          ],
          onChanged: (v) => setState(() => _library = v),
        ),
      ],
    );
  }

  /// Fork: music statistics from the app's own listening log.
  List<Widget> _musicContent(BuildContext context) {
    final now = DateTime.now();
    bool inPeriod(DateTime at) => switch (_period) {
      StatsPeriod.allTime => true,
      StatsPeriod.thisYear => at.year == now.year,
      StatsPeriod.last12Months => now.difference(at).inDays <= 365,
    };
    final log = [
      for (final l in MusicListenTracker.instance.log)
        if (inPeriod(l.at) && (_server == null || l.server == _server)) l,
    ];
    if (log.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(RetroStrings.statsMusicEmpty, style: TextStyle(color: tokens(context).textMuted)),
        ),
      ];
    }
    final n = _listLength;
    final hours = log.fold<int>(0, (sum, l) => sum + l.duration.inMilliseconds) / 3600000;
    final artists = <String, int>{};
    final albums = <String, int>{};
    final albumInfo = <String, MusicListen>{};
    final tracks = <String, int>{};
    final hoursOfDay = List.filled(24, 0);
    final weekdays = List.filled(7, 0);
    for (final l in log) {
      if (l.artist.isNotEmpty) artists[l.artist] = (artists[l.artist] ?? 0) + 1;
      final albumKey = l.albumKey;
      if (albumKey != null) {
        albums[albumKey] = (albums[albumKey] ?? 0) + 1;
        albumInfo[albumKey] = l;
      }
      final trackLabel = l.artist.isEmpty ? l.title : '${l.title} · ${l.artist}';
      tracks[trackLabel] = (tracks[trackLabel] ?? 0) + 1;
      hoursOfDay[l.at.hour]++;
      weekdays[l.at.weekday - 1]++;
    }
    List<MapEntry<String, int>> top(Map<String, int> map) =>
        (map.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(n).toList();
    final topAlbums = top(albums);
    return [
      Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          _StatTile(icon: Symbols.headphones_rounded, value: '${hours.round()}', label: RetroStrings.statsListened),
          _StatTile(icon: Symbols.music_note_rounded, value: '${log.length}', label: RetroStrings.statsTracks),
          _StatTile(icon: Symbols.artist_rounded, value: '${artists.length}', label: RetroStrings.statsTopArtists),
          _StatTile(icon: Symbols.album_rounded, value: '${albums.length}', label: RetroStrings.statsTopAlbums),
        ],
      ),
      if (artists.isNotEmpty)
        _Section(title: RetroStrings.statsTopArtists, child: _Bars(entries: top(artists))),
      if (topAlbums.isNotEmpty)
        _Section(
          title: RetroStrings.statsTopAlbums,
          child: _PosterStrip(
            entries: [
              for (final e in topAlbums)
                _Entry(
                  server: albumInfo[e.key]!.server ?? '',
                  id: e.key.substring(e.key.indexOf(':') + 1),
                  thumb: albumInfo[e.key]!.thumb,
                  title: albumInfo[e.key]!.album,
                  badge: '×${e.value}',
                ),
            ],
            client: _client,
            onOpen: _openItem,
          ),
        ),
      if (tracks.isNotEmpty) _Section(title: RetroStrings.statsTopTracks, child: _Bars(entries: top(tracks))),
      _Section(
        title: RetroStrings.statsWeekdays,
        child: _Columns(entries: [for (var i = 0; i < 7; i++) MapEntry(RetroStrings.weekdaysShort[i], weekdays[i])]),
      ),
      _Section(
        title: RetroStrings.statsHoursOfDay,
        child: _Columns(
          entries: [for (var h = 0; h < 24; h++) MapEntry(h % 3 == 0 ? '$h' : '', hoursOfDay[h])],
          height: 110,
        ),
      ),
    ];
  }

  List<Widget> _content(BuildContext context, WatchSummary s, List<MediaLibrary> libraries) {
    final libraryTitle = {for (final l in libraries) l.globalKey: l.title};
    final n = _listLength;
    final genres = WatchSummary.ranked(s.byGenre, n);
    final decades = s.byDecade.keys.toList()..sort();
    final directors = WatchSummary.ranked(s.byDirector, n);
    final actors = WatchSummary.ranked(s.byActor, n);
    final topShows = WatchSummary.ranked(s.byShow, n);
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          // Fork: the six tiles share one row: full size from 170 px each,
          // compact from 120 px; below that they wrap, centred.
          final fit = (constraints.maxWidth - 16 * 5) / 6;
          final fitCompact = (constraints.maxWidth - 10 * 5) / 6;
          final compact = fit < 170 && fitCompact >= 120;
          final w = fit >= 170 ? fit.floorToDouble() : (compact ? fitCompact.floorToDouble() : 190.0);
          return Wrap(
        alignment: fit >= 170 || compact ? WrapAlignment.start : WrapAlignment.center,
        spacing: compact ? 10 : 16,
        runSpacing: 16,
        children: [
          _StatTile(
            width: w,
            compact: compact,
            icon: Symbols.hourglass_bottom_rounded,
            value: '${s.hours.round()}',
            label: RetroStrings.statsHours,
            onTap: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _BarsDetailScreen(
                    title: RetroStrings.statsHoursByLibrary,
                    entries: [
                      for (final e in (s.hoursByLibrary.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                        MapEntry(libraryTitle[e.key] ?? e.key, e.value.round()),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _StatTile(
            width: w,
            compact: compact,
            icon: Symbols.movie_rounded,
            value: '${s.movies}',
            label: RetroStrings.statsMovies,
            onTap: () => _openDetail(RetroStrings.statsMovies, _movieEntries(s.movieRecords)),
          ),
          _StatTile(
            width: w,
            compact: compact,
            icon: Symbols.tv_rounded,
            value: '${s.episodes}',
            label: RetroStrings.statsEpisodes,
            onTap: () => _openDetail(RetroStrings.statsEpisodes, [
              for (final key in WatchSummary.ranked(s.byShow, 1000)) _showEntry(s, key, s.byShow[key]!.length),
            ]),
          ),
          _StatTile(
            width: w,
            compact: compact,
            icon: Symbols.video_library_rounded,
            value: '${s.shows}',
            label: RetroStrings.statsShows,
            onTap: () => _openDetail(RetroStrings.statsShows, [
              for (final key in WatchSummary.ranked(s.byShow, 1000)) _showEntry(s, key, s.byShow[key]!.length),
            ]),
          ),
          _StatTile(
            width: w,
            compact: compact,
            icon: Symbols.local_fire_department_rounded,
            value: '${s.longestStreak}',
            label: RetroStrings.statsLongestStreak,
          ),
          _StatTile(
            width: w,
            compact: compact,
            icon: Symbols.bolt_rounded,
            value: '${s.currentStreak}',
            label: RetroStrings.statsCurrentStreak,
          ),
        ],
      );
        },
      ),
      if (_period != StatsPeriod.allTime) ...[
        const SizedBox(height: 10),
        Text(RetroStrings.statsPeriodHint, style: TextStyle(color: tokens(context).textMuted)),
      ],
      if (topShows.isNotEmpty)
        _Section(
          title: RetroStrings.statsTopShows,
          child: _PosterStrip(
            entries: [for (final key in topShows) _showEntry(s, key, s.byShow[key]!.length)],
            client: _client,
            onOpen: _openItem,
            onMenu: _entryMenu,
          ),
        ),
      if (s.rewatched.isNotEmpty)
        _Section(
          title: RetroStrings.statsRewatched,
          child: _PosterStrip(
            entries: _movieEntries(s.rewatched.take(n)),
            client: _client,
            onOpen: _openItem,
            onMenu: _entryMenu,
          ),
        ),
      if (directors.isNotEmpty)
        _Section(
          title: RetroStrings.statsDirectors,
          child: _PeopleGrid(
            names: directors,
            counts: {for (final d in directors) d: s.byDirector[d]!.length},
            records: s.byDirector,
            thumbs: const {},
            client: _client,
            onTap: (name) => _openDetail(name, _movieEntries(s.byDirector[name]!)),
          ),
        ),
      if (actors.isNotEmpty)
        _Section(
          title: RetroStrings.statsActors,
          hint: RetroStrings.statsPeopleHint,
          child: _PeopleGrid(
            names: actors,
            counts: {for (final a in actors) a: s.byActor[a]!.length},
            records: s.byActor,
            thumbs: s.actorThumbs,
            client: _client,
            onTap: (name) => _openDetail(name, _movieEntries(s.byActor[name]!)),
          ),
        ),
      if (genres.isNotEmpty)
        _Section(
          title: RetroStrings.statsGenres,
          child: _Bars(
            entries: [for (final g in genres) MapEntry(g, s.byGenre[g]!.length)],
            onTap: (g) => _openDetail(g, _titleEntries(s, s.byGenre[g]!)),
          ),
        ),
      if (decades.isNotEmpty)
        _Section(
          title: RetroStrings.statsDecades,
          child: _Columns(
            entries: [for (final d in decades) MapEntry(d, s.byDecade[d]!.length)],
            onTap: (d) => _openDetail(d, _titleEntries(s, s.byDecade[d]!)),
          ),
        ),
      if (s.finished.isNotEmpty || s.inProgress.isNotEmpty || s.abandoned.isNotEmpty)
        _Section(
          title: RetroStrings.statsShowProgress,
          hint: RetroStrings.statsShowProgressHint,
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatTile(
                icon: Symbols.check_circle_rounded,
                value: '${s.finished.length}',
                label: RetroStrings.statsFinished,
                onTap: () => _openDetail(RetroStrings.statsFinished, _showRecordEntries(s.finished)),
              ),
              _StatTile(
                icon: Symbols.play_circle_rounded,
                value: '${s.inProgress.length}',
                label: RetroStrings.statsInProgress,
                onTap: () => _openDetail(RetroStrings.statsInProgress, _showRecordEntries(s.inProgress)),
              ),
              _StatTile(
                icon: Symbols.pause_circle_rounded,
                value: '${s.abandoned.length}',
                label: RetroStrings.statsAbandoned,
                onTap: () => _openDetail(RetroStrings.statsAbandoned, _showRecordEntries(s.abandoned)),
              ),
            ],
          ),
        ),
      if (s.activeDays > 0) ...[
        _Section(
          title: RetroStrings.statsWeekdays,
          hint: RetroStrings.statsDatesHint,
          child: _Columns(
            entries: [for (var i = 0; i < 7; i++) MapEntry(RetroStrings.weekdaysShort[i], s.weekdays[i])],
          ),
        ),
        _Section(
          title: RetroStrings.statsHoursOfDay,
          child: _Columns(
            entries: [for (var h = 0; h < 24; h++) MapEntry(h % 3 == 0 ? '$h' : '', s.hoursOfDay[h])],
            height: 110,
          ),
        ),
        _Section(
          title: RetroStrings.statsMonths,
          child: _Columns(entries: _lastTwelve(s.months)),
        ),
      ],
    ];
  }

  List<MapEntry<String, int>> _lastTwelve(Map<String, int> months) {
    final now = DateTime.now();
    return [
      for (var i = 11; i >= 0; i--)
        () {
          final d = DateTime(now.year, now.month - i);
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          return MapEntry(RetroStrings.monthName(d.month).substring(0, 3), months[key] ?? 0);
        }(),
    ];
  }

  Widget _yearInReview(BuildContext context, WatchSummary y) {
    if (y.movies + y.episodes == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final mono = tokens(context);
    final colors = _gradient(context);
    final year = DateTime.now().year;
    String month(String key) {
      final parts = key.split('-');
      return parts.length == 2 ? RetroStrings.monthName(int.tryParse(parts[1]) ?? 1) : key;
    }

    final facts = <(IconData, String, String)>[
      (Symbols.hourglass_bottom_rounded, RetroStrings.statsHours, '${y.hours.round()}'),
      (Symbols.movie_rounded, RetroStrings.statsMovies, '${y.movies}'),
      (Symbols.tv_rounded, RetroStrings.statsEpisodes, '${y.episodes}'),
      (Symbols.calendar_month_rounded, RetroStrings.statsActiveDays, '${y.activeDays}'),
      if (y.topGenre case final g?) (Symbols.category_rounded, RetroStrings.statsTopGenre, g),
      if (y.topShowKey case final k?) (Symbols.star_rounded, RetroStrings.statsTopShow, y.showTitle(k)),
      if (y.topDirector case final d?) (Symbols.movie_edit_rounded, RetroStrings.statsTopDirector, d),
      if (y.topActor case final a?) (Symbols.person_rounded, RetroStrings.statsTopActor, a),
      if (y.busiestMonth case final m?) (Symbols.trending_up_rounded, RetroStrings.statsBusiestMonth, month(m)),
      (Symbols.local_fire_department_rounded, RetroStrings.statsLongestStreak, '${y.longestStreak}'),
    ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(mono.radiusMd + 2),
        gradient: LinearGradient(colors: colors),
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: RetroColors.isActive(context) ? RetroColors.dusk : mono.surface,
          borderRadius: BorderRadius.circular(mono.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (rect) => LinearGradient(colors: colors).createShader(rect),
              child: Text(
                RetroStrings.statsYearInReview(year),
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 14,
              children: [
                for (final (icon, label, value) in facts)
                  SizedBox(
                    width: 240,
                    child: Row(
                      children: [
                        AppIcon.retro(icon, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(label, style: TextStyle(color: mono.textMuted, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The player timeline's colours (or the theme's accent).
List<Color> _gradient(BuildContext context) {
  final g = PlayerStyle.of(context).progressGradient;
  if (g != null && g.length >= 2) return g;
  final primary = Theme.of(context).colorScheme.primary;
  return [primary.withValues(alpha: 0.55), primary];
}

/// [_gradient], muted for bars and columns: the same fade, half strength.
List<Color> _softGradient(BuildContext context) {
  final g = _gradient(context);
  return [g.first.withValues(alpha: 0.3), g.last.withValues(alpha: 0.7)];
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.hint});
  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: RetroColors.isActive(context) ? RetroColors.dusk.withValues(alpha: 0.7) : mono.surface,
        borderRadius: BorderRadius.circular(mono.radiusMd),
        border: Border.all(color: mono.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          if (hint != null) Text(hint!, style: TextStyle(color: mono.textMuted, fontSize: 12)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
    this.width = 190,
    this.compact = false,
  });
  final double width;
  final bool compact;
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final colors = _gradient(context);
    return Material(
      color: RetroColors.isActive(context) ? RetroColors.dusk : mono.surface,
      borderRadius: BorderRadius.circular(mono.radiusMd),
      child: InkWell(
        mouseCursor: onTap == null ? null : SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(mono.radiusMd),
        onTap: onTap,
        child: Container(
          width: width,
          padding: EdgeInsets.all(compact ? 10 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(mono.radiusMd),
            border: Border.all(color: mono.outline),
          ),
          child: Row(
            children: [
              AppIcon.retro(icon, size: compact ? 22 : 30),
              SizedBox(width: compact ? 8 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: (rect) => LinearGradient(colors: colors).createShader(rect),
                      child: Text(
                        value,
                        maxLines: 1,
                        style: (compact ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall)?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Text(label, maxLines: 2, style: TextStyle(color: mono.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (onTap != null && !compact) AppIcon.retro(Symbols.chevron_right_rounded, size: 18, color: mono.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal bars in the timeline's fade.
class _Bars extends StatelessWidget {
  const _Bars({required this.entries, this.onTap});
  final List<MapEntry<String, int>> entries;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final colors = _softGradient(context);
    final max = entries.fold<int>(1, (m, e) => e.value > m ? e.value : m);
    return Column(
      children: [
        for (final e in entries)
          InkWell(
            mouseCursor: onTap == null ? null : SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(8),
            onTap: onTap == null ? null : () => onTap!(e.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                children: [
                  SizedBox(width: 170, child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 8,
                          width: (c.maxWidth * e.value / max).clamp(4.0, c.maxWidth),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: colors),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text('${e.value}', textAlign: TextAlign.end, style: TextStyle(color: mono.textMuted)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Vertical columns in the timeline's fade (decades, weekdays, hours).
class _Columns extends StatelessWidget {
  const _Columns({required this.entries, this.onTap, this.height = 140});
  final List<MapEntry<String, int>> entries;
  final ValueChanged<String>? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final colors = _softGradient(context);
    final max = entries.fold<int>(1, (m, e) => e.value > m ? e.value : m);
    return SizedBox(
      height: height + 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in entries)
            Expanded(
              child: Tooltip(
                message: '${e.key} · ${e.value}',
                child: InkWell(
                  mouseCursor: onTap == null || e.key.isEmpty ? null : SystemMouseCursors.click,
                  onTap: onTap == null || e.key.isEmpty ? null : () => onTap!(e.key),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (e.value > 0 && entries.length <= 12)
                        Text('${e.value}', style: TextStyle(fontSize: 11, color: mono.textMuted)),
                      Container(
                        height: (height * e.value / max).clamp(2.0, height),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: colors,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(e.key, maxLines: 1, style: TextStyle(fontSize: 11, color: mono.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Posters in a row with a badge; a tap opens the title.
class _PosterStrip extends StatelessWidget {
  const _PosterStrip({required this.entries, required this.client, required this.onOpen, this.onMenu});
  final List<_Entry> entries;
  final MediaServerClient? Function(String server) client;
  final Future<void> Function(String server, String? id) onOpen;
  final _EntryMenu? onMenu;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 232,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: 120,
          child: _PosterTile(entry: entries[i], rank: i + 1, client: client, onOpen: onOpen, onMenu: onMenu),
        ),
      ),
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({required this.entry, required this.client, required this.onOpen, this.rank, this.onMenu});
  final _Entry entry;
  final int? rank;
  final MediaServerClient? Function(String server) client;
  final Future<void> Function(String server, String? id) onOpen;
  final _EntryMenu? onMenu;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final colors = _gradient(context);
    Offset? pressAt;
    final menu = onMenu;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(mono.radiusSm),
      onTap: () => unawaited(onOpen(entry.server, entry.id)),
      onTapDown: (d) => pressAt = d.globalPosition,
      onSecondaryTapDown: menu == null ? null : (d) => unawaited(menu(entry, d.globalPosition)),
      onLongPress: menu == null ? null : () => unawaited(menu(entry, pressAt ?? Offset.zero)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(mono.radiusSm),
                  child: OptimizedMediaImage(
                    client: client(entry.server),
                    imagePath: entry.thumb,
                    fit: BoxFit.cover,
                    fallbackIcon: Symbols.movie_rounded,
                    imageType: ImageType.poster,
                  ),
                ),
                if (rank != null && rank! <= 3)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _Badge(text: '#$rank', colors: colors),
                  ),
                if (entry.badge case final badge?)
                  Positioned(right: 6, bottom: 6, child: _Badge(text: badge, colors: colors)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.colors});
  final String text;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: colors.last.withValues(alpha: 0.55)),
    ),
    child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

/// People as round pictures with the number of their titles.
class _PeopleGrid extends StatelessWidget {
  const _PeopleGrid({
    required this.names,
    required this.counts,
    required this.records,
    required this.thumbs,
    required this.client,
    required this.onTap,
  });
  final List<String> names;
  final Map<String, int> counts;
  final Map<String, List<WatchRecord>> records;
  final Map<String, ({String server, String path})> thumbs;
  final MediaServerClient? Function(String server) client;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final colors = _gradient(context);
    return Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        for (final name in names)
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(name),
            child: SizedBox(
              width: 104,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: colors.last.withValues(alpha: 0.5)),
                        child: ClipOval(
                          child: SizedBox(
                            width: 82,
                            height: 82,
                            child: _PersonPicture(
                              name: name,
                              known: thumbs[name],
                              records: records[name] ?? const [],
                              client: client,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -2,
                        child: _Badge(text: '${counts[name]}', colors: colors),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: mono.text),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A person's picture: the one the listing gave, or looked up once in one
/// of their films (cast and crew with pictures); initials otherwise.
class _PersonPicture extends StatefulWidget {
  const _PersonPicture({required this.name, required this.known, required this.records, required this.client});
  final String name;
  final ({String server, String path})? known;
  final List<WatchRecord> records;
  final MediaServerClient? Function(String server) client;

  static final Map<String, Future<({String server, String path})?>> _cache = {};

  @override
  State<_PersonPicture> createState() => _PersonPictureState();
}

class _PersonPictureState extends State<_PersonPicture> {
  late final Future<({String server, String path})?> _picture =
      widget.known != null ? Future.value(widget.known) : _PersonPicture._cache.putIfAbsent(widget.name, _lookUp);

  Future<({String server, String path})?> _lookUp() async {
    final record = widget.records.where((r) => r.id != null).firstOrNull;
    if (record == null) return null;
    try {
      final item = await widget.client(record.server)?.fetchItem(record.id!);
      if (item == null) return null;
      final path = _pathIn(item, widget.name);
      return path == null ? null : (server: record.server, path: path);
    } catch (_) {
      return null;
    }
  }

  static String? _pathIn(MediaItem item, String name) {
    for (final r in item.roles ?? const []) {
      if (r.tag == name && r.thumbPath != null) return r.thumbPath;
    }
    final raw = item.raw;
    // Jellyfin: People with ids (directors too).
    if (raw?['People'] case final List people) {
      for (final p in people) {
        if (p is Map && p['Name'] == name && p['Id'] is String) return '/Items/${p['Id']}/Images/Primary';
      }
    }
    // Plex: Director tags with a picture.
    if (raw?['Director'] case final List directors) {
      for (final d in directors) {
        if (d is Map && d['tag'] == name && d['thumb'] is String) return d['thumb'] as String;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final mono = tokens(context);
    final fallback = ColoredBox(
      color: RetroColors.isActive(context) ? RetroColors.dusk : mono.surface,
      child: Center(
        child: initials.isEmpty
            ? AppIcon.retro(Symbols.person_rounded, size: 40, color: mono.textMuted)
            : Text(initials, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: mono.textMuted)),
      ),
    );
    return FutureBuilder<({String server, String path})?>(
      future: _picture,
      builder: (context, snapshot) {
        final p = snapshot.data;
        final external = ExternalPersonPicture(name: widget.name, fallback: fallback);
        if (p == null) return snapshot.connectionState == ConnectionState.done ? external : fallback;
        return OptimizedMediaImage(
          client: widget.client(p.server),
          imagePath: p.path,
          fit: BoxFit.cover,
          imageType: ImageType.avatar,
          fallbackIcon: Symbols.person_rounded,
          placeholder: (_, _) => fallback,
          errorWidget: (_, _, _) => external,
        );
      },
    );
  }
}

/// The titles behind a number, as a poster grid.
class _StatsDetailScreen extends StatefulWidget {
  const _StatsDetailScreen({
    required this.title,
    required this.entries,
    required this.client,
    required this.onOpen,
    required this.onMenu,
  });
  final String title;
  final List<_Entry> entries;
  final MediaServerClient? Function(String server) client;
  final Future<void> Function(String server, String? id) onOpen;
  final _EntryMenu onMenu;

  @override
  State<_StatsDetailScreen> createState() => _StatsDetailScreenState();
}

class _StatsDetailScreenState extends State<_StatsDetailScreen> {
  final _removed = <String>{};

  Future<bool> _menu(_Entry entry, Offset position) async {
    final excluded = await widget.onMenu(entry, position);
    if (excluded && mounted && entry.key != null) setState(() => _removed.add(entry.key!));
    return excluded;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final entries = [
      for (final e in widget.entries)
        if (!_removed.contains(e.key)) e,
    ];
    return Scaffold(
      appBar: AppBar(title: Text('$title · ${entries.length}')),
      body: GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.52,
        ),
        itemCount: entries.length,
        itemBuilder: (context, i) =>
            _PosterTile(entry: entries[i], client: widget.client, onOpen: widget.onOpen, onMenu: _menu),
      ),
    );
  }
}

class _BarsDetailScreen extends StatelessWidget {
  const _BarsDetailScreen({required this.title, required this.entries});
  final String title;
  final List<MapEntry<String, int>> entries;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(padding: const EdgeInsets.all(24), children: [_Bars(entries: entries)]),
  );
}
