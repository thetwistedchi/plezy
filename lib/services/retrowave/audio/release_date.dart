import '../../../media/media_item.dart';

/// Fork: release date of a podcast episode.
///
/// Podcast downloaders such as Podshelf start file names with the release
/// date ("2026-11-26 - Title.mp3") and keep the year tag empty, because Plex
/// splits an album into several when its tracks have different years. So the
/// date in the file name comes first, then the server's release date, then
/// the date the episode was added.
class ReleaseDate {
  ReleaseDate._();

  static final _leadingDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?=[\s._-]|$)');

  /// The date at the start of the item's file name, if there is one.
  static DateTime? fromFileName(MediaItem item) {
    for (final path in item.allPartFiles) {
      final name = path.split(RegExp(r'[\\/]')).last;
      final m = _leadingDate.firstMatch(name);
      if (m == null) continue;
      final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
      if (y < 1900 || mo < 1 || mo > 12 || d < 1 || d > 31) continue;
      return DateTime(y, mo, d);
    }
    return null;
  }

  /// Best known release date, or null when nothing is known.
  static DateTime? of(MediaItem item) {
    final fromName = fromFileName(item);
    if (fromName != null) return fromName;
    final server = DateTime.tryParse(item.originallyAvailableAt ?? '');
    if (server != null) return server;
    return null;
  }

  /// Release date, falling back to the date the item was added.
  static DateTime? orAdded(MediaItem item) {
    final date = of(item);
    if (date != null) return date;
    final added = item.addedAt;
    return added == null ? null : DateTime.fromMillisecondsSinceEpoch(added * 1000);
  }

  /// Milliseconds for sorting; 0 when nothing is known.
  static int sortStamp(MediaItem item) => orAdded(item)?.millisecondsSinceEpoch ?? 0;
}
