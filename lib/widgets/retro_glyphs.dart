import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/retrowave_colors.dart';

/// Fork: hand-drawn outrun glyphs (sunset house, VHS tape, CRT with antennas,
/// horizon lines) for the navigation, the top bar actions and the hub
/// headers, stroked with the cyan to magenta fade. Only on the retrowave
/// theme; [AppIcon] swaps them in when called with `retro: true`.
abstract final class RetroGlyphs {
  static const _home = '<path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10v10h13V10"/><path d="M8.5 16.5a3.5 3.5 0 0 1 7 0"/><path d="M7.5 18.5h9"/>';
  static const _libraries = '<rect x="2.5" y="6" width="19" height="12" rx="1.5"/><circle cx="7.5" cy="12" r="2"/><circle cx="16.5" cy="12" r="2"/><path d="M9.5 12h5"/><path d="M6 18l1.5-2.5h9L18 18"/>';
  static const _search = '<circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5 21 21"/><path d="M5.5 11.5h10M6.8 14h7.4"/><path d="M10.5 11.5v4.5"/>';
  static const _downloads = '<path d="M12 2.5v10"/><path d="M7.5 8l4.5 4.5L16.5 8"/><path d="M3 16h18"/><path d="M6 19h12"/><path d="M9 21.5h6"/>';
  static const _settings = '<circle cx="12" cy="12" r="5.5"/><circle cx="12" cy="12" r="2.2"/><path d="M17.50 12.00L20.60 12.00"/><path d="M15.89 15.89L18.08 18.08"/><path d="M12.00 17.50L12.00 20.60"/><path d="M8.11 15.89L5.92 18.08"/><path d="M6.50 12.00L3.40 12.00"/><path d="M8.11 8.11L5.92 5.92"/><path d="M12.00 6.50L12.00 3.40"/><path d="M15.89 8.11L18.08 5.92"/><path d="M2 22h20"/>';
  static const _party = '<rect x="3" y="7" width="18" height="12" rx="2"/><path d="M8 3l4 4 4-4"/><circle cx="9.5" cy="11.5" r="1.4"/><circle cx="14.5" cy="11.5" r="1.4"/><path d="M7 16.5c.6-1.4 1.5-2 2.5-2s1.9.6 2.5 2c.6-1.4 1.5-2 2.5-2s1.9.6 2.5 2"/>';
  static const _refresh = '<path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 4v5h-5"/><path d="M8.5 14.5a3.5 3.5 0 0 1 7 0"/><path d="M8 16.5h8"/>';
  static const _continueWatching = '<path d="M3 13a9 9 0 0 1 18 0"/><path d="M3.5 15.5h17M5 18h14M7.5 20.5h9"/><path d="M10.2 6.5v5l4-2.5z"/>';
  static const _recentlyAdded = '<path d="M11 3l1.8 5.7 5.7 1.8-5.7 1.8L11 18l-1.8-5.7-5.7-1.8 5.7-1.8z"/><path d="M18.5 15l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/>';

  static final Map<IconData, String> _byIcon = {
    Symbols.home_rounded: _home,
    Symbols.video_library_rounded: _libraries,
    Symbols.search_rounded: _search,
    Symbols.download_rounded: _downloads,
    Symbols.settings_rounded: _settings,
    Symbols.group_rounded: _party,
    Symbols.refresh_rounded: _refresh,
    Symbols.play_circle_rounded: _continueWatching,
    Symbols.schedule_rounded: _recentlyAdded,
    Symbols.new_releases_rounded: _recentlyAdded,
  };

  static String? pathsFor(IconData icon) => _byIcon[icon];

  static final Map<String, String> _svgCache = {};

  static String svg(String paths) => _svgCache.putIfAbsent(
    paths,
    () =>
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="url(#g)" '
        'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">'
        '<defs><linearGradient id="g" x1="0" y1="0" x2="24" y2="24" gradientUnits="userSpaceOnUse">'
        '<stop offset="0" stop-color="#22D2EB"/><stop offset="1" stop-color="#C10093"/></linearGradient></defs>'
        '$paths</svg>',
  );
}

/// One [RetroGlyphs] glyph at [size] (the ambient icon size when null).
/// [opacity] dims it, e.g. for unselected navigation entries.
class RetroGlyph extends StatelessWidget {
  const RetroGlyph(this.paths, {super.key, this.size, this.opacity = 1, this.semanticLabel});

  final String paths;
  final double? size;
  final double opacity;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final s = size ?? IconTheme.of(context).size ?? 24;
    Widget glyph = SvgPicture.string(RetroGlyphs.svg(paths), width: s, height: s, semanticsLabel: semanticLabel);
    if (opacity < 1) glyph = Opacity(opacity: opacity, child: glyph);
    return SizedBox(width: s, height: s, child: glyph);
  }

  /// The glyph for [icon] when the retrowave theme is active, else null.
  static String? pathsIfActive(BuildContext context, IconData? icon) {
    if (icon == null || !RetroColors.isActive(context)) return null;
    return RetroGlyphs.pathsFor(icon);
  }
}
