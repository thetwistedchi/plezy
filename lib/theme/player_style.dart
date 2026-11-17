import 'package:flutter/material.dart';

/// How the video player's chrome is coloured. Stock Plezy draws its player in
/// plain white over the video; a theme may attach a [PlayerStyle] to tint it.
///
/// Every field is optional: null keeps the stock look for that part, so the
/// player reads [PlayerStyle.of] and falls back field by field.
@immutable
class PlayerStyle extends ThemeExtension<PlayerStyle> {
  const PlayerStyle({
    this.playButtonFill,
    this.playButtonIcon,
    this.progress,
    this.progressGlow,
    this.skipButtonBorder,
  });

  /// Filled disc behind the play/pause icon.
  final Color? playButtonFill;

  /// Icon colour on [playButtonFill].
  final Color? playButtonIcon;

  /// Played part of the timeline.
  final Color? progress;

  /// Glow around the timeline's played part and the play button.
  final Color? progressGlow;

  /// Neon outline of the "Skip intro / credits" button; null keeps the stock
  /// white pill.
  final Color? skipButtonBorder;

  static const PlayerStyle stock = PlayerStyle();

  /// Purple play button, magenta timeline and neon skip button.
  static const PlayerStyle retrowave = PlayerStyle(
    playButtonFill: Color(0xFF9D7BFF),
    playButtonIcon: Color(0xFF14041F),
    progress: Color(0xFFE0479A),
    progressGlow: Color(0xFFE0479A),
    skipButtonBorder: Color(0xFFE0479A),
  );

  static PlayerStyle of(BuildContext context) => Theme.of(context).extension<PlayerStyle>() ?? stock;

  @override
  PlayerStyle copyWith({
    Color? playButtonFill,
    Color? playButtonIcon,
    Color? progress,
    Color? progressGlow,
    Color? skipButtonBorder,
  }) => PlayerStyle(
    playButtonFill: playButtonFill ?? this.playButtonFill,
    playButtonIcon: playButtonIcon ?? this.playButtonIcon,
    progress: progress ?? this.progress,
    progressGlow: progressGlow ?? this.progressGlow,
    skipButtonBorder: skipButtonBorder ?? this.skipButtonBorder,
  );

  @override
  PlayerStyle lerp(covariant ThemeExtension<PlayerStyle>? other, double t) {
    if (other is! PlayerStyle) return this;
    return PlayerStyle(
      playButtonFill: Color.lerp(playButtonFill, other.playButtonFill, t),
      playButtonIcon: Color.lerp(playButtonIcon, other.playButtonIcon, t),
      progress: Color.lerp(progress, other.progress, t),
      progressGlow: Color.lerp(progressGlow, other.progressGlow, t),
      skipButtonBorder: Color.lerp(skipButtonBorder, other.skipButtonBorder, t),
    );
  }
}
