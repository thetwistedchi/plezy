import 'package:flutter/material.dart';

import '../theme/page_backdrop.dart';
import '../theme/retrowave_colors.dart';
import '../theme/mono_tokens.dart';

/// Unwatched-episode count chip shown in the top-right corner of poster
/// cards. Keeps a [size]-diameter circular footprint for 1–2 digit counts
/// and widens into a stadium pill beyond that; counts above 999 render as
/// "999+" so the label stays on one line (#1310).
class UnwatchedCountBadge extends StatelessWidget {
  final int count;
  final double size;
  final double fontSize;

  const UnwatchedCountBadge({super.key, required this.count, this.size = 24, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    final retro = Theme.of(context).extension<PageBackdropStyle>() != null;
    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size),
      padding: EdgeInsets.symmetric(horizontal: size * 0.2),
      decoration: BoxDecoration(
        // Retrowave: a muted magenta-to-blue fade.
        color: retro ? null : tokens(context).text,
        gradient: retro ? const LinearGradient(colors: [RetroColors.magentaMuted, RetroColors.blueMuted]) : null,
        border: retro ? Border.all(color: RetroColors.magenta.withValues(alpha: 0.35), width: 0.8) : null,
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: retro ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
      ),
      // Center with widthFactor shrink-wraps the pill to the label (Container
      // alignment would expand into the Stack's loose width instead).
      child: Center(
        widthFactor: 1,
        child: Text(
          count > 999 ? '999+' : '$count',
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: retro ? RetroColors.moon.withValues(alpha: 0.92) : tokens(context).bg,
            fontSize: fontSize,
            fontWeight: .bold,
            // Tight line box, so the digits sit in the middle of the pill.
            height: 1,
            leadingDistribution: TextLeadingDistribution.even,
          ),
          textAlign: TextAlign.center,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        ),
      ),
    );
  }
}
