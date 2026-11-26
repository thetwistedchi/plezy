import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/youtube/youtube_notification_history.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import 'youtube_player_screen.dart';
import 'youtube_strings.dart';

/// Fork: the history of new videos from favourite channels.
class YouTubeNotificationsScreen extends StatefulWidget {
  const YouTubeNotificationsScreen({super.key});

  @override
  State<YouTubeNotificationsScreen> createState() => _YouTubeNotificationsScreenState();
}

class _YouTubeNotificationsScreenState extends State<YouTubeNotificationsScreen> {
  final _history = YouTubeNotificationHistory.instance;

  @override
  void initState() {
    super.initState();
    _history.addListener(_changed);
    unawaited(_history.load());
  }

  @override
  void dispose() {
    _history.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _open(YouTubeNotificationEntry entry) async {
    unawaited(_history.markRead(entry.video.id));
    await YouTubePlayerScreen.open(context, [entry.video]);
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final theme = Theme.of(context);
    final entries = _history.entries;
    return Scaffold(
      appBar: AppBar(
        title: Text(YtStrings.notifications),
        actions: [
          IconButton(
            tooltip: YtStrings.markAllRead,
            onPressed: _history.unread == 0 ? null : () => unawaited(_history.markAllRead()),
            icon: const AppIcon.retro(Symbols.done_all_rounded),
          ),
          IconButton(
            tooltip: YtStrings.clearNotifications,
            onPressed: entries.isEmpty ? null : () => unawaited(_history.clear()),
            icon: const AppIcon.retro(Symbols.clear_all_rounded),
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(YtStrings.notificationsNone, style: TextStyle(color: mono.textMuted)),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final entry = entries[i];
                final video = entry.video;
                return InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(mono.radiusSm),
                  onTap: () => unawaited(_open(entry)),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          child: entry.read
                              ? null
                              : Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(mono.radiusSm),
                          child: SizedBox(
                            width: 160,
                            height: 90,
                            child: video.thumbnailUrl == null
                                ? ColoredBox(color: mono.surface)
                                : CachedNetworkImage(imageUrl: video.thumbnailUrl!, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: entry.read ? FontWeight.w500 : FontWeight.w800,
                                  color: entry.read ? mono.textMuted : mono.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${video.channelTitle} · ${YtStrings.age(video.publishedAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: mono.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
