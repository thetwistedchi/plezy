import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/retro_strings.dart';
import '../../media/ids.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/media_server_client.dart';
import '../../providers/libraries_provider.dart';
import '../../services/retrowave/watch_stats.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/desktop_app_bar.dart';

/// Fork: watch statistics from the libraries' watched states, kept on the
/// device so they open at once. Filters by server, library and period;
/// genres, decades, people, shows (finished, going, put aside), weekdays
/// and hours, streaks and a year in review.
class WatchStatsScreen extends StatefulWidget {
  const WatchStatsScreen({super.key});

  @override
  State<WatchStatsScreen> createState() => _WatchStatsScreenState();
}

class _WatchStatsScreenState extends State<WatchStatsScreen> {
  WatchData? _data;
  bool _loading = false;
  String? _reading;
  String? _server;
  String? _library;
  StatsPeriod _period = StatsPeriod.allTime;

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
      // Older than a day: refresh in the background.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final data = _data;
    final libraries = _libraries;
    final servers = <String, String>{
      for (final l in libraries) l.serverId!: l.serverName ?? l.serverId!,
    };
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CustomAppBar(
            title: Text(RetroStrings.watchStats),
            actions: [
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
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
                  ..._content(theme, mono, WatchSummary(data, server: _server, library: _library, period: _period)),
                  const SizedBox(height: 32),
                  ..._yearInReview(theme, mono, WatchSummary(data, server: _server, library: _library, period: StatsPeriod.thisYear)),
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
    final shownLibraries = [for (final l in libraries) if (_server == null || l.serverId == _server) l];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
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
        DropdownButton<String?>(
          value: shownLibraries.any((l) => l.globalKey == _library) ? _library : null,
          items: [
            DropdownMenuItem(value: null, child: Text(RetroStrings.statsAllLibraries)),
            for (final l in shownLibraries) DropdownMenuItem(value: l.globalKey, child: Text(l.title)),
          ],
          onChanged: (v) => setState(() => _library = v),
        ),
      ],
    );
  }

  Widget _heading(ThemeData theme, String text, {String? hint, MonoTokens? mono}) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (hint != null && mono != null) Text(hint, style: TextStyle(color: mono.textMuted)),
      ],
    ),
  );

  List<Widget> _content(ThemeData theme, MonoTokens mono, WatchSummary s) {
    MapEntry<String, int> e(String k, int v) => MapEntry(k, v);
    List<MapEntry<String, int>> topOf(Map<String, int> map, [int n = 10]) =>
        (map.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(n).toList();
    final weekdayNames = RetroStrings.weekdaysShort;
    return [
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _tile(theme, mono, '${s.hours.round()}', RetroStrings.statsHours),
          _tile(theme, mono, '${s.movies}', RetroStrings.statsMovies),
          _tile(theme, mono, '${s.episodes}', RetroStrings.statsEpisodes),
          _tile(theme, mono, '${s.shows}', RetroStrings.statsShows),
          _tile(theme, mono, '${s.longestStreak}', RetroStrings.statsLongestStreak),
          _tile(theme, mono, '${s.currentStreak}', RetroStrings.statsCurrentStreak),
        ],
      ),
      if (_period != StatsPeriod.allTime) ...[
        const SizedBox(height: 8),
        Text(RetroStrings.statsPeriodHint, style: TextStyle(color: mono.textMuted)),
      ],
      if (s.genres.isNotEmpty) ...[_heading(theme, RetroStrings.statsGenres), ..._bars(theme, mono, topOf(s.genres))],
      if (s.decades.isNotEmpty) ...[
        _heading(theme, RetroStrings.statsDecades),
        ..._bars(theme, mono, s.decades.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      ],
      if (s.people.isNotEmpty) ...[
        _heading(theme, RetroStrings.statsPeople, hint: RetroStrings.statsPeopleHint, mono: mono),
        ..._bars(theme, mono, topOf(s.people)),
      ],
      if (s.topShows.isNotEmpty) ...[_heading(theme, RetroStrings.statsTopShows), ..._bars(theme, mono, s.topShows)],
      if (s.rewatched.isNotEmpty) ...[_heading(theme, RetroStrings.statsRewatched), ..._bars(theme, mono, topOf(s.rewatched))],
      if (s.finished.isNotEmpty || s.inProgress.isNotEmpty || s.abandoned.isNotEmpty) ...[
        _heading(theme, RetroStrings.statsShowProgress, hint: RetroStrings.statsShowProgressHint, mono: mono),
        ..._bars(theme, mono, [
          e(RetroStrings.statsFinished, s.finished.length),
          e(RetroStrings.statsInProgress, s.inProgress.length),
          e(RetroStrings.statsAbandoned, s.abandoned.length),
        ]),
        if (s.abandoned.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${RetroStrings.statsAbandoned}: ${(s.abandoned..sort()).take(12).join(', ')}${s.abandoned.length > 12 ? ' …' : ''}',
            style: TextStyle(color: mono.textMuted),
          ),
        ],
      ],
      if (s.activeDays > 0) ...[
        _heading(theme, RetroStrings.statsWeekdays, hint: RetroStrings.statsDatesHint, mono: mono),
        ..._bars(theme, mono, [for (var i = 0; i < 7; i++) e(weekdayNames[i], s.weekdays[i])]),
        _heading(theme, RetroStrings.statsHoursOfDay),
        _hourChart(theme, mono, s.hoursOfDay),
        _heading(theme, RetroStrings.statsMonths),
        ..._bars(theme, mono, _lastTwelve(s.months)),
      ],
    ];
  }

  List<Widget> _yearInReview(ThemeData theme, MonoTokens mono, WatchSummary y) {
    if (y.movies + y.episodes == 0) return const [];
    final year = DateTime.now().year;
    String month(String key) {
      final parts = key.split('-');
      return parts.length == 2 ? RetroStrings.monthName(int.tryParse(parts[1]) ?? 1) : key;
    }

    final lines = <(String, String)>[
      (RetroStrings.statsHours, '${y.hours.round()}'),
      (RetroStrings.statsMovies, '${y.movies}'),
      (RetroStrings.statsEpisodes, '${y.episodes}'),
      (RetroStrings.statsActiveDays, '${y.activeDays}'),
      if (y.topGenre case final g?) (RetroStrings.statsTopGenre, g),
      if (y.topShows.isNotEmpty) (RetroStrings.statsTopShow, y.topShows.first.key),
      if (y.topPerson case final p?) (RetroStrings.statsTopPerson, p),
      if (y.busiestMonth case final m?) (RetroStrings.statsBusiestMonth, month(m)),
      (RetroStrings.statsLongestStreak, '${y.longestStreak}'),
    ];
    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: mono.surface,
          borderRadius: BorderRadius.circular(mono.radiusMd),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              RetroStrings.statsYearInReview(year),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final (label, value) in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 200, child: Text(label, style: TextStyle(color: mono.textMuted))),
                    Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Iterable<MapEntry<String, int>> _lastTwelve(Map<String, int> months) {
    final now = DateTime.now();
    return [
      for (var i = 11; i >= 0; i--)
        () {
          final d = DateTime(now.year, now.month - i);
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          return MapEntry('${d.month.toString().padLeft(2, '0')}/${d.year}', months[key] ?? 0);
        }(),
    ];
  }

  Widget _hourChart(ThemeData theme, MonoTokens mono, List<int> hours) {
    final max = hours.fold<int>(1, (m, v) => v > m ? v : m);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var h = 0; h < 24; h++)
            Expanded(
              child: Tooltip(
                message: '$h:00 · ${hours[h]}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 90 * hours[h] / max,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(h % 3 == 0 ? '$h' : '', style: TextStyle(fontSize: 11, color: mono.textMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(ThemeData theme, MonoTokens mono, String value, String label) => Container(
    width: 180,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: mono.surface,
      borderRadius: BorderRadius.circular(mono.radiusMd),
      border: Border.all(color: mono.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: mono.textMuted)),
      ],
    ),
  );

  List<Widget> _bars(ThemeData theme, MonoTokens mono, Iterable<MapEntry<String, int>> entries) {
    final list = entries.toList();
    final max = list.fold<int>(1, (m, e) => e.value > m ? e.value : m);
    return [
      for (final e in list)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(width: 180, child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 14,
                      width: c.maxWidth * e.value / max,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(7),
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
    ];
  }
}
