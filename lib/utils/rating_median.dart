import '../media/media_rating.dart';

/// Sources left out of the median. The Tomatometer is the share of positive
/// reviews, not an average score, so it runs far above every other source.
const _excludedFromMedian = {'rottenTomatoesCritic'};

/// The median of [ratings] on a 0-100 scale, rounded, or null when none
/// count. Every [MediaRatingSource] is already on 0-10 (IMDb as is,
/// percentages / 10, Letterboxd stars * 2), so the values compare directly.
/// One score per source.
({int score, int sources})? ratingMedian(Iterable<MediaRatingSource> ratings) {
  final bySource = <String, double>{};
  for (final rating in ratings) {
    if (_excludedFromMedian.contains(rating.source)) continue;
    if (!rating.value.isFinite || rating.value <= 0) continue;
    bySource.putIfAbsent(rating.source, () => rating.value);
  }
  if (bySource.isEmpty) return null;
  final values = bySource.values.toList()..sort();
  final mid = values.length ~/ 2;
  final median = values.length.isOdd ? values[mid] : (values[mid - 1] + values[mid]) / 2;
  return (score: (median * 10).round().clamp(0, 100), sources: values.length);
}
