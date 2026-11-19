import 'package:flutter/material.dart';

import '../theme/retrowave_colors.dart';
import 'retro_pill.dart';
import '../theme/mono_tokens.dart';

/// Unwatched-episode count chip shown in the top-right corner of poster
/// cards. [size] is its height. Keeps a [size]-diameter circular footprint for 1–2 digit counts
/// and widens into a stadium pill beyond that; counts above 999 render as
/// "999+" so the label stays on one line (#1310).
class UnwatchedCountBadge extends StatelessWidget {
  final int count;
  final double size;
  final double fontSize;

  const UnwatchedCountBadge({super.key, required this.count, this.size = 18, this.fontSize = 10.5});

  @override
  Widget build(BuildContext context) {
    if (RetroColors.isActive(context)) {
      return RetroPill(
        label: count > 999 ? '999+' : '$count',
        tone: RetroPillTone.magenta,
        height: size,
        fontSize: fontSize,
      );
    }
    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size),
      padding: EdgeInsets.symmetric(horizontal: size * 0.2),
      decoration: BoxDecoration(
        color: tokens(context).text,
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
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
            color: tokens(context).bg,
            fontSize: fontSize,
            fontWeight: .bold,
            // Tight line box, so the digits sit in the middle of the pill.
            height: 1,
            leadingDistribution: TextLeadingDistribution.even,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
