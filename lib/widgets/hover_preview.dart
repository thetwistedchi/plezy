import 'package:flutter/material.dart';

import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../services/ratings/rating_median_cache.dart';
import '../services/settings_service.dart';
import '../theme/retrowave_colors.dart';
import '../utils/formatters.dart';
import '../utils/platform_detector.dart';

/// Desktop: after resting the mouse on a poster, a small card with the plot,
/// runtime, genres and the rating median. Nothing is fetched; it shows what
/// the listing already carries.
class HoverPreview extends StatelessWidget {
  const HoverPreview({super.key, required this.item, required this.child});

  final MediaItem item;
  final Widget child;

  static bool appliesTo(MediaItem item) {
    if (!PlatformDetector.isDesktopOS() || PlatformDetector.isTV()) return false;
    if (!(item.isMovie || item.isShow || item.isSeason || item.isEpisode)) return false;
    return SettingsService.instance.read(SettingsService.hoverPreview);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retro = RetroColors.isActive(context);
    final chrome = PlayerChrome.of(context);
    final textColor = retro ? RetroColors.moon : theme.colorScheme.onSurface;
    final muted = textColor.withValues(alpha: 0.72);

    final facts = <String>[
      if (item.year != null) '${item.year}',
      if ((item.durationMs ?? 0) > 0) formatDurationTextual(item.durationMs!),
      ...?item.genres?.take(3),
    ];
    final median = RatingMedianCache.instance.medianFor(item);
    if (median != null) facts.add('★ ${median.score}');

    return Tooltip(
      waitDuration: Duration(milliseconds: SettingsService.instance.read(SettingsService.hoverPreviewDelayMs)),
      showDuration: const Duration(seconds: 30),
      excludeFromSemantics: true,
      preferBelow: false,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: chrome.panel.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: chrome.outline),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      richMessage: WidgetSpan(
        child: SizedBox(
          width: 320,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.isEpisode && item.grandparentTitle != null ? '${item.grandparentTitle} · ${item.title ?? ''}' : (item.title ?? ''),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: retro ? retroPreviewTitle : textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(facts.join(' · '), style: theme.textTheme.labelMedium?.copyWith(color: muted)),
                ],
                // Seasons and some episodes carry no plot in lists.
                if ((item.summary ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.summary!.trim(),
                    maxLines: 7,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: textColor, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Periwinkle, the colour of row headings and card titles.
const retroPreviewTitle = Color(0xFF9DB4FF);
