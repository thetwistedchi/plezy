import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/retro_strings.dart';
import '../../media/ids.dart';
import '../../media/library_query.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../providers/libraries_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/desktop_app_bar.dart';

/// Fork: watch statistics from the libraries' watched states: hours, films
/// and episodes, favourite genres and the last twelve months. Read from the
/// servers, so it covers everything watched on any device.
class WatchStatsScreen extends StatefulWidget {
  const WatchStatsScreen({super.key});

  @override
  State<WatchStatsScreen> createState() => _WatchStatsScreenState();
}

class _Stats {
  int movies = 0;
  int episodes = 0;
  int shows = 0;
  double hours = 0;
  final genres = <String, int>{};
  final months = <String, int>{};
}

class _WatchStatsScreenState extends State<WatchStatsScreen> {
  _Stats? _stats;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final stats = _Stats();
    final libraries = context.read<LibrariesProvider>().libraries;
    for (final library in libraries) {
      if (library.kind != MediaKind.movie && library.kind != MediaKind.show) continue;
      final serverId = library.serverId;
      if (serverId == null) continue;
      try {
        final client = context.tryGetMediaClientForServer(ServerId(serverId));
        if (client == null) continue;
        final page = await client.fetchLibraryPagedContent(
          library.id,
          libraryKind: library.kind,
          query: LibraryQuery(kind: library.kind, limit: 5000),
        );
        for (final item in page.items) {
          _count(stats, item);
        }
      } catch (e) {
        appLogger.d('Watch stats: ${library.title} failed', error: e);
      }
      if (!mounted) return;
    }
    if (mounted) setState(() => _stats = stats);
  }

  void _count(_Stats stats, MediaItem item) {
    final runtimeH = (item.durationMs ?? 0) / 3600000;
    int watchedUnits;
    if (item.kind == MediaKind.movie) {
      watchedUnits = (item.viewCount ?? 0) > 0 ? 1 : 0;
      stats.movies += watchedUnits;
      stats.hours += runtimeH * (item.viewCount ?? 0);
    } else {
      watchedUnits = item.viewedLeafCount ?? 0;
      stats.episodes += watchedUnits;
      if (watchedUnits > 0) stats.shows++;
      stats.hours += runtimeH * watchedUnits;
    }
    if (watchedUnits == 0) return;
    for (final g in item.genres ?? const <String>[]) {
      stats.genres[g] = (stats.genres[g] ?? 0) + watchedUnits;
    }
    final last = item.lastViewedAt;
    if (last != null && last > 0) {
      final d = DateTime.fromMillisecondsSinceEpoch(last > 100000000000 ? last : last * 1000);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      stats.months[key] = (stats.months[key] ?? 0) + 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final stats = _stats;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CustomAppBar(title: Text(RetroStrings.watchStats)),
          if (stats == null)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList.list(
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _tile(theme, mono, '${stats.hours.round()}', RetroStrings.statsHours),
                      _tile(theme, mono, '${stats.movies}', RetroStrings.statsMovies),
                      _tile(theme, mono, '${stats.episodes}', RetroStrings.statsEpisodes),
                      _tile(theme, mono, '${stats.shows}', RetroStrings.statsShows),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(RetroStrings.statsGenres, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ..._bars(theme, mono, (stats.genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(10)),
                  const SizedBox(height: 28),
                  Text(RetroStrings.statsMonths, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(RetroStrings.statsMonthsHint, style: TextStyle(color: mono.textMuted)),
                  const SizedBox(height: 10),
                  ..._bars(theme, mono, _lastTwelve(stats.months)),
                ],
              ),
            ),
        ],
      ),
    );
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
              SizedBox(width: 140, child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
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
              SizedBox(width: 48, child: Text('${e.value}', textAlign: TextAlign.end, style: TextStyle(color: mono.textMuted))),
            ],
          ),
        ),
    ];
  }
}
