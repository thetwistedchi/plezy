import 'package:shared_preferences/shared_preferences.dart';

import '../../media/media_item.dart';

/// Fork: titles removed from Continue Watching on servers that cannot do it
/// themselves (Jellyfin). Kept on this device with their position: once the
/// title is played further, it shows again.
class HiddenContinueWatching {
  HiddenContinueWatching._();
  static final instance = HiddenContinueWatching._();

  static const _key = 'retrowave_hidden_continue_watching';
  Map<String, int>? _hidden;

  static String _id(MediaItem item) => '${item.serverId}|${item.id}';

  Future<Map<String, int>> _load() async {
    if (_hidden != null) return _hidden!;
    final prefs = await SharedPreferences.getInstance();
    final map = <String, int>{};
    for (final entry in prefs.getStringList(_key) ?? const <String>[]) {
      final i = entry.lastIndexOf('@');
      if (i > 0) map[entry.substring(0, i)] = int.tryParse(entry.substring(i + 1)) ?? 0;
    }
    return _hidden = map;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = [for (final e in _hidden!.entries) '${e.key}@${e.value}'];
    await prefs.setStringList(_key, list.length > 300 ? list.sublist(list.length - 300) : list);
  }

  Future<void> hide(MediaItem item) async {
    final map = await _load();
    map[_id(item)] = item.viewOffsetMs ?? 0;
    await _save();
  }

  /// [items] without the hidden ones whose position has not moved since.
  Future<List<MediaItem>> filter(List<MediaItem> items) async {
    final map = await _load();
    if (map.isEmpty) return items;
    var changed = false;
    final out = <MediaItem>[];
    for (final item in items) {
      final hiddenAt = map[_id(item)];
      if (hiddenAt == null) {
        out.add(item);
      } else if ((item.viewOffsetMs ?? 0) != hiddenAt) {
        // Watched further: it belongs in Continue Watching again.
        map.remove(_id(item));
        changed = true;
        out.add(item);
      }
    }
    if (changed) await _save();
    return out;
  }
}
