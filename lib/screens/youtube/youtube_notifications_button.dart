import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/youtube/youtube_notification_history.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import 'youtube_player_screen.dart';
import 'youtube_strings.dart';

/// Fork: the bell in the feed bar. Opens a panel with the new videos from
/// favourite channels; a click plays one, a right click (or long press)
/// removes it from the list.
class YouTubeNotificationsButton extends StatefulWidget {
  const YouTubeNotificationsButton({super.key});

  @override
  State<YouTubeNotificationsButton> createState() => _YouTubeNotificationsButtonState();
}

class _YouTubeNotificationsButtonState extends State<YouTubeNotificationsButton> {
  final _history = YouTubeNotificationHistory.instance;
  final _menu = MenuController();

  @override
  void initState() {
    super.initState();
    unawaited(_history.load());
  }

  Future<void> _play(YouTubeNotificationEntry entry) async {
    _menu.close();
    unawaited(_history.markRead(entry.video.id));
    await YouTubePlayerScreen.open(context, [entry.video]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _history,
      builder: (context, _) {
        final unread = _history.unread;
        return MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(-360, 4),
          menuChildren: [_panel(context)],
          builder: (context, controller, _) => IconButton(
            tooltip: unread > 0 ? YtStrings.notificationsUnread(unread) : YtStrings.notifications,
            onPressed: () => controller.isOpen ? controller.close() : controller.open(),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const AppIcon.retro(Symbols.notifications_rounded),
            ),
          ),
        );
      },
    );
  }

  Widget _panel(BuildContext context) {
    final mono = tokens(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _history,
      builder: (context, _) {
        final entries = _history.entries;
        return SizedBox(
          width: 420,
          height: 520,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        YtStrings.notifications,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: YtStrings.markAllRead,
                      onPressed: _history.unread == 0 ? null : () => unawaited(_history.markAllRead()),
                      icon: const AppIcon.retro(Symbols.done_all_rounded, size: 20),
                    ),
                    IconButton(
                      tooltip: YtStrings.clearNotifications,
                      onPressed: entries.isEmpty ? null : () => unawaited(_history.clear()),
                      icon: const AppIcon.retro(Symbols.clear_all_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            YtStrings.notificationsNone,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: mono.textMuted),
                          ),
                        ),
                      )
                    : Scrollbar(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: entries.length,
                          itemBuilder: (context, i) => _row(context, entries[i]),
                        ),
                      ),
              ),
              if (entries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    YtStrings.notificationsRemoveHint,
                    style: TextStyle(fontSize: 11, color: mono.textMuted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, YouTubeNotificationEntry entry) {
    final mono = tokens(context);
    final theme = Theme.of(context);
    final video = entry.video;
    void remove() => unawaited(_history.remove(video.id));
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () => unawaited(_play(entry)),
      onSecondaryTap: remove,
      onLongPress: remove,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 10,
              child: entry.read
                  ? null
                  : Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primary),
                    ),
            ),
            const SizedBox(width: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(mono.radiusSm),
              child: SizedBox(
                width: 112,
                height: 63,
                child: video.thumbnailUrl == null
                    ? ColoredBox(color: mono.surface)
                    : CachedNetworkImage(imageUrl: video.thumbnailUrl!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: entry.read ? FontWeight.w500 : FontWeight.w800,
                      color: entry.read ? mono.textMuted : mono.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${video.channelTitle} · ${YtStrings.age(video.publishedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: mono.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
