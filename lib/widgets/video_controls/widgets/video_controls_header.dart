import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:plezy/utils/formatters.dart';

import '../../../media/media_item.dart';
import '../../../i18n/strings.g.dart';
import '../../../watch_together/widgets/watch_together_overlay.dart';
import '../../../watch_together/providers/watch_together_provider.dart';
import '../../app_bar_back_button.dart';
import '../../system_clock.dart';

/// Header layout style for video controls
enum VideoHeaderStyle {
  /// Multi-line: Series name on first line, episode info on second line
  multiLine,

  /// Single-line: All info combined with separators (for macOS)
  singleLine,
}

/// Shared header widget for video controls with back button and title.
///
/// Displays the video title with optional series/episode information.
/// Supports both single-line (macOS) and multi-line (other platforms) layouts.
class VideoControlsHeader extends StatelessWidget {
  final MediaItem metadata;
  final VideoHeaderStyle style;

  /// Optional trailing widget (e.g., track/chapter controls)
  final Widget? trailing;

  /// Optional callback for back button. If null, defaults to Navigator.pop(true).
  final VoidCallback? onBack;
  final VoidCallback? onCancelAutoHide;
  final VoidCallback? onStartAutoHide;

  /// Whether to show the system clock. Off for a portrait phone, where the
  /// header is too narrow to fit the clock beside the title and trailing
  /// controls.
  final bool showClock;

  /// Makes the title clickable (desktop): the series name opens the series
  /// (`true`), the episode part or a movie's title opens the item (`false`).
  final void Function(bool series)? onOpenDetails;

  const VideoControlsHeader({
    super.key,
    required this.metadata,
    this.style = VideoHeaderStyle.multiLine,
    this.trailing,
    this.onBack,
    this.onCancelAutoHide,
    this.onStartAutoHide,
    this.showClock = true,
    this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final itemTitle = metadata.title ?? t.common.unknown;
    return Row(
      children: [
        AppBarBackButton(style: BackButtonStyle.video, onPressed: onBack ?? () => Navigator.of(context).pop(true)),
        const SizedBox(width: 16),
        Expanded(
          child: style == VideoHeaderStyle.singleLine
              ? _buildSingleLineTitle(itemTitle)
              : _buildMultiLineTitle(itemTitle),
        ),
        Selector<WatchTogetherProvider, bool>(
          selector: (_, p) => p.isInSession,
          builder: (context, inSession, child) {
            if (!inSession) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: WatchTogetherSessionIndicator(
                onCancelAutoHide: onCancelAutoHide,
                onStartAutoHide: onStartAutoHide,
              ),
            );
          },
        ),
        if (showClock)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SystemClock(
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: .w500),
            ),
          ),
        ?trailing,
      ],
    );
  }

  Widget _buildSingleLineTitle(String itemTitle) {
    final seriesName = metadata.grandparentTitle ?? itemTitle;
    final hasEpisodeInfo = metadata.parentIndex != null && metadata.index != null;

    final List<String> parts = [seriesName];

    if (hasEpisodeInfo) {
      parts.add('S${metadata.parentIndex}E${metadata.index}');
      parts.add(itemTitle);
    }

    return Text(
      toBulletedString(parts),
      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: .w500),
      maxLines: 1,
      overflow: .ellipsis,
    );
  }

  Widget _buildMultiLineTitle(String itemTitle) {
    final hasEpisodeInfo = metadata.parentIndex != null && metadata.index != null;
    final episodeParts = [
      if (hasEpisodeInfo) ...['S${metadata.parentIndex}', 'E${metadata.index}', itemTitle],
    ];
    final duration = metadata.durationMs == null ? null : formatDurationTextual(metadata.durationMs!);
    final open = onOpenDetails;
    final hasSeries = metadata.grandparentTitle != null;
    const secondStyle = TextStyle(color: Colors.white70, fontSize: 14);

    return Column(
      crossAxisAlignment: .start,
      children: [
        _HeaderLink(
          onTap: open == null ? null : () => open(hasSeries),
          child: Text(
            metadata.grandparentTitle ?? itemTitle,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: .bold),
            maxLines: 1,
            overflow: .ellipsis,
          ),
        ),
        if (episodeParts.isNotEmpty || duration != null)
          Row(
            children: [
              if (episodeParts.isNotEmpty)
                Flexible(
                  child: _HeaderLink(
                    onTap: open == null ? null : () => open(false),
                    child: Text(toBulletedString(episodeParts), style: secondStyle, maxLines: 1, overflow: .ellipsis),
                  ),
                ),
              if (duration != null)
                Text(
                  episodeParts.isEmpty ? duration : ' · $duration',
                  style: secondStyle,
                  maxLines: 1,
                ),
            ],
          ),
      ],
    );
  }
}

/// A title part that opens a details page: pointer cursor and an underline
/// while hovered. Plain text when [onTap] is null.
class _HeaderLink extends StatefulWidget {
  const _HeaderLink({required this.child, this.onTap});

  final Text child;
  final VoidCallback? onTap;

  @override
  State<_HeaderLink> createState() => _HeaderLinkState();
}

class _HeaderLinkState extends State<_HeaderLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    if (onTap == null) return widget.child;
    final text = widget.child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(
          text.data ?? '',
          style: (text.style ?? const TextStyle()).copyWith(
            decoration: _hovered ? TextDecoration.underline : TextDecoration.none,
            decorationColor: text.style?.color,
          ),
          maxLines: text.maxLines,
          overflow: text.overflow,
        ),
      ),
    );
  }
}
