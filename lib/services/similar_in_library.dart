import '../i18n/retro_strings.dart';
import '../media/library_query.dart';
import '../media/media_filter.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import 'plex_client.dart';
import 'ratings/rating_median_cache.dart';

/// "Similar in your library": titles of the same library that share genres
/// with [item], ranked by how many genres they share and then by score
/// (the cached rating median, else the server's own rating). Null when the
/// item has no genres or nothing matches.
Future<MediaHub?> similarInLibraryHub(MediaServerClient client, MediaItem item) async {
  final libraryId = item.libraryId;
  final genres = {for (final g in item.genres ?? const <String>[]) g.toLowerCase()};
  if (libraryId == null || genres.isEmpty || !(item.isMovie || item.isShow)) return null;
  try {
    final filterResult = await client.fetchLibraryFiltersWithValues(libraryId, libraryKind: item.kind);
    final genreField = filterResult.filters
        .where((f) => f.filter == MediaFilterField.genre && f.hasValueList)
        .firstOrNull;
    if (genreField == null) return null;
    var values = filterResult.cachedValues[genreField.filter] ?? const <MediaFilterValue>[];
    if (values.isEmpty && client is PlexClient) values = await client.getFilterValues(genreField.key);
    final ids = [
      for (final v in values)
        if (genres.contains(v.title.toLowerCase())) libraryFilterValueId(v.key, MediaFilterField.genre),
    ];
    if (ids.isEmpty) return null;

    final page = await client.fetchLibraryPagedContent(
      libraryId,
      libraryKind: item.kind,
      query: LibraryQuery(
        kind: item.kind,
        limit: 150,
        // Values inside one clause OR: anything sharing at least one genre.
        filters: [LibraryFilter(field: genreField.filter, values: ids)],
        sort: const LibrarySort(field: 'audienceRating'),
      ),
    );

    final medians = RatingMedianCache.instance;
    int score(MediaItem candidate) {
      final shared = (candidate.genres ?? const <String>[]).where((g) => genres.contains(g.toLowerCase())).length;
      final median = medians.medianFor(candidate)?.score ?? ((candidate.rating ?? 0) * 10).round();
      return shared * 1000 + median;
    }

    final ranked = page.items.where((candidate) => candidate.id != item.id).toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    final picks = ranked.take(20).toList();
    if (picks.isEmpty) return null;
    return MediaHub(
      id: 'retro.similar.${item.id}',
      identifier: 'retro.similar',
      title: RetroStrings.similarInLibrary,
      type: item.isShow ? 'show' : 'movie',
      items: picks,
      size: picks.length,
      serverId: item.serverId,
      serverName: item.serverName,
    );
  } catch (e) {
    appLogger.d('Similar in library failed for "${item.title}"', error: e);
    return null;
  }
}
