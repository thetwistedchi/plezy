import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../i18n/retro_strings.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../providers/discover_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/desktop_app_bar.dart';

/// Fork: the next episodes of the shows you are watching (the shows on
/// Continue Watching / Next Up), with air dates from TVmaze. No account or
/// key needed.
class UpcomingEpisodesScreen extends StatefulWidget {
  const UpcomingEpisodesScreen({super.key});

  @override
  State<UpcomingEpisodesScreen> createState() => _UpcomingEpisodesScreenState();
}

typedef _Upcoming = ({String show, String? episodeName, int? season, int? number, DateTime airs, String? network});

class _UpcomingEpisodesScreenState extends State<UpcomingEpisodesScreen> {
  List<_Upcoming>? _items;
  int _shows = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final onDeck = context.read<DiscoverProvider>().onDeck;
    final shows = <String, MediaItem>{};
    for (final item in onDeck) {
      final showId = item.grandparentId ?? (item.isShow ? item.id : null);
      if (showId == null || item.serverId == null) continue;
      shows.putIfAbsent('${item.serverId}:$showId', () => item);
    }
    _shows = shows.length;
    final results = <_Upcoming>[];
    for (final entry in shows.entries) {
      final item = entry.value;
      final showId = item.grandparentId ?? item.id;
      try {
        final client = context.tryGetMediaClientForServer(ServerId(item.serverId!));
        if (client == null) continue;
        final ids = await client.fetchExternalIds(showId);
        final next = await _nextEpisode(tvdb: ids.tvdb, imdb: ids.imdb);
        if (next != null) {
          results.add((
            show: item.grandparentTitle ?? item.title ?? '',
            episodeName: next.name,
            season: next.season,
            number: next.number,
            airs: next.airs,
            network: next.network,
          ));
        }
      } catch (e) {
        appLogger.d('Upcoming: lookup failed for $showId', error: e);
      }
      if (!mounted) return;
    }
    results.sort((a, b) => a.airs.compareTo(b.airs));
    if (mounted) setState(() => _items = results);
  }

  static Future<({String? name, int? season, int? number, DateTime airs, String? network})?> _nextEpisode({
    int? tvdb,
    String? imdb,
  }) async {
    final query = tvdb != null ? {'thetvdb': '$tvdb'} : (imdb != null ? {'imdb': imdb} : null);
    if (query == null) return null;
    final lookup = await http.get(Uri.https('api.tvmaze.com', '/lookup/shows', query)).timeout(const Duration(seconds: 10));
    if (lookup.statusCode != 200) return null;
    final show = jsonDecode(lookup.body) as Map<String, dynamic>;
    final id = show['id'];
    if (id == null) return null;
    final full = await http
        .get(Uri.https('api.tvmaze.com', '/shows/$id', {'embed': 'nextepisode'}))
        .timeout(const Duration(seconds: 10));
    if (full.statusCode != 200) return null;
    final json = jsonDecode(full.body) as Map<String, dynamic>;
    final next = (json['_embedded'] as Map?)?['nextepisode'] as Map?;
    if (next == null) return null;
    final airs = DateTime.tryParse(next['airstamp'] as String? ?? '') ?? DateTime.tryParse(next['airdate'] as String? ?? '');
    if (airs == null) return null;
    return (
      name: next['name'] as String?,
      season: (next['season'] as num?)?.toInt(),
      number: (next['number'] as num?)?.toInt(),
      airs: airs.toLocal(),
      network: ((json['network'] ?? json['webChannel']) as Map?)?['name'] as String?,
    );
  }

  String _day(DateTime d) {
    final today = DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (days == 0) return RetroStrings.today;
    if (days == 1) return RetroStrings.tomorrow;
    return '${d.day}.${d.month}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final theme = Theme.of(context);
    final items = _items;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CustomAppBar(title: Text(RetroStrings.upcomingEpisodes)),
          if (items == null)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (items.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  _shows == 0 ? RetroStrings.upcomingNoShows : RetroStrings.upcomingNone,
                  style: TextStyle(color: mono.textMuted),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                final newDay = i == 0 || _day(items[i - 1].airs) != _day(e.airs);
                final code = e.season != null && e.number != null ? 'S${e.season} E${e.number}' : '';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (newDay)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
                        child: Text(_day(e.airs), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      title: Text(e.show),
                      subtitle: Text([code, ?e.episodeName, ?e.network].where((s) => s.isNotEmpty).join(' · ')),
                      trailing: Text(
                        '${e.airs.hour.toString().padLeft(2, '0')}:${e.airs.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(color: mono.textMuted),
                      ),
                    ),
                  ],
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
