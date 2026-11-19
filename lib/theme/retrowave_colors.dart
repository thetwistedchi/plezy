import 'package:flutter/material.dart';

import 'page_backdrop.dart';

/// The Retrowave palette, sampled from the reference artwork (violet night
/// sky, magenta clouds, cyan glow). Every colour of the retrowave theme, the
/// player and the YouTube screens comes from here.
abstract final class RetroColors {
  /// Whether the retrowave theme is active in [context].
  static bool isActive(BuildContext context) => Theme.of(context).extension<PageBackdropStyle>() != null;

  /// "Online / connected" status colour: the cyan glow on retrowave, plain
  /// green elsewhere.
  static Color online(BuildContext context) => isActive(context) ? cyan : Colors.green;

  /// Status dot in [online] colour; glows softly on retrowave.
  static BoxDecoration onlineDot(BuildContext context) => BoxDecoration(
    color: online(context),
    shape: BoxShape.circle,
    boxShadow: isActive(context) ? [BoxShadow(color: cyan.withValues(alpha: 0.6), blurRadius: 6)] : null,
  );

  /// Darkest cliff shadow: page background.
  static const night = Color(0xFF140327);

  /// Rock face: side panels and sheets.
  static const rock = Color(0xFF1D0333);

  /// Indigo dusk: cards, fields and thumbnail placeholders.
  static const dusk = Color(0xFF241858);

  /// Sky band violet: play button, highlights, badges.
  static const violet = Color(0xFF6956FE);

  /// Cloud magenta: accent, skip buttons, end of the timeline fade.
  static const magenta = Color(0xFFC10093);

  /// Ground glow cyan: start of the timeline fade.
  static const cyan = Color(0xFF22D2EB);

  /// Pale horizon cyan: highlight markers.
  static const ice = Color(0xFFBAFCFC);

  /// Moonlight: text.
  static const moon = Color(0xFFF2EEFF);

  /// Dividers (12 % moonlight) and outlines (16 %).
  static const divider = Color(0x1FF2EEFF);
  static const outline = Color(0x29F2EEFF);

  /// Translucent night behind floating buttons and notices.
  static const night75 = Color(0xC0140327);
  static const night80 = Color(0xCC140327);
  static const night90 = Color(0xE6140327);

  // Muted badge tones: the accents mixed half-and-half with [night], for
  // small pills on posters that should fit in rather than stand out.
  static const violetMuted = Color(0xE63E2C92);
  static const magentaMuted = Color(0xE66A015D);
  static const cyanMuted = Color(0xE61B6A89);
  static const blueMuted = Color(0xE6212F86);
}

/// The page background: a muted fade through the artwork's night, dusk and
/// magenta. It starts at [RetroColors.night] across the whole top edge, so app
/// bars and the window caption sit on the same colour.
const retroBackdropGradient = LinearGradient(
  begin: Alignment(-0.35, -1),
  end: Alignment(0.35, 1),
  stops: [0, 0.22, 0.62, 1],
  colors: [RetroColors.night, RetroColors.night, Color(0xFF1A0E3C), Color(0xFF280938)],
);

/// Dark chrome of the YouTube player and its side panels, which sit over
/// video in every theme: retrowave purples in that theme, neutral greys in
/// the others.
@immutable
class PlayerChrome {
  const PlayerChrome({
    required this.panel,
    required this.surface,
    required this.outline,
    required this.divider,
    required this.text,
    required this.highlight,
    required this.scrim75,
    required this.scrim90,
  });

  final Color panel;
  final Color surface;
  final Color outline;
  final Color divider;
  final Color text;
  final Color highlight;
  final Color scrim75;
  final Color scrim90;

  static const retro = PlayerChrome(
    panel: RetroColors.rock,
    surface: RetroColors.dusk,
    outline: RetroColors.outline,
    divider: RetroColors.divider,
    text: RetroColors.moon,
    highlight: RetroColors.ice,
    scrim75: RetroColors.night75,
    scrim90: RetroColors.night90,
  );

  static const neutral = PlayerChrome(
    panel: Color(0xFF161618),
    surface: Color(0xFF26262B),
    outline: Color(0x29FFFFFF),
    divider: Color(0x1FFFFFFF),
    text: Color(0xFFF2F2F5),
    highlight: Colors.white,
    scrim75: Color(0xC00E0E10),
    scrim90: Color(0xE60E0E10),
  );

  static PlayerChrome of(BuildContext context) => RetroColors.isActive(context) ? retro : neutral;
}
