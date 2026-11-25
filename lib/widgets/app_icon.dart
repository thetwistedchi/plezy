import 'package:flutter/material.dart';

import 'retro_glyphs.dart';

/// Wrapper around [Icon] that centralizes our Material Symbols defaults.
/// Defaults: fill=1 (filled) and weight=700 (bold). Update [AppIconDefaults]
/// to tweak app-wide icon appearance from one place.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
    this.retro = false,
    this.retroOpacity,
    this.retroSoft = false,
    this.retroGlow = true,
  });

  /// Same as [AppIcon] with [retro] on.
  const AppIcon.retro(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
    this.retroOpacity,
    this.retroSoft = false,
    this.retroGlow = true,
  }) : retro = true;

  final IconData? icon;
  final double? size;
  final Color? color;
  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;
  final List<Shadow>? shadows;
  final String? semanticLabel;
  final TextDirection? textDirection;

  /// Fork: on the retrowave theme, draw the matching [RetroGlyphs] glyph
  /// instead (navigation, top bar actions, hub headers).
  final bool retro;

  /// Opacity of the retro glyph; defaults to [color]'s alpha, so faded
  /// icons stay faded.
  final double? retroOpacity;

  /// Fork: the calmer player variant of the glyph (pastel, no glow).
  final bool retroSoft;

  /// Fork: whether the glyph may glow (never on TV).
  final bool retroGlow;

  @override
  Widget build(BuildContext context) {
    if (icon == null) return const SizedBox.shrink();
    final scope = retro ? null : RetroIconScope.maybeOf(context);
    if (retro || (scope != null && _neutral(color ?? IconTheme.of(context).color))) {
      final paths = RetroGlyph.pathsIfActive(context, icon);
      if (paths != null) {
        return RetroGlyph(
          paths,
          size: size ?? IconTheme.of(context).size,
          opacity: retroOpacity ?? ((color ?? IconTheme.of(context).color)?.a ?? 1),
          semanticLabel: semanticLabel,
          soft: scope?.soft ?? retroSoft,
          glow: scope == null ? retroGlow : false,
        );
      }
    }
    return Icon(
      icon,
      size: size,
      color: color,
      fill: fill ?? AppIconDefaults.fill,
      weight: weight ?? AppIconDefaults.weight,
      grade: grade ?? AppIconDefaults.grade,
      opticalSize: opticalSize ?? AppIconDefaults.opticalSize,
      shadows: shadows ?? AppIconDefaults.shadows,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
    );
  }
}

/// Central place to adjust default Material Symbol variations.
class AppIconDefaults {
  static double fill = 1;
  static double weight = 700;
  static double? grade;
  static double? opticalSize;
  static Color? color;
  static List<Shadow>? shadows;

  static void update({
    double? fill,
    double? weight,
    double? grade,
    double? opticalSize,
    Color? color,
    List<Shadow>? shadows,
  }) {
    if (fill != null) AppIconDefaults.fill = fill;
    if (weight != null) AppIconDefaults.weight = weight;
    if (grade != null) AppIconDefaults.grade = grade;
    if (opticalSize != null) AppIconDefaults.opticalSize = opticalSize;
    if (color != null) AppIconDefaults.color = color;
    if (shadows != null) AppIconDefaults.shadows = shadows;
  }
}


/// Fork: light, unsaturated-looking icon colours (white, lavender) take the
/// neon glyph inside a [RetroIconScope]; coloured status icons keep theirs.
bool _neutral(Color? c) {
  if (c == null) return true;
  final max = [c.r, c.g, c.b].reduce((a, b) => a > b ? a : b);
  final min = [c.r, c.g, c.b].reduce((a, b) => a < b ? a : b);
  return (max + min) / 2 > 0.72;
}

/// Fork: every [AppIcon] below draws its retrowave glyph (when one exists
/// and the icon is not a coloured status icon), without glow.
class RetroIconScope extends InheritedWidget {
  const RetroIconScope({super.key, this.soft = true, required super.child});

  /// The calm pastel variant.
  final bool soft;

  static RetroIconScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RetroIconScope>();

  @override
  bool updateShouldNotify(RetroIconScope oldWidget) => oldWidget.soft != soft;
}
