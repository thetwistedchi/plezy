import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../theme/player_style.dart';
import '../../widgets/app_icon.dart';
import 'youtube_strings.dart';

/// Recent videos of the playing video's channel, beside the player.
class YouTubeChannelPanel extends StatefulWidget {
  const YouTubeChannelPanel({
    super.key,
    required this.channelId,
    required this.channelTitle,
    required this.currentVideoId,
    required this.onPlay,
    required this.onOpenChannel,
    required this.onClose,
  });

  final String channelId;
  final String channelTitle;
  final String currentVideoId;
  final ValueChanged<YouTubeVideo> onPlay;
  final VoidCallback onOpenChannel;
  final VoidCallback onClose;

  @override
  State<YouTubeChannelPanel> createState() => _YouTubeChannelPanelState();
}

class _YouTubeChannelPanelState extends State<YouTubeChannelPanel> {
  List<YouTubeVideo>? _videos;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final videos = await YouTubeService.instance.channelFeed(widget.channelId);
      if (mounted) setState(() => _videos = videos);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = playerActiveColor(context);
    final settings = YouTubeSettings.instance;
    final videos = (_videos ?? const <YouTubeVideo>[])
        .where((v) => (settings.showShorts || !v.isShort) && (settings.showPremieres || !(v.isUpcoming || v.isLive)))
        .toList();
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0820),
        border: Border(left: BorderSide(color: Color(0x29F4ECFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    YtStrings.moreFrom(widget.channelTitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: YtStrings.openChannel,
                  onPressed: widget.onOpenChannel,
                  icon: const AppIcon(Symbols.account_box_rounded, color: Colors.white),
                ),
                IconButton(
                  tooltip: YtStrings.close,
                  onPressed: widget.onClose,
                  icon: const AppIcon(Symbols.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x1FF4ECFF)),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('$_error', style: const TextStyle(color: Colors.white70)),
                    ),
                  )
                : _videos == null
                ? Center(child: CircularProgressIndicator(color: accent))
                : videos.isEmpty
                ? Center(child: Text(YtStrings.channelEmpty, style: const TextStyle(color: Colors.white70)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: videos.length,
                    itemBuilder: (context, i) {
                      final video = videos[i];
                      return _ChannelVideoRow(
                        video: video,
                        playing: video.id == widget.currentVideoId,
                        accent: accent,
                        onTap: () => widget.onPlay(video),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: widget.onOpenChannel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: accent),
                minimumSize: const Size.fromHeight(44),
              ),
              icon: AppIcon(Symbols.account_box_rounded, color: accent),
              label: Text(YtStrings.openChannel),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelVideoRow extends StatelessWidget {
  const _ChannelVideoRow({required this.video, required this.playing, required this.accent, required this.onTap});

  final YouTubeVideo video;
  final bool playing;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = YouTubeSettings.instance.progressFraction(video.id);
    return InkWell(
      onTap: playing ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 160,
                height: 90,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFF1B1240)),
                    if (video.thumbnailUrl != null)
                      CachedNetworkImage(
                        imageUrl: video.thumbnailUrl!,
                        fit: BoxFit.cover,
                          memCacheWidth: 480,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    if (video.duration > Duration.zero)
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            YtStrings.duration(video.duration),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    if (progress != null && progress > 0)
                      Positioned(
                        left: 0,
                        bottom: 0,
                        height: 3,
                        width: 160 * progress,
                        child: ColoredBox(color: accent),
                      ),
                    if (playing)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: Center(child: AppIcon(Symbols.equalizer_rounded, color: accent, size: 28)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: playing ? accent : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    playing
                        ? YtStrings.nowPlaying
                        : [
                            if (video.viewCount > 0) YtStrings.views(video.viewCount),
                            YtStrings.age(video.publishedAt),
                          ].join(' · '),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
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
