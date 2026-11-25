import 'package:flutter/material.dart';

import '../theme/retrowave_colors.dart';
import '../utils/platform_detector.dart';
import 'app_icon.dart';

/// The rim colour family of a [RetroPill].
enum RetroPillTone {
  /// Ratings and languages.
  violet(Color(0x996956FE), Color(0xFFC7BDFF), neonTube: Color(0xFF8C78FF), neonCore: Color(0xFFE8E2FF), neonHalo: Color(0xFF6956FE)),

  /// Counts (unwatched episodes, watched).
  magenta(Color(0x99C10093), Color(0xFFF2A7DD), neonTube: Color(0xFFFF28C8), neonCore: Color(0xFFFFD6F4), neonHalo: Color(0xFFD600A0)),

  /// Quality (4K, HDR).
  cyan(Color(0x8C22D2EB), Color(0xFFA9EEF7), neonTube: Color(0xFF22D2EB), neonCore: Color(0xFFD8FBFF), neonHalo: Color(0xFF0FA8C8));

  const RetroPillTone(this.rim, this.text, {required this.neonTube, required this.neonCore, required this.neonHalo});

  /// Fork: neon look in the retrowave theme: tube, its pale core and glow.
  final Color neonTube;
  final Color neonCore;
  final Color neonHalo;

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
    if (RetroColors.isActive(context)) return _neon(context);
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

extension on RetroPill {
  /// Retrowave: a neon sign. Dark body, a coloured tube with a pale core as
  /// the rim, text in the core colour, and an even glow except on TV.
  Widget _neon(BuildContext context) {
    final glow = !PlatformDetector.isTV();
    final textStyle = TextStyle(
      color: tone.neonCore,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1,
      leadingDistribution: TextLeadingDistribution.even,
      fontFeatures: const [FontFeature.tabularFigures()],
      shadows: glow ? [Shadow(color: tone.neonHalo, blurRadius: 4)] : null,
    );
    return RepaintBoundary(
      child: CustomPaint(
        painter: NeonPillPainter(tone: tone, glow: glow),
        child: Container(
          height: height,
          constraints: BoxConstraints(minWidth: height),
          padding: EdgeInsets.symmetric(horizontal: height * 0.38),
          child: Center(
            widthFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  AppIcon(icon!, fill: 1, size: fontSize, color: tone.neonCore),
                  const SizedBox(width: 3),
                ],
                Text(label, maxLines: 1, softWrap: false, textAlign: TextAlign.center, style: textStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fork: the stadium of a neon [RetroPill]: glow, dark body, tube, core.
class NeonPillPainter extends CustomPainter {
  const NeonPillPainter({required this.tone, this.glow = true});

  final RetroPillTone tone;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final tubeWidth = (size.height * 0.09).clamp(1.3, 2.4);
    final rect = (Offset.zero & size).deflate(tubeWidth / 2);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    Paint stroke(Color color, double width, {MaskFilter? blur}) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..maskFilter = blur;
    if (glow) {
      canvas.drawRRect(
        shape,
        stroke(tone.neonHalo.withValues(alpha: 0.7), tubeWidth * 1.6, blur: MaskFilter.blur(BlurStyle.normal, size.height * 0.18)),
      );
    }
    canvas.drawRRect(shape.deflate(tubeWidth / 2), Paint()..color = RetroPill.background);
    canvas.drawRRect(shape, stroke(tone.neonTube, tubeWidth));
    canvas.drawRRect(shape, stroke(tone.neonCore, tubeWidth * 0.42));
  }

  @override
  bool shouldRepaint(NeonPillPainter oldDelegate) => oldDelegate.tone != tone || oldDelegate.glow != glow;
}

/// Soft lavender: row headings and card titles in the retrowave theme, a
/// plain colour between the glyphs' cyan and magenta (was periwinkle
/// 0xFF9DB4FF). No other text uses it.
const retroHeadingColor = Color(0xFFC4B8FF);

/// Whether the retrowave look applies (its page backdrop is installed).
bool isRetrowave(BuildContext context) => RetroColors.isActive(context);
