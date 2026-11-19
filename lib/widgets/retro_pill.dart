import 'package:flutter/material.dart';

import '../theme/retrowave_colors.dart';
import 'app_icon.dart';

/// The rim colour family of a [RetroPill].
enum RetroPillTone {
  /// Ratings and languages.
  violet(Color(0x996956FE), Color(0xFFC7BDFF)),

  /// Counts (unwatched episodes, watched).
  magenta(Color(0x99C10093), Color(0xFFF2A7DD)),

  /// Quality (4K, HDR).
  cyan(Color(0x8C22D2EB), Color(0xFFA9EEF7));

  const RetroPillTone(this.rim, this.text);

  final Color rim;

  /// A light tint of [rim], instead of white.
  final Color text;
}

/// A small dark-purple pill with a muted neon rim and tinted text: the
/// retrowave theme's poster badges.
class RetroPill extends StatelessWidget {
  const RetroPill({super.key, required this.label, required this.tone, this.icon, this.height = 18, this.fontSize = 10.5});

  final String label;
  final RetroPillTone tone;
  final IconData? icon;
  final double height;
  final double fontSize;

  static const background = Color(0xE01D0333);

  /// Other themes: the same pill in the theme's own colours (primary,
  /// secondary and tertiary stand in for violet, cyan and magenta).
  static ({Color background, Color rim, Color text}) _colors(BuildContext context, RetroPillTone tone) {
    if (RetroColors.isActive(context)) return (background: background, rim: tone.rim, text: tone.text);
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (tone) {
      RetroPillTone.violet => scheme.primary,
      RetroPillTone.cyan => scheme.secondary,
      RetroPillTone.magenta => scheme.tertiary,
    };
    return (
      background: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
      rim: accent.withValues(alpha: 0.6),
      text: Color.lerp(accent, scheme.onSurface, 0.35)!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context, tone);
    return Container(
      height: height,
      constraints: BoxConstraints(minWidth: height),
      padding: EdgeInsets.symmetric(horizontal: height * 0.38),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: colors.rim, width: 1),
      ),
      // Centred, but only as wide as the label: Container's own alignment
      // would stretch the pill across any loose width (the language pill in
      // its row), and without centring a one-digit label sat top-left.
      child: Center(
        widthFactor: 1,
        child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, fill: 1, size: fontSize, color: colors.text),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.text,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              height: 1,
              leadingDistribution: TextLeadingDistribution.even,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Soft lavender: row headings and card titles in the retrowave theme, a
/// plain colour between the glyphs' cyan and magenta (was periwinkle
/// 0xFF9DB4FF). No other text uses it.
const retroHeadingColor = Color(0xFFC4B8FF);

/// Whether the retrowave look applies (its page backdrop is installed).
bool isRetrowave(BuildContext context) => RetroColors.isActive(context);
