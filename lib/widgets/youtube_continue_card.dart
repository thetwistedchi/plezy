import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../screens/youtube/youtube_player_screen.dart';
import '../screens/youtube/youtube_resume.dart';
import '../services/youtube/youtube_extras.dart';
import '../services/youtube/youtube_settings.dart';
import '../services/youtube/youtube_webview.dart';
import '../theme/mono_tokens.dart';
import '../theme/player_style.dart';
import '../theme/retrowave_colors.dart';
import 'app_icon.dart';
import 'retro_pill.dart';

/// The YouTube video to resume, as the first card of Home's Continue
/// watching row: poster-sized (the video thumbnail cropped from its centre),
/// a YouTube mark, the progress bar, title and channel. Hidden while there is
/// nothing to resume.
class YouTubeContinueCard extends StatelessWidget {
  const YouTubeContinueCard({super.key, required this.width, required this.posterHeight});

  final double width;
  final double posterHeight;

  /// The hub's leading-card builder, where the in-app YouTube player exists.
  static Widget Function(BuildContext, double, double)? builderIfAvailable() {
    if (!YouTubeWebView.isSupported) return null;
    unawaited(YouTubeSettings.instance.load());
    return (context, width, posterHeight) => YouTubeContinueCard(width: width, posterHeight: posterHeight);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([youTubeResumeChanges, DeArrow.instance]),
      builder: (context, _) {
        final resume = youTubeResumeCandidate();
        if (resume == null) return const SizedBox.shrink();
        final video = resume.video;
        final fraction = (resume.progress.position / resume.progress.duration).clamp(0.0, 1.0);
        final theme = Theme.of(context);
        final mono = tokens(context);
        final retro = RetroColors.isActive(context);
        final gradient = PlayerStyle.of(context).progressGradient ?? [theme.colorScheme.primary, theme.colorScheme.primary];
        final title = YouTubeSettings.instance.deArrowTitles ? DeArrow.instance.titleFor(video) : video.title;
        void open() => unawaited(YouTubePlayerScreen.open(context, [video]));

        return SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(3, 3, 3, 1),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: open,
                onSecondaryTap: () => unawaited(YouTubeSettings.instance.dismissResume(video.id)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(mono.radiusMd),
                      child: SizedBox(
                        width: double.infinity,
                        height: posterHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(color: retro ? RetroColors.dusk : mono.surface),
                            if (video.thumbnailUrl != null)
                              CachedNetworkImage(imageUrl: video.thumbnailUrl!, fit: BoxFit.cover),
                            Positioned(
                              top: 6,
                              left: 6,
                              child: retro
                                  ? const RetroPill(
                                      label: 'YouTube',
                                      tone: RetroPillTone.magenta,
                                      icon: Symbols.smart_display_rounded,
                                    )
                                  : DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: mono.text,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            AppIcon(Symbols.smart_display_rounded, fill: 1, size: 11, color: mono.bg),
                                            const SizedBox(width: 3),
                                            Text(
                                              'YouTube',
                                              style: TextStyle(color: mono.bg, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: FractionallySizedBox(
                                widthFactor: fraction,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(gradient: LinearGradient(colors: gradient)),
                                  child: const SizedBox(height: 4, width: double.infinity),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.1,
                        color: retro ? retroHeadingColor : null,
                      ),
                    ),
                    Text(
                      video.channelTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
