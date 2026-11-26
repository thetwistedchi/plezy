import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/youtube/youtube_service.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import 'youtube_player_screen.dart';
import 'youtube_routes.dart';
import 'youtube_strings.dart';

/// Fork: a playlist's videos as an overview; play all or start anywhere.
class YouTubePlaylistScreen extends StatefulWidget {
  const YouTubePlaylistScreen({super.key, required this.playlistId, required this.title});

  final String playlistId;
  final String title;

  static Future<void> open(BuildContext context, {required String playlistId, required String title}) =>
      Navigator.of(context).push(
        ytRoute<void>('playlist', (_) => YouTubePlaylistScreen(playlistId: playlistId, title: title)),
      );

  @override
  State<YouTubePlaylistScreen> createState() => _YouTubePlaylistScreenState();
}

class _YouTubePlaylistScreenState extends State<YouTubePlaylistScreen> {
  List<YouTubeVideo>? _videos;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final videos = await YouTubeService.instance.playlistVideos(widget.playlistId);
      if (mounted) setState(() => _videos = videos);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _play(int index) {
    final videos = _videos;
    if (videos == null || videos.isEmpty) return;
    unawaited(YouTubePlayerScreen.open(context, videos, startIndex: index));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final videos = _videos;
    final total = videos?.fold<Duration>(Duration.zero, (sum, v) => sum + v.duration) ?? Duration.zero;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _failed
          ? Center(child: Text(YtStrings.playlistFailed, style: TextStyle(color: mono.textMuted)))
          : videos == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
                  sliver: SliverToBoxAdapter(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          [
                            YtStrings.videoCount(videos.length),
                            if (total > Duration.zero) YtStrings.duration(total),
                          ].join(' · '),
                          style: theme.textTheme.bodyLarge?.copyWith(color: mono.textMuted),
                        ),
                        FilledButton.icon(
                          onPressed: videos.isEmpty ? null : () => _play(0),
                          icon: const AppIcon(Symbols.play_arrow_rounded, fill: 1),
                          label: Text(YtStrings.playAll),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  sliver: SliverList.builder(
                    itemCount: videos.length,
                    itemBuilder: (context, i) {
                      final v = videos[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(mono.radiusMd),
                        onTap: () => _play(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text('${i + 1}', style: TextStyle(color: mono.textMuted)),
                              ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(mono.radiusSm),
                                child: SizedBox(
                                  width: 160,
                                  height: 90,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (v.thumbnailUrl case final url?)
                                        CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                                      else
                                        ColoredBox(color: mono.surface),
                                      if (v.duration > Duration.zero)
                                        Positioned(
                                          right: 4,
                                          bottom: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            color: Colors.black.withValues(alpha: 0.75),
                                            child: Text(
                                              YtStrings.duration(v.duration),
                                              style: const TextStyle(color: Colors.white, fontSize: 11),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        v.channelTitle,
                                        if (v.viewCount > 0) YtStrings.views(v.viewCount),
                                      ].where((s) => s.isNotEmpty).join(' · '),
                                      style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
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
                ),
              ],
            ),
    );
  }
}
