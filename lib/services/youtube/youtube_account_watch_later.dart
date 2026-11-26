import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'youtube_service.dart';
import 'youtube_webview.dart';

/// Fork: the Watch later list of the signed-in YouTube account, read from
/// youtube.com (the API no longer hands it out) and kept apart from the
/// app's own watch list.
class YouTubeAccountWatchLater extends ChangeNotifier {
  YouTubeAccountWatchLater._();

  static final YouTubeAccountWatchLater instance = YouTubeAccountWatchLater._();

  static const _kKey = 'youtube_account_watch_later';
  static const _kAtKey = 'youtube_account_watch_later_at';

  SharedPreferences? _prefs;
  List<YouTubeVideo> _items = [];
  DateTime? updatedAt;
  bool loading = false;

  List<YouTubeVideo> get items => List.unmodifiable(_items);
  int get length => _items.length;

  Future<void> load() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
    try {
      final raw = _prefs!.getString(_kKey);
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      _items = [for (final e in list) ?YouTubeVideo.fromJson(e as Map<String, dynamic>)];
      final at = _prefs!.getInt(_kAtKey);
      updatedAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    } catch (_) {
      _items = [];
    }
    notifyListeners();
  }

  /// Reads the list from youtube.com again. False when it could not be read
  /// (player not signed in, page changed).
  Future<bool> refresh() async {
    await load();
    loading = true;
    notifyListeners();
    try {
      final raw = await YouTubeWebView.watchLater();
      if (raw == null) return false;
      _items = [
        for (final i in raw)
          if ((i['id'] as String? ?? '').isNotEmpty)
            YouTubeVideo(
              id: i['id'] as String,
              title: i['t'] as String? ?? '',
              channelId: i['ci'] as String? ?? '',
              channelTitle: i['c'] as String? ?? '',
              thumbnailUrl: 'https://i.ytimg.com/vi/${i['id']}/hqdefault.jpg',
              publishedAt: DateTime.now(),
              viewCount: 0,
              isShort: false,
              duration: Duration(seconds: (i['s'] as num?)?.toInt() ?? 0),
            ),
      ];
      updatedAt = DateTime.now();
      await _prefs!.setString(_kKey, jsonEncode([for (final v in _items) v.toJson()]));
      await _prefs!.setInt(_kAtKey, updatedAt!.millisecondsSinceEpoch);
      return true;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Hides [videoId] here (youtube.com keeps it until the next refresh).
  Future<void> remove(String videoId) async {
    await load();
    _items.removeWhere((v) => v.id == videoId);
    await _prefs!.setString(_kKey, jsonEncode([for (final v in _items) v.toJson()]));
    notifyListeners();
  }
}
