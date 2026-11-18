import 'package:flutter/painting.dart';

/// The Retrowave palette, sampled from the reference artwork (violet night
/// sky, magenta clouds, cyan glow). Every colour of the retrowave theme, the
/// player and the YouTube screens comes from here.
abstract final class RetroColors {
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
}
