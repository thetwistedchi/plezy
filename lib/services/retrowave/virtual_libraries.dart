import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/retro_strings.dart';
import '../../media/media_backend.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../screens/free_on_plex_screen.dart' show FreeOnPlexScreen;
import '../../screens/retrowave/upcoming_episodes_screen.dart';


/// Fork: app pages that sit in the libraries list like a library: Upcoming
/// episodes and Free on Plex. They can be moved and hidden in Manage
/// libraries like real ones; their place among the real libraries is kept
/// here (the server libraries' own order stays where it was).
class VirtualLibraries {
  VirtualLibraries._();

  static const upcomingId = 'retrowave-upcoming';
  static const freeOnPlexId = 'retrowave-freeonplex';
  static const _orderKey = 'retrowave_virtual_library_order';

  /// Bumped when the order changes, for the sidebar and Home.
  static final ValueNotifier<int> revision = ValueNotifier(0);
  static List<String> _order = const [];

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _order = prefs.getStringList(_orderKey) ?? const [];
    revision.value++;
  }

  static List<MediaLibrary> entries({required bool withPlex}) => [
    MediaLibrary(id: upcomingId, backend: MediaBackend.plex, title: RetroStrings.upcomingEpisodes, kind: MediaKind.show),
    if (withPlex) MediaLibrary(id: freeOnPlexId, backend: MediaBackend.plex, title: RetroStrings.freeOnPlex),
  ];

  static bool isVirtual(MediaLibrary library) => library.serverId == null && library.id.startsWith('retrowave-');

  static IconData iconFor(MediaLibrary library) =>
      library.id == upcomingId ? Symbols.calendar_month_rounded : Symbols.local_activity_rounded;

  /// [libraries] with the app pages at their saved places (at the end when
  /// never moved). An app page follows the library it was placed after.
  /// Free on Plex only with a Plex server among [libraries].
  static List<MediaLibrary> merge(List<MediaLibrary> libraries) {
    final result = List<MediaLibrary>.of(libraries);
    final withPlex = libraries.any((l) => l.serverId != null && l.backend == MediaBackend.plex);
    for (final entry in entries(withPlex: withPlex)) {
      final at = _order.indexOf(entry.globalKey);
      if (at < 0) {
        result.add(entry);
        continue;
      }
      // The nearest earlier key that is shown now decides the place.
      var insertAt = 0;
      for (var i = at - 1; i >= 0; i--) {
        final index = result.indexWhere((l) => l.globalKey == _order[i]);
        if (index >= 0) {
          insertAt = index + 1;
          break;
        }
      }
      result.insert(insertAt, entry);
    }
    return result;
  }

  /// Keeps the places of the app pages in [merged] (the whole list as shown
  /// in Manage libraries) and returns the server libraries alone, in order.
  static Future<List<MediaLibrary>> saveOrder(List<MediaLibrary> merged) async {
    _order = [for (final library in merged) library.globalKey];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, _order);
    revision.value++;
    return [for (final library in merged) if (!isVirtual(library)) library];
  }

  static Future<void> open(BuildContext context, MediaLibrary library) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => library.id == upcomingId ? const UpcomingEpisodesScreen() : const FreeOnPlexScreen(),
    ),
  );
}
