import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../widgets/app_icon.dart';
import 'youtube_player_screen.dart';
import 'youtube_strings.dart';

/// Fork: how "Play all" lines up a group's or channel's videos.
enum YouTubePlayAllMode { unwatchedOldest, unwatchedNewest, allNewest, shuffle }

/// [videos] in the order of [mode]; premieres and streams not started are
/// left out. At most 200, so the queue stays manageable.
List<YouTubeVideo> playAllOrder(List<YouTubeVideo> videos, YouTubePlayAllMode mode) {
  final settings = YouTubeSettings.instance;
  final playable = [for (final v in videos) if (!v.isUpcoming) v];
  final list = switch (mode) {
    YouTubePlayAllMode.unwatchedOldest || YouTubePlayAllMode.unwatchedNewest => [
      for (final v in playable) if (!settings.isWatched(v.id)) v,
    ],
    _ => playable,
  };
  switch (mode) {
    case YouTubePlayAllMode.unwatchedOldest:
      list.sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
    case YouTubePlayAllMode.unwatchedNewest || YouTubePlayAllMode.allNewest:
      list.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    case YouTubePlayAllMode.shuffle:
      list.shuffle(math.Random());
  }
  return list.take(200).toList();
}

/// A ▶ button with the "Play all" choices for [videos] (read when picked).
class YouTubePlayAllButton extends StatelessWidget {
  const YouTubePlayAllButton({super.key, required this.videos});

  final List<YouTubeVideo> Function() videos;

  static String _label(YouTubePlayAllMode mode) => switch (mode) {
    YouTubePlayAllMode.unwatchedOldest => YtStrings.playAllOldest,
    YouTubePlayAllMode.unwatchedNewest => YtStrings.playAllNewest,
    YouTubePlayAllMode.allNewest => YtStrings.playAllEverythingNewest,
    YouTubePlayAllMode.shuffle => YtStrings.playAllShuffle,
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<YouTubePlayAllMode>(
      tooltip: YtStrings.playAll,
      onSelected: (mode) {
        final queue = playAllOrder(videos(), mode);
        if (queue.isEmpty) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(YtStrings.nothingToPlay)));
          return;
        }
        unawaited(YouTubePlayerScreen.open(context, queue));
      },
      itemBuilder: (_) => [
        for (final mode in YouTubePlayAllMode.values) PopupMenuItem(value: mode, child: Text(_label(mode))),
      ],
      icon: const AppIcon.retro(Symbols.play_circle_rounded),
    );
  }
}
