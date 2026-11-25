import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../services/settings_service.dart';
import '../theme/mono_tokens.dart';
import '../utils/platform_detector.dart';
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
            child: retro
                // Fork: a neon sign: dark disc, magenta tube with a pale pink
                // core for ring and check, and an even glow (off on TV).
                ? RepaintBoundary(
                    child: CustomPaint(
                      size: Size.square(size.pillHeight * 1.1),
                      painter: NeonCheckPainter(glow: !PlatformDetector.isTV()),
                    ),
                  )
                : Container(
                    width: size.pillHeight * 1.1,
                    height: size.pillHeight * 1.1,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens(context).text,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4)],
                    ),
                    child: AppIcon(
                      Symbols.check_rounded,
                      fill: 1,
                      weight: 700,
                      color: tokens(context).bg,
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
                // Fork: the neon magenta of the watched mark.
                valueColor: retro ? NeonCheckPainter.tube : null,
                backgroundColor: retro ? NeonCheckPainter.disc : null,
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

/// Fork: the retrowave watched mark drawn as a neon sign. A dark disc keeps
/// it readable on bright posters; ring and check are one magenta tube with a
/// pale pink core. [glow] adds an even magenta halo (a blurred stroke; left
/// off on TV to keep long poster grids light).
class NeonCheckPainter extends CustomPainter {
  const NeonCheckPainter({this.glow = true});

  final bool glow;

  static const tube = Color(0xFFFF28C8);
  static const core = Color(0xFFFFD6F4);
  static const halo = Color(0xFFD600A0);
  static const disc = Color(0xE6140327);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final tubeWidth = (outer * 0.2).clamp(1.6, 3.0);
    final r = outer - tubeWidth / 2;
    final k = r / 19;
    final check = Path()
      ..moveTo(center.dx - 8 * k, center.dy + 0.5 * k)
      ..lineTo(center.dx - 2.5 * k, center.dy + 6 * k)
      ..lineTo(center.dx + 8.5 * k, center.dy - 5.5 * k);

    Paint stroke(Color color, double width, {MaskFilter? blur}) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = blur;

    void tubes(Paint paint) {
      canvas.drawCircle(center, r, paint);
      canvas.drawPath(check, paint);
    }

    if (glow) {
      tubes(stroke(halo.withValues(alpha: 0.75), tubeWidth * 1.6, blur: MaskFilter.blur(BlurStyle.normal, outer * 0.35)));
    }
    canvas.drawCircle(center, r - tubeWidth / 2, Paint()..color = disc);
    if (glow) {
      tubes(stroke(halo.withValues(alpha: 0.5), tubeWidth, blur: MaskFilter.blur(BlurStyle.normal, outer * 0.12)));
    }
    tubes(stroke(tube, tubeWidth));
    tubes(stroke(core, tubeWidth * 0.42));
  }

  @override
  bool shouldRepaint(NeonCheckPainter oldDelegate) => oldDelegate.glow != glow;
}
