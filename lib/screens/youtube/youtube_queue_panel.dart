import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../theme/player_style.dart';
import '../../widgets/app_icon.dart';
import 'youtube_strings.dart';
import '../../theme/retrowave_colors.dart';

/// The player's queue / watchlist beside the video: the playing order (jump,
/// drag to reorder, remove) and the newest subscription videos to add.
class YouTubeQueuePanel extends StatefulWidget {
  const YouTubeQueuePanel({
    super.key,
    required this.queue,
    required this.currentIndex,
    required this.onJump,
    required this.onRemove,
    required this.onReorder,
    required this.onAdd,
    required this.onClose,
  });

  final List<YouTubeVideo> queue;
  final int currentIndex;
  final ValueChanged<int> onJump;
  final ValueChanged<int> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<YouTubeVideo> onAdd;
  final VoidCallback onClose;

  @override
  State<YouTubeQueuePanel> createState() => _YouTubeQueuePanelState();
}

class _YouTubeQueuePanelState extends State<YouTubeQueuePanel> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final accent = playerActiveColor(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RetroColors.rock,
        border: Border(left: BorderSide(color: RetroColors.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
            child: Row(
              children: [
                Text(
                  YtStrings.watchlist,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text('${widget.queue.length}', style: const TextStyle(color: Colors.white54, fontSize: 16)),
                const Spacer(),
                IconButton(
                  tooltip: YtStrings.close,
                  onPressed: widget.onClose,
                  icon: const AppIcon(Symbols.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected) ? Color.lerp(accent, Colors.black, 0.55) : RetroColors.dusk,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white60,
                ),
                side: WidgetStateProperty.resolveWith(
                  (s) => BorderSide(color: s.contains(WidgetState.selected) ? accent : RetroColors.outline),
                ),
              ),
              segments: [
                ButtonSegment(value: false, label: Text(YtStrings.queue)),
                ButtonSegment(value: true, label: Text(YtStrings.addVideos)),
              ],
              selected: {_adding},
              onSelectionChanged: (s) => setState(() => _adding = s.first),
            ),
          ),
          const Divider(height: 1, color: RetroColors.divider),
          Expanded(child: _adding ? _buildAdd(accent) : _buildQueue(accent)),
        ],
      ),
    );
  }

  Widget _buildQueue(Color accent) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      buildDefaultDragHandles: false,
      itemCount: widget.queue.length,
      onReorder: widget.onReorder,
      itemBuilder: (context, i) {
        final video = widget.queue[i];
        final current = i == widget.currentIndex;
        return _VideoRow(
          key: ValueKey('q-${video.id}'),
          video: video,
          accent: accent,
          highlighted: current,
          subtitle: current ? YtStrings.nowPlaying : video.channelTitle,
          leading: ReorderableDragStartListener(
            index: i,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: current
                  ? AppIcon(Symbols.equalizer_rounded, color: accent, size: 20)
                  : const AppIcon(Symbols.drag_indicator_rounded, color: Colors.white38, size: 20),
            ),
          ),
          onTap: current ? null : () => widget.onJump(i),
          trailing: current
              ? null
              : IconButton(
                  tooltip: YtStrings.removeFromQueue,
                  onPressed: () => widget.onRemove(i),
                  icon: const AppIcon(Symbols.close_rounded, color: Colors.white54, size: 20),
                ),
        );
      },
    );
  }

  Widget _buildAdd(Color accent) {
    final settings = YouTubeSettings.instance;
    final queued = {for (final v in widget.queue) v.id};
    final feed = YouTubeService.instance.videos
        .where((v) => (settings.showShorts || !v.isShort) && (settings.showPremieres || !(v.isUpcoming || v.isLive)))
        .take(80)
        .toList();
    if (feed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(YtStrings.noFeedVideos, style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      itemCount: feed.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Text(
              YtStrings.addFromSubscriptions.toUpperCase(),
              style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3),
            ),
          );
        }
        final video = feed[i - 1];
        final added = queued.contains(video.id);
        return _VideoRow(
          key: ValueKey('a-${video.id}'),
          video: video,
          accent: accent,
          highlighted: false,
          subtitle: '${video.channelTitle} · ${YtStrings.age(video.publishedAt)}',
          onTap: added ? null : () => widget.onAdd(video),
          trailing: IconButton(
            tooltip: added ? YtStrings.inQueue : YtStrings.addToQueue,
            onPressed: added ? null : () => widget.onAdd(video),
            icon: AppIcon(
              added ? Symbols.check_rounded : Symbols.add_rounded,
              color: added ? accent : Colors.white,
              size: 22,
            ),
          ),
        );
      },
    );
  }
}

class _VideoRow extends StatelessWidget {
  const _VideoRow({
    super.key,
    required this.video,
    required this.accent,
    required this.highlighted,
    required this.subtitle,
    required this.onTap,
    this.leading,
    this.trailing,
  });

  final YouTubeVideo video;
  final Color accent;
  final bool highlighted;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? accent.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              ?leading,
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 120,
                  height: 68,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: RetroColors.dusk),
                      if (video.thumbnailUrl != null)
                        CachedNetworkImage(
                          imageUrl: video.thumbnailUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 480,
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      if (video.duration > Duration.zero)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              YtStrings.duration(video.duration),
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                    ],
                  ),
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
                        color: highlighted ? accent : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
