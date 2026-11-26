import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/retro_strings.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../services/retrowave/upcoming_episodes.dart';
import '../../services/settings_service.dart';
import '../../utils/media_navigation_helper.dart';
import '../../widgets/settings_builder.dart';
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

class _UpcomingEpisodesScreenState extends State<UpcomingEpisodesScreen> {
  List<UpcomingEpisode>? _items;
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
      final serverId = item.serverId;
      if (showId == null || serverId == null || shows.containsKey('$serverId:$showId')) continue;
      try {
        final client = context.tryGetMediaClientForServer(ServerId(serverId));
        final show = item.isShow ? item : await client?.fetchItem(showId);
        if (show != null) shows['$serverId:$showId'] = show;
      } catch (e) {
        appLogger.d('Upcoming: show $showId failed', error: e);
      }
      if (!mounted) return;
    }
    _shows = shows.length;
    final results = await UpcomingEpisodes.instance.forShows(
      shows.values.toList(),
      (show) => context.tryGetMediaClientForServer(serverIdOrNull(show.serverId)),
      isCancelled: () => !mounted,
    );
    if (mounted) setState(() => _items = results);
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
          SliverToBoxAdapter(
            child: SettingsBuilder(
              prefs: const [SettingsService.upcomingOnHome],
              builder: (context) => SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(RetroStrings.upcomingOnHome),
                subtitle: Text(RetroStrings.upcomingOnHomeDescription),
                value: SettingsService.instance.read(SettingsService.upcomingOnHome),
                onChanged: (v) => unawaited(SettingsService.instance.write(SettingsService.upcomingOnHome, v)),
              ),
            ),
          ),
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
                final newDay = i == 0 || UpcomingEpisodes.dayLabel(items[i - 1].airs) != UpcomingEpisodes.dayLabel(e.airs);
                final code = e.code;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (newDay)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
                        child: Text(UpcomingEpisodes.dayLabel(e.airs), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      title: Text(e.show.title ?? ''),
                      onTap: () => unawaited(navigateToMediaItem(context, e.show)),
                      subtitle: Text([code, ?e.name, ?e.network].where((s) => s.isNotEmpty).join(' · ')),
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
