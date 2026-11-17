import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/strings.g.dart';
import '../services/ratings/title_links_service.dart';
import '../theme/mono_tokens.dart';
import '../utils/app_logger.dart';
import '../utils/rating_utils.dart';

/// The details page's "Ratings & links" row: one compact card per site. The
/// whole card is the link; the site's score shows when one is known.
class RatingsLinksRow extends StatelessWidget {
  const RatingsLinksRow({super.key, required this.links, this.launcher});

  final List<TitleLink> links;

  /// Overrides how a link opens; tests pass a recorder.
  final Future<bool> Function(Uri url)? launcher;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [for (final link in links) _RatingLinkCard(link: link, launcher: launcher)],
    );
  }
}

class _RatingLinkCard extends StatefulWidget {
  const _RatingLinkCard({required this.link, this.launcher});

  final TitleLink link;
  final Future<bool> Function(Uri url)? launcher;

  @override
  State<_RatingLinkCard> createState() => _RatingLinkCardState();
}

class _RatingLinkCardState extends State<_RatingLinkCard> {
  bool _highlighted = false;

  Future<void> _open() async {
    final url = widget.link.url;
    try {
      final opened = await (widget.launcher?.call(url) ?? launchUrl(url, mode: LaunchMode.externalApplication));
      if (!opened) appLogger.w('Ratings & links: could not open $url');
    } on Exception catch (e) {
      appLogger.w('Ratings & links: could not open $url', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final link = widget.link;
    final rating = link.rating;
    // The badge asset does not depend on the score except for Rotten
    // Tomatoes' fresh/rotten split; an unscored card shows the fresh mark.
    final info = ratingInfoForSource(link.source, rating?.value ?? 10);
    final label = ratingSourceLabel(link.source) ?? link.siteName;
    final value = rating == null ? '–' : (info?.formattedValue ?? rating.value.toStringAsFixed(1));
    final votes = rating?.votes;
    final accent = theme.colorScheme.primary;
    const iconHeight = 18.0;

    return Tooltip(
      message: t.discover.openOn(site: link.siteName),
      child: Semantics(
        link: true,
        label: '$label $value',
        excludeSemantics: true,
        child: Material(
          color: mono.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(mono.radiusMd),
            side: BorderSide(color: _highlighted ? accent : mono.outline, width: _highlighted ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _open,
            onHover: (hovering) => setState(() => _highlighted = hovering),
            onFocusChange: (focused) => setState(() => _highlighted = focused),
            child: AnimatedContainer(
              duration: mono.fast,
              constraints: const BoxConstraints(minWidth: 132),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                boxShadow: _highlighted
                    ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 16)]
                    : const [],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (info != null)
                        SizedBox(
                          width: iconHeight * info.iconAspect,
                          height: iconHeight,
                          child: SvgPicture.asset(info.assetPath, theme: SvgTheme(currentColor: mono.text)),
                        ),
                      if (info != null) const SizedBox(width: 8),
                      Text(label, style: theme.textTheme.labelMedium?.copyWith(color: mono.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        value,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: rating == null ? mono.textMuted : mono.text,
                        ),
                      ),
                      if (votes != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          compactCount(votes),
                          style: theme.textTheme.labelSmall?.copyWith(color: mono.textMuted),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 950 → "950", 48 200 → "48K", 1 250 000 → "1.3M".
String compactCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 10000) return '${(n / 1000).round()}K';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}
