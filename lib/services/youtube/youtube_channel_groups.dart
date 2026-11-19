import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A named set of channels, e.g. "Music" or "Tech".
class YouTubeChannelGroup {
  YouTubeChannelGroup(this.name, Set<String> channelIds) : channelIds = Set.unmodifiable(channelIds);

  final String name;
  final Set<String> channelIds;

  Map<String, Object> toJson() => {'name': name, 'channels': channelIds.toList()};
}

/// User-made channel groups, used as quick filters on the subscriptions page.
class YouTubeChannelGroups extends ChangeNotifier {
  YouTubeChannelGroups._();

  static final YouTubeChannelGroups instance = YouTubeChannelGroups._();
  static const _kKey = 'youtube_channel_groups';

  SharedPreferences? _prefs;
  Future<void>? _loading;
  List<YouTubeChannelGroup> _groups = [];

  List<YouTubeChannelGroup> get groups => List.unmodifiable(_groups);

  YouTubeChannelGroup? byName(String? name) =>
      name == null ? null : _groups.where((g) => g.name == name).firstOrNull;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_kKey);
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      _groups = [
        for (final e in list)
          if (e is Map && e['name'] is String)
            YouTubeChannelGroup(e['name'] as String, {...(e['channels'] as List? ?? const []).whereType<String>()}),
      ];
    } catch (_) {
      _groups = [];
    }
    _prefs = prefs;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode([for (final g in _groups) g.toJson()]));
    notifyListeners();
  }

  /// Creates or replaces a group. Renaming passes the old name as [previousName].
  Future<void> put(String name, Set<String> channelIds, {String? previousName}) async {
    await load();
    final group = YouTubeChannelGroup(name, channelIds);
    var at = _groups.indexWhere((g) => g.name == (previousName ?? name));
    if (at >= 0) {
      _groups[at] = group;
    } else {
      _groups.add(group);
      at = _groups.length - 1;
    }
    // A rename onto an existing name replaces that group.
    for (var i = _groups.length - 1; i >= 0; i--) {
      if (i != at && _groups[i].name == name) _groups.removeAt(i);
    }
    await _save();
  }

  Future<void> remove(String name) async {
    await load();
    _groups.removeWhere((g) => g.name == name);
    await _save();
  }
}
