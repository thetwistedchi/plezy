import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'youtube_service.dart';

/// The user's own YouTube watchlist: videos queued with the + button, in
/// order, kept across restarts. Stores the whole video so an entry survives
/// after it drops out of the subscriptions feed.
class YouTubeWatchlist extends ChangeNotifier {
  YouTubeWatchlist._();

  static final YouTubeWatchlist instance = YouTubeWatchlist._();

  static const _kKey = 'youtube_watchlist';

  /// youtube.com's ad-hoc playlist link takes at most 50 IDs.
  static const int maxBrowserQueue = 50;

  SharedPreferences? _prefs;
  List<YouTubeVideo> _items = [];

  List<YouTubeVideo> get items => List.unmodifiable(_items);
  int get length => _items.length;
  bool contains(String videoId) => _items.any((v) => v.id == videoId);

  Future<void> load() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
    try {
      final raw = _prefs!.getString(_kKey);
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      _items = [
        for (final e in list)
          if (YouTubeVideo.fromJson(e as Map<String, dynamic>) case final video?) video,
      ];
    } catch (_) {
      _items = [];
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await load();
    await _prefs!.setString(_kKey, jsonEncode([for (final v in _items) v.toJson()]));
    notifyListeners();
  }

  Future<void> toggle(YouTubeVideo video) async {
    await load();
    if (contains(video.id)) {
      _items.removeWhere((v) => v.id == video.id);
    } else {
      _items.add(video);
    }
    await _save();
  }

  Future<void> remove(String videoId) async {
    await load();
    _items.removeWhere((v) => v.id == videoId);
    await _save();
  }

  Future<void> clear() async {
    await load();
    _items.clear();
    await _save();
  }

  /// Moves the entry at [oldIndex] to [newIndex] (ReorderableList indices).
  Future<void> reorder(int oldIndex, int newIndex) async {
    await load();
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _items.removeAt(oldIndex);
    _items.insert(newIndex, item);
    await _save();
  }

  /// A youtube.com link that plays the first [maxBrowserQueue] entries in a row.
  Uri? browserQueueUrl() {
    if (_items.isEmpty) return null;
    final ids = _items.take(maxBrowserQueue).map((v) => v.id).join(',');
    return Uri.https('www.youtube.com', '/watch_videos', {'video_ids': ids});
  }
}
