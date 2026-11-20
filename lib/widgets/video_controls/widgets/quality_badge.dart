import 'package:flutter/material.dart';

import '../../../media/media_display_criteria.dart';
import '../../../mpv/mpv.dart';
import '../../../theme/player_style.dart';
import '../../../utils/codec_utils.dart';

/// Small outlined "4K · DV" style badge for the player's bottom bar, built
/// from the playing version's display criteria. Shows nothing when the
/// server reported neither a size nor a dynamic range.
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.criteria, this.isTranscoding = false, this.onTap, this.tooltip});

  final MediaDisplayCriteria? criteria;

  /// A transcode is re-encoded to SDR at the chosen quality, so the source's
  /// labels would be wrong; the badge hides.
  final bool isTranscoding;

  /// Fork: makes the badge a button (opens the file info).
  final VoidCallback? onTap;
  final String? tooltip;

  /// "4K", "1440p", "1080p", "720p", "SD" from the frame size.
  static String? resolutionLabel(int? width, int? height) {
    if ((width ?? 0) <= 0 || (height ?? 0) <= 0) return null;
    final w = width!, h = height!;
    if (w >= 3200 || h >= 2000) return '4K';
    if (w >= 2200 || h >= 1400) return '1440p';
    if (w >= 1600 || h >= 1000) return '1080p';
    if (w >= 1100 || h >= 700) return '720p';
    return 'SD';
  }

  /// "DV", "HDR10", "HLG", or null for SDR/unknown.
  /// Dolby Vision wins even when its base layer is HDR10/HLG-compatible.
  static String? rangeLabel(MediaDisplayCriteria c) => (c.doviProfile ?? 0) > 0
      ? 'DV'
      : switch (c.colorType) {
          MediaDisplayColorType.dolbyVision => 'DV',
          MediaDisplayColorType.pq => 'HDR10',
          MediaDisplayColorType.hlg => 'HLG',
          _ => null,
        };

  static List<String> labelsFor(MediaDisplayCriteria? c) {
    if (c == null) return const [];
    return [?resolutionLabel(c.width, c.height), ?rangeLabel(c)];
  }

  @override
  Widget build(BuildContext context) {
    if (isTranscoding) return const SizedBox.shrink();
    final labels = labelsFor(criteria);
    if (labels.isEmpty) return const SizedBox.shrink();
    return PlayerInfoBadge(text: labels.join(' · '), onTap: onTap, tooltip: tooltip);
  }
}

/// Fork: the playing audio track's format next to the quality badge, e.g.
/// `TrueHD Atmos 7.1`, `DTS-HD MA 5.1`, `AAC Stereo`. Follows track switches
/// and shows nothing when no audio track is playing.
class AudioFormatBadge extends StatelessWidget {
  const AudioFormatBadge({super.key, required this.player, this.onTap, this.tooltip});

  final Player player;
  final VoidCallback? onTap;
  final String? tooltip;

  static String? labelFor(AudioTrack? track) {
    final codec = track?.codec;
    if (track == null || codec == null || codec.isEmpty) return null;
    final name = CodecUtils.formatAudioCodec(codec, profile: track.codecProfile);
    // Atmos rides inside TrueHD / E-AC3 and only shows in the track's title.
    final atmos = (track.title ?? '').toLowerCase().contains('atmos') && !name.contains('Atmos');
    return [name, if (atmos) 'Atmos', ?CodecUtils.formatAudioChannels(track.channels)].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: player.streams.tracks,
      initialData: player.state.tracks,
      builder: (context, tracksSnapshot) => StreamBuilder<TrackSelection>(
        stream: player.streams.track,
        initialData: player.state.track,
        builder: (context, selectionSnapshot) {
          final selected = selectionSnapshot.data?.audio;
          if (selected == null || selected.id == AudioTrack.off.id) return const SizedBox.shrink();
          // The selection can be a bare id ('auto'); the track list has the details.
          AudioTrack? track = selected;
          for (final a in tracksSnapshot.data?.audio ?? const <AudioTrack>[]) {
            if (a.id == selected.id) {
              track = a;
              break;
            }
          }
          final label = labelFor(track);
          if (label == null) return const SizedBox.shrink();
          return PlayerInfoBadge(text: label, onTap: onTap, tooltip: tooltip);
        },
      ),
    );
  }
}

/// Outlined info badge of the player's bottom bar (quality, audio format).
/// The text is centred on both axes: fixed line height with the leading split
/// evenly, so caps and digits sit in the middle of the outline.
class PlayerInfoBadge extends StatelessWidget {
  const PlayerInfoBadge({super.key, required this.text, this.onTap, this.tooltip});

  final String text;
  final VoidCallback? onTap;
  final String? tooltip;

  static const double height = 22;
  static const double fontSize = 11.5;

  @override
  Widget build(BuildContext context) {
    final style = PlayerStyle.of(context);
    final color = style.badge ?? Colors.white;
    const textStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.0,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final badge = Container(
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: color, width: 0.8),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        strutStyle: const StrutStyle(
          fontSize: fontSize,
          height: 1.0,
          forceStrutHeight: true,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        style: textStyle.copyWith(color: color),
      ),
    );
    if (onTap == null) return badge;
    return Tooltip(
      message: tooltip ?? '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: badge),
      ),
    );
  }
}
