import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/app_logger.dart';
import 'youtube_service.dart';

/// One entry: a new video from a favourite channel, and whether it was seen.
class YouTubeNotificationEntry {
  YouTubeNotificationEntry({required this.video, required this.at, this.read = false});

  final YouTubeVideo video;
  final DateTime at;
  bool read;

  Map<String, dynamic> toJson() => {'v': video.toJson(), 'at': at.toIso8601String(), 'r': read};

  static YouTubeNotificationEntry? fromJson(Map<String, dynamic> json) {
    final video = json['v'] is Map ? YouTubeVideo.fromJson(Map<String, dynamic>.from(json['v'] as Map)) : null;
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (video == null || at == null) return null;
    return YouTubeNotificationEntry(video: video, at: at, read: json['r'] as bool? ?? false);
  }
}

/// Fork: every new video from a favourite channel the feed found, kept on
/// the device (newest first, at most [_max]), whether or not a Windows
/// notification was shown for it.
class YouTubeNotificationHistory extends ChangeNotifier {
  YouTubeNotificationHistory._();
  static final instance = YouTubeNotificationHistory._();

  static const _max = 200;

  final List<YouTubeNotificationEntry> _entries = [];
  Future<void>? _loaded;

  List<YouTubeNotificationEntry> get entries => List.unmodifiable(_entries);
  int get unread => _entries.where((e) => !e.read).length;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}youtube_notifications.json');
  }

  Future<void> load() => _loaded ??= _load();

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List;
      _entries
        ..clear()
        ..addAll([
          for (final e in list.whereType<Map>()) ?YouTubeNotificationEntry.fromJson(Map<String, dynamic>.from(e)),
        ]);
      notifyListeners();
    } catch (e) {
      appLogger.d('YouTube notification history unreadable', error: e);
    }
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode([for (final e in _entries) e.toJson()]));
    } catch (e) {
      appLogger.d('Saving the YouTube notification history failed', error: e);
    }
  }

  /// Adds [videos] that are not listed yet.
  Future<void> add(List<YouTubeVideo> videos) async {
    if (videos.isEmpty) return;
    await load();
    final known = {for (final e in _entries) e.video.id};
    final now = DateTime.now();
    final fresh = [
      for (final v in videos)
        if (!known.contains(v.id)) YouTubeNotificationEntry(video: v, at: now),
    ]..sort((a, b) => b.video.publishedAt.compareTo(a.video.publishedAt));
    if (fresh.isEmpty) return;
    _entries.insertAll(0, fresh);
    if (_entries.length > _max) _entries.removeRange(_max, _entries.length);
    notifyListeners();
    await _save();
  }

  Future<void> markRead(String videoId) async {
    var changed = false;
    for (final e in _entries) {
      if (e.video.id == videoId && !e.read) {
        e.read = true;
        changed = true;
      }
    }
    if (!changed) return;
    notifyListeners();
    await _save();
  }

  Future<void> remove(String videoId) async {
    final before = _entries.length;
    _entries.removeWhere((e) => e.video.id == videoId);
    if (_entries.length == before) return;
    notifyListeners();
    await _save();
  }

  Future<void> markAllRead() async {
    if (unread == 0) return;
    for (final e in _entries) {
      e.read = true;
    }
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _save();
  }
}
