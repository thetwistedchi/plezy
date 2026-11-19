import 'package:flutter/material.dart';

import '../../../media/media_display_criteria.dart';
import '../../../theme/player_style.dart';

/// Small outlined "4K · DV" style badge for the player's bottom bar, built
/// from the playing version's display criteria. Shows nothing when the
/// server reported neither a size nor a dynamic range.
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.criteria, this.isTranscoding = false, this.onTap, this.tooltip});

  final MediaDisplayCriteria? criteria;

  /// A transcode is re-encoded to SDR at the chosen quality, so the source's
  /// labels would be wrong; the badge hides.
  final bool isTranscoding;

  /// Fork: makes the badge a button (opens the file info).
  final VoidCallback? onTap;
  final String? tooltip;

  /// "4K", "1440p", "1080p", "720p", "SD" from the frame size.
  static String? resolutionLabel(int? width, int? height) {
    if ((width ?? 0) <= 0 || (height ?? 0) <= 0) return null;
    final w = width!, h = height!;
    if (w >= 3200 || h >= 2000) return '4K';
    if (w >= 2200 || h >= 1400) return '1440p';
    if (w >= 1600 || h >= 1000) return '1080p';
    if (w >= 1100 || h >= 700) return '720p';
    return 'SD';
  }

  /// "DV", "HDR10", "HLG", or null for SDR/unknown.
  /// Dolby Vision wins even when its base layer is HDR10/HLG-compatible.
  static String? rangeLabel(MediaDisplayCriteria c) => (c.doviProfile ?? 0) > 0
      ? 'DV'
      : switch (c.colorType) {
          MediaDisplayColorType.dolbyVision => 'DV',
          MediaDisplayColorType.pq => 'HDR10',
          MediaDisplayColorType.hlg => 'HLG',
          _ => null,
        };

  static List<String> labelsFor(MediaDisplayCriteria? c) {
    if (c == null) return const [];
    return [?resolutionLabel(c.width, c.height), ?rangeLabel(c)];
  }

  @override
  Widget build(BuildContext context) {
    if (isTranscoding) return const SizedBox.shrink();
    final labels = labelsFor(criteria);
    if (labels.isEmpty) return const SizedBox.shrink();
    final style = PlayerStyle.of(context);
    final color = style.badge ?? Colors.white;
    final badge = Container(
      height: 22,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        labels.join(' · '),
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, height: 1.0),
      ),
    );
    if (onTap == null) return badge;
    return Tooltip(
      message: tooltip ?? '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: badge),
      ),
    );
  }
}
