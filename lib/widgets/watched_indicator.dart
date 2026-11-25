import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../services/settings_service.dart';
import '../theme/mono_tokens.dart';
import 'retro_pill.dart';
import 'app_icon.dart';
import 'media_progress_bar.dart';
import 'unwatched_count_badge.dart';

/// Size preset for [WatchedIndicator]: [standard] for grid/poster cards,
/// [compact] for dense surfaces (folder tree rows, episode thumbnails).
/// Add a preset here instead of hand-rolling a new overlay variant.
enum WatchedIndicatorSize {
  // Fork: the check, the unwatched count and the poster's median rating pill
  // share one height and one inset, so the top corners line up.
  standard(inset: 6, pillHeight: 18, countFontSize: 10.5, barRadius: 8, barMinHeight: 4),
  compact(inset: 3, pillHeight: 15, countFontSize: 9, barRadius: 6, barMinHeight: 3);

  const WatchedIndicatorSize({
    required this.inset,
    required this.pillHeight,
    required this.countFontSize,
    required this.barRadius,
    required this.barMinHeight,
  });

  /// Distance of the corner pills from the artwork's top and side edges.
  final double inset;

  /// Height of the check circle and the unwatched-count pill.
  final double pillHeight;
  final double countFontSize;
  final double barRadius;
  final double barMinHeight;
}

/// Watched/progress overlay for media artwork: watched checkmark,
/// unwatched-count pill (shows/seasons), active-progress bar, and season
/// completion bar. The single implementation behind every surface that
/// stamps watch state onto a poster/thumbnail. Callers that must react to
/// [SettingsService.showWatchedIndicators] or [SettingsService.showUnwatchedCount]
/// flipping wrap themselves in a [SettingsBuilder] on those prefs.
const _watchedFill = Color(0xFFC8379B);
const _watchedRim = Color(0xFFF07AC8);

class WatchedIndicator extends StatelessWidget {
  final MediaItem item;
  final WatchedIndicatorSize size;

  /// Overrides the settings read for the unwatched-count pill — pass it when
  /// the caller already watches [SettingsService.showUnwatchedCount] so pill
  /// visibility updates reactively with the caller's rebuilds.
  final bool? showUnwatchedCount;

  const WatchedIndicator({
    super.key,
    required this.item,
    this.size = WatchedIndicatorSize.standard,
    this.showUnwatchedCount,
  });

  @override
  Widget build(BuildContext context) {
    final bool showCount = showUnwatchedCount ?? SettingsService.instance.read(SettingsService.showUnwatchedCount);
    final bool showWatched = SettingsService.instance.read(SettingsService.showWatchedIndicators);
    final retro = isRetrowave(context);
    final hasActiveProgress = item.hasActiveProgress;
    final unwatched = item.unwatchedCount;
    final barRadius = BorderRadius.only(
      bottomLeft: Radius.circular(size.barRadius),
      bottomRight: Radius.circular(size.barRadius),
    );

    return Stack(
      children: [
        // Watched checkmark
        if (showWatched && item.isWatched && !hasActiveProgress)
          Positioned(
            top: size.inset,
            right: size.inset,
            // Fork: 10% larger than the other corner pills and filled with a
            // vivid (not glaring) magenta, so it reads at a glance.
            child: Container(
              width: size.pillHeight * 1.1,
              height: size.pillHeight * 1.1,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: retro ? _watchedFill : tokens(context).text,
                border: retro ? Border.all(color: _watchedRim) : null,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4)],
              ),
              child: AppIcon(
                Symbols.check_rounded,
                fill: 1,
                weight: 700,
                color: retro ? Colors.white : tokens(context).bg,
                size: (size.pillHeight * 1.1 * 0.66).roundToDouble(),
              ),
            ),
          ),
        // Unwatched count for shows/seasons
        if (showCount &&
            !item.isWatched &&
            (item.kind == MediaKind.show || item.kind == MediaKind.season) &&
            unwatched != null &&
            unwatched > 0)
          Positioned(
            top: size.inset,
            right: size.inset,
            child: UnwatchedCountBadge(count: unwatched, size: size.pillHeight, fontSize: size.countFontSize),
          ),
        // Progress bar for partially watched content (episodes/movies)
        if (hasActiveProgress)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: barRadius,
              child: MediaProgressBar(
                viewOffset: item.viewOffsetMs!,
                duration: item.durationMs!,
                minHeight: size.barMinHeight,
              ),
            ),
          ),
        // Progress bar for seasons (viewed leaves / total leaves).
        if (item.isSeason && item.isPartiallyWatched)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: barRadius,
              child: LinearProgressIndicator(
                value: item.leafWatchFraction,
                backgroundColor: tokens(context).outline,
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                minHeight: size.barMinHeight,
              ),
            ),
          ),
      ],
    );
  }
}
