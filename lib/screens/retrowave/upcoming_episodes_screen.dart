import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/retro_strings.dart';
import '../../media/ids.dart';
import '../../media/media_server_client.dart';
import '../../providers/libraries_provider.dart';
import '../../services/retrowave/upcoming_episodes.dart';
import '../../services/settings_service.dart';
import '../../media/media_kind.dart';
import '../../utils/media_navigation_helper.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/desktop_app_bar.dart';

/// Fork: the next episodes of every show in your TV libraries, with air
/// dates from TVmaze. No account or key needed. Opened from the libraries
/// list; the same scan feeds the Upcoming row on Home.
class UpcomingEpisodesScreen extends StatefulWidget {
  const UpcomingEpisodesScreen({super.key});

  @override
  State<UpcomingEpisodesScreen> createState() => _UpcomingEpisodesScreenState();
}

class _UpcomingEpisodesScreenState extends State<UpcomingEpisodesScreen> {
  final _service = UpcomingEpisodes.instance;

  @override
  void initState() {
    super.initState();
    _service.all.addListener(_changed);
    _service.allProgress.addListener(_changed);
    _scan();
  }

  void _scan({bool force = false}) {
    final libraries = context.read<LibrariesProvider>().libraries;
    MediaServerClient? clientFor(String serverId) => context.tryGetMediaClientForServer(ServerId(serverId));
    unawaited(_service.refreshAll(libraries, clientFor, force: force));
  }

  /// Fork: which servers Upcoming reads.
  Widget _serverFilter() {
    final servers = <String, String>{
      for (final l in context.read<LibrariesProvider>().libraries)
        if (l.kind == MediaKind.show && l.serverId != null) l.serverId!: l.serverName ?? l.serverId!,
    };
    if (servers.length < 2) return const SizedBox.shrink();
    final svc = SettingsService.instance;
    final off = svc.read(SettingsService.upcomingServersOff).toSet();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in servers.entries)
            FilterChip(
              label: Text(e.value),
              selected: !off.contains(e.key),
              onSelected: (on) async {
                final next = {...off};
                on ? next.remove(e.key) : next.add(e.key);
                await svc.write(SettingsService.upcomingServersOff, next.toList());
                if (mounted) {
                  setState(() {});
                  _scan(force: true);
                }
              },
            ),
        ],
      ),
    );
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.all.removeListener(_changed);
    _service.allProgress.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final theme = Theme.of(context);
    final items = _service.all.value;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CustomAppBar(title: Text(RetroStrings.upcomingEpisodes)),
          SliverToBoxAdapter(child: _serverFilter()),
          if (_service.allProgress.value case final progress?)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                child: Text(
                  RetroStrings.upcomingChecking(progress.done, progress.total),
                  style: TextStyle(color: mono.textMuted),
                ),
              ),
            ),
          if (items == null)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (items.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  RetroStrings.upcomingNone,
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
