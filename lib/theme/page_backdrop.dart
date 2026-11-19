import 'package:flutter/material.dart';

/// A gradient painted behind every page in place of the solid scaffold colour.
@immutable
class PageBackdropStyle extends ThemeExtension<PageBackdropStyle> {
  const PageBackdropStyle({required this.color, required this.gradient});

  /// Solid stand-in for [gradient], for overlays, fades and sticky bars that
  /// must cover what scrolls beneath them.
  final Color color;
  final Gradient gradient;

  @override
  PageBackdropStyle copyWith({Color? color, Gradient? gradient}) =>
      PageBackdropStyle(color: color ?? this.color, gradient: gradient ?? this.gradient);

  @override
  PageBackdropStyle lerp(PageBackdropStyle? other, double t) => t < 0.5 || other == null ? this : other;
}

extension PageColor on ThemeData {
  /// The opaque page colour. Use this rather than [scaffoldBackgroundColor],
  /// which is transparent inside a [PageBackdrop] so the gradient shows.
  Color get pageColor => extension<PageBackdropStyle>()?.color ?? scaffoldBackgroundColor;
}

/// The decoration for a full-screen page background.
BoxDecoration pageDecoration(ThemeData theme) {
  final style = theme.extension<PageBackdropStyle>();
  return style == null ? BoxDecoration(color: theme.scaffoldBackgroundColor) : BoxDecoration(gradient: style.gradient);
}

final _transparentThemes = Expando<ThemeData>('PageBackdrop');

/// Paints the theme's [PageBackdropStyle] gradient behind [child] and makes
/// the scaffolds inside it transparent. A no-op without the extension or when
/// an outer [PageBackdrop] already paints it.
class PageBackdrop extends StatelessWidget {
  const PageBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.extension<PageBackdropStyle>();
    if (style == null || theme.scaffoldBackgroundColor.a == 0) return child;
    final inner = _transparentThemes[theme] ??= theme.copyWith(scaffoldBackgroundColor: Colors.transparent);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: style.gradient),
      // Own layer for the page, so scrolling does not repaint the gradient.
      child: RepaintBoundary(child: Theme(data: inner, child: child)),
    );
  }
}

/// Wraps the platform's default page transition so each page brings its own
/// backdrop, which keeps pages opaque while they slide or fade over each other.
class BackdropPageTransitionsBuilder extends PageTransitionsBuilder {
  const BackdropPageTransitionsBuilder();

  static const _defaults = PageTransitionsTheme();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route is NoPageBackdropRoute) return _defaults.buildTransitions(route, context, animation, secondaryAnimation, child);
    return _defaults.buildTransitions(route, context, animation, secondaryAnimation, PageBackdrop(child: child));
  }
}

/// A page route that must stay see-through, such as a player whose video is a
/// native surface beneath the Flutter view. [BackdropPageTransitionsBuilder]
/// leaves it without a backdrop.
class NoPageBackdropRoute<T> extends MaterialPageRoute<T> {
  NoPageBackdropRoute({required super.builder, super.settings});
}
