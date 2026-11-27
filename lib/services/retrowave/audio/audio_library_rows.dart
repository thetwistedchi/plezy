import 'dart:math' as math;

import '../../../i18n/retro_strings.dart';
import '../../../media/library_query.dart';
import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_library.dart';
import '../../../media/media_server_client.dart';
import '../../../utils/app_logger.dart';
import 'audio_extras.dart';
import 'audio_settings.dart';

/// Fork: extra rows on the Recommended page of audiobook, audio drama and
/// podcast libraries, built from one listing of the library's tracks (kept
/// for the session) and the app's own listening state.
class AudioLibraryRows {
  AudioLibraryRows._();

  static final _tracksCache = <String, (DateTime, List<MediaItem>)>{};
  static const _cacheAge = Duration(minutes: 30);
  static const _short = Duration(hours: 3);

  static Future<List<MediaItem>> _tracks(MediaServerClient client, MediaLibrary library) async {
    final key = library.globalKey;
    final hit = _tracksCache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < _cacheAge) return hit.$2;
    final page = await client.fetchLibraryPagedContent(
      library.id,
      libraryKind: library.kind,
      query: const LibraryQuery(kind: MediaKind.track, limit: 5000),
    );
    final tracks = page.items.where((i) => i.kind == MediaKind.track).toList();
    _tracksCache[key] = (DateTime.now(), tracks);
    return tracks;
  }

  /// Leading number of a title ("Folge 12 - …", "012 …"), for series order.
  static int? _number(String title) {
    final m = RegExp(r'(\d{1,4})').firstMatch(title);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static MediaHub _hub(MediaLibrary library, String id, String title, String type, List<MediaItem> items) => MediaHub(
    id: 'retrowave_${id}_${library.id}',
    identifier: 'retrowave_$id',
    title: title,
    type: type,
    items: items,
    size: items.length,
    serverId: library.serverId,
    libraryId: library.id,
  );

  /// Rows for [library]; empty for music libraries or on errors.
  static Future<List<MediaHub>> build(MediaServerClient client, MediaLibrary library, AudioMode mode) async {
    final serverId = library.serverId;
    if (serverId == null || mode == AudioMode.music) return const [];
    try {
      await AudioExtras.instance.load();
      final tracks = await _tracks(client, library);
      if (tracks.isEmpty) return const [];
      return mode == AudioMode.podcast
          ? _podcastRows(library, tracks)
          : _bookRows(library, serverId, tracks, mode);
    } catch (e) {
      appLogger.d('Audio library rows failed for ${library.title}', error: e);
      return const [];
    }
  }

  static List<MediaHub> _podcastRows(MediaLibrary library, List<MediaItem> tracks) {
    final extras = AudioExtras.instance;
    int stamp(MediaItem i) =>
        DateTime.tryParse(i.originallyAvailableAt ?? '')?.millisecondsSinceEpoch ?? (i.addedAt ?? 0) * 1000;
    final fresh = [
      for (final t in tracks)
        if (!extras.isPlayed(t) && (t.viewCount ?? 0) == 0) t,
    ]..sort((a, b) => stamp(b).compareTo(stamp(a)));
    return [
      if (fresh.isNotEmpty) _hub(library, 'new_episodes', RetroStrings.audioNewEpisodes, 'track', fresh.take(30).toList()),
    ];
  }

  static List<MediaHub> _bookRows(MediaLibrary library, String serverId, List<MediaItem> tracks, AudioMode mode) {
    final extras = AudioExtras.instance;
    final started = extras.startedKeys;
    final finished = extras.finishedKeys;

    // Albums (books, episodes) from their tracks.
    final albums = <String, MediaItem>{};
    final lengths = <String, int>{};
    for (final t in tracks) {
      final id = t.parentId;
      if (id == null) continue;
      lengths[id] = (lengths[id] ?? 0) + (t.durationMs ?? 0);
      albums.putIfAbsent(
        id,
        () => MediaItem(
          id: id,
          backend: t.backend,
          kind: MediaKind.album,
          title: t.parentTitle ?? '',
          thumbPath: t.parentThumbPath ?? t.thumbPath,
          parentId: t.grandparentId,
          parentTitle: t.grandparentTitle,
          year: t.year,
          addedAt: t.addedAt,
          serverId: serverId,
          libraryId: library.id,
        ),
      );
    }
    bool untouched(String id) => !started.contains('$serverId:$id') && !finished.contains('$serverId:$id');
    final fresh = [for (final e in albums.entries) if (untouched(e.key)) e.value];

    // More from the author listened to last.
    final author = extras.lastAuthor(serverId, library.id);
    final byAuthor = author == null ? const <MediaItem>[] : [for (final a in fresh) if (a.parentTitle == author) a];

    // Short listens.
    final short = [
      for (final a in fresh)
        if ((lengths[a.id] ?? 0) > 0 && Duration(milliseconds: lengths[a.id]!) < _short) a,
    ]..sort((a, b) => (lengths[a.id] ?? 0).compareTo(lengths[b.id] ?? 0));

    // Not started yet: a different pick each day.
    final now = DateTime.now();
    final pick = [...fresh]..shuffle(math.Random(now.year * 1000 + now.month * 50 + now.day));

    // Next in series: per author with finished episodes, the first one in
    // number order that is neither finished nor started.
    final series = <String, List<MediaItem>>{};
    for (final a in albums.values) {
      final key = a.parentTitle;
      if (key == null || key.isEmpty) continue;
      series.putIfAbsent(key, () => []).add(a);
    }
    final next = <MediaItem>[];
    for (final list in series.values) {
      if (list.length < 2) continue;
      if (!list.any((a) => finished.contains('$serverId:${a.id}'))) continue;
      list.sort((a, b) {
        final na = _number(a.title ?? '');
        final nb = _number(b.title ?? '');
        if (na != null && nb != null && na != nb) return na.compareTo(nb);
        return (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase());
      });
      final upcoming = list.where((a) => untouched(a.id)).firstOrNull;
      if (upcoming != null) next.add(upcoming);
    }

    return [
      if (next.isNotEmpty) _hub(library, 'next_in_series', RetroStrings.audioNextInSeries, 'album', next.take(40).toList()),
      if (byAuthor.isNotEmpty)
        _hub(library, 'more_from_author', RetroStrings.audioMoreFrom(author!), 'album', byAuthor.take(30).toList()),
      if (short.isNotEmpty) _hub(library, 'short_listens', RetroStrings.audioShortListens, 'album', short.take(30).toList()),
      if (pick.isNotEmpty)
        _hub(
          library,
          'not_started',
          mode == AudioMode.audioDrama ? RetroStrings.audioNotHeardYet : RetroStrings.audioNotStarted,
          'album',
          pick.take(20).toList(),
        ),
    ];
  }
}
