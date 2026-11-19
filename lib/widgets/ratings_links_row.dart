import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/strings.g.dart';
import '../services/ratings/title_links_service.dart';
import '../theme/mono_tokens.dart';
import '../utils/app_logger.dart';
import '../utils/rating_median.dart';
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
      children: [
        for (final link in links) _RatingLinkCard(link: link, launcher: launcher),
        if (ratingMedian([for (final link in links) ?link.rating]) case final median?)
          _MedianCard(score: median.score, sources: median.sources, links: links),
      ],
    );
  }
}

/// The median of the row's scores on 0-100, after the site cards. The
/// Tomatometer is left out (see [ratingMedian]).
class _MedianCard extends StatelessWidget {
  const _MedianCard({required this.score, required this.sources, required this.links});

  final int score;
  final int sources;
  final List<TitleLink> links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    const label = 'Median';
    final sourcesLabel = LocaleSettings.currentLocale == AppLocale.de
        ? '$sources ${sources == 1 ? 'Quelle' : 'Quellen'}'
        : '$sources ${sources == 1 ? 'source' : 'sources'}';
    final de = LocaleSettings.currentLocale == AppLocale.de;
    return Tooltip(
      message: de ? 'Alle Wertungen im Vergleich anzeigen' : 'Show every score side by side',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(mono.radiusMd),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => _MedianBreakdownDialog(score: score, links: links),
          ),
          child: Container(
        constraints: const BoxConstraints(minWidth: 132),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mono.surface,
          borderRadius: BorderRadius.circular(mono.radiusMd),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.7)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: mono.textMuted)),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$score', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: mono.text)),
                const SizedBox(width: 6),
                Text(sourcesLabel, style: theme.textTheme.labelSmall?.copyWith(color: mono.textMuted)),
              ],
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

/// Opens the comparison of every score in [links] (used by the Median card
/// and by the TV details page's scores action). No-op without a median.
Future<void> showRatingsBreakdown(BuildContext context, List<TitleLink> links) async {
  final median = ratingMedian([for (final link in links) ?link.rating]);
  if (median == null) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _MedianBreakdownDialog(score: median.score, links: links),
  );
}

/// Every score of the row on 0–100 next to its own scale, with the median
/// marked, so the spread behind the single number is visible.
class _MedianBreakdownDialog extends StatelessWidget {
  const _MedianBreakdownDialog({required this.score, required this.links});

  final int score;
  final List<TitleLink> links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final de = LocaleSettings.currentLocale == AppLocale.de;
    final rows = [
      for (final link in links)
        if (link.rating case final rating?)
          (
            name: link.siteName,
            native: ratingInfoForSource(link.source, rating.value)?.formattedValue ?? rating.value.toStringAsFixed(1),
            normalized: (rating.value * 10).round().clamp(0, 100).toInt(),
            votes: rating.votes,
            counted: ratingCountsTowardMedian(rating.source),
          ),
    ]..sort((a, b) => b.normalized.compareTo(a.normalized));
    final counted = [for (final r in rows) if (r.counted) r.normalized];
    final spread = counted.isEmpty ? null : (counted.reduce((a, b) => a < b ? a : b), counted.reduce((a, b) => a > b ? a : b));
    final accent = theme.colorScheme.primary;

    return AlertDialog(
      title: Text(de ? 'Wertungen im Vergleich' : 'All scores'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                de
                    ? 'Jede Wertung auf 0–100 umgerechnet. Die Linie markiert den Median ($score).'
                    : 'Each score converted to 0–100. The line marks the median ($score).',
                style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
              ),
              const SizedBox(height: 14),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Opacity(
                    opacity: r.counted ? 1 : 0.55,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 128,
                          child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(
                            r.native,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, c) => Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: mono.outline.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                Container(
                                  height: 8,
                                  width: c.maxWidth * r.normalized / 100,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: r.counted ? 0.85 : 0.4),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                Positioned(
                                  left: c.maxWidth * score / 100 - 1,
                                  top: -3,
                                  child: Container(width: 2, height: 14, color: mono.text),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${r.normalized}',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                [
                  de ? 'Median $score aus ${counted.length} ${counted.length == 1 ? 'Quelle' : 'Quellen'}' : 'Median $score from ${counted.length} ${counted.length == 1 ? 'source' : 'sources'}',
                  if (spread != null) de ? 'Spanne ${spread.$1}–${spread.$2}' : 'range ${spread.$1}–${spread.$2}',
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (rows.any((r) => !r.counted)) ...[
                const SizedBox(height: 4),
                Text(
                  de
                      ? 'Ausgegraut: nicht im Median, der Tomatometer ist der Anteil positiver Kritiken, keine Durchschnittsnote.'
                      : 'Greyed out: not in the median; the Tomatometer is the share of positive reviews, not an average score.',
                  style: theme.textTheme.bodySmall?.copyWith(color: mono.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.pop(context), child: Text(de ? 'Schließen' : 'Close')),
      ],
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
