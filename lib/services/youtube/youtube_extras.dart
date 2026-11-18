import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:local_notifier/local_notifier.dart';

import '../../utils/app_logger.dart';
import 'youtube_service.dart';
import 'youtube_settings.dart';

/// Community titles and thumbnails replacing clickbait, from DeArrow
/// (dearrow.ajay.app, by the SponsorBlock makers). Looked up lazily per
/// video and kept in memory.
class DeArrow extends ChangeNotifier {
  DeArrow._();

  static final DeArrow instance = DeArrow._();
  static const int _parallel = 6;

  final http.Client _client = http.Client();
  final Map<String, ({String? title, double? thumbnailTime})> _cache = {};
  final List<String> _queue = [];
  final Set<String> _pending = {};
  int _running = 0;
  Timer? _notify;

  /// The community title for [video], or its own.
  String titleFor(YouTubeVideo video) {
    if (!YouTubeSettings.instance.deArrowTitles) return video.title;
    _request(video.id);
    return _cache[video.id]?.title ?? video.title;
  }

  /// A thumbnail at the community-picked moment, or the original.
  String? thumbnailFor(YouTubeVideo video) {
    if (!YouTubeSettings.instance.deArrowThumbnails) return video.thumbnailUrl;
    _request(video.id);
    final time = _cache[video.id]?.thumbnailTime;
    if (time == null) return video.thumbnailUrl;
    return Uri.https('dearrow-thumb.ajay.app', '/api/v1/getThumbnail', {
      'videoID': video.id,
      'time': time.toString(),
    }).toString();
  }

  void _request(String id) {
    if (_cache.containsKey(id) || _pending.contains(id)) return;
    _pending.add(id);
    _queue.add(id);
    _pump();
  }

  void _pump() {
    while (_running < _parallel && _queue.isNotEmpty) {
      final id = _queue.removeLast();
      _running++;
      unawaited(
        _fetch(id).whenComplete(() {
          _running--;
          _pending.remove(id);
          _pump();
        }),
      );
    }
  }

  Future<void> _fetch(String id) async {
    try {
      final response = await _client
          .get(Uri.https('sponsor.ajay.app', '/api/branding', {'videoID': id}))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _cache[id] = (title: null, thumbnailTime: null);
        return;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      String? title;
      for (final t in (json['titles'] as List? ?? const [])) {
        if (t is! Map || t['original'] == true) continue;
        final votes = (t['votes'] as num?)?.toInt() ?? 0;
        if (votes < 0 && t['locked'] != true) continue;
        title = _cleanTitle(t['title'] as String? ?? '');
        break;
      }
      double? time;
      for (final t in (json['thumbnails'] as List? ?? const [])) {
        if (t is! Map || t['original'] == true) continue;
        final votes = (t['votes'] as num?)?.toInt() ?? 0;
        if (votes < 0 && t['locked'] != true) continue;
        time = (t['timestamp'] as num?)?.toDouble();
        break;
      }
      _cache[id] = (title: (title?.isEmpty ?? true) ? null : title, thumbnailTime: time);
      while (_cache.length > 5000) {
        _cache.remove(_cache.keys.first);
      }
      if (title != null || time != null) {
        _notify ??= Timer(const Duration(milliseconds: 400), () {
          _notify = null;
          notifyListeners();
        });
      }
    } catch (e) {
      _cache[id] = (title: null, thumbnailTime: null);
    }
  }

  /// DeArrow marks words to keep as typed with a leading ">".
  static String _cleanTitle(String title) => title.replaceAll(RegExp(r'(^|\s)>(?=\S)'), r'$1').trim();
}

/// Estimated dislikes from Return YouTube Dislike
/// (returnyoutubedislikeapi.com).
class ReturnDislike {
  ReturnDislike._();

  static final http.Client _client = http.Client();

  static Future<({int likes, int dislikes})?> votes(String videoId) async {
    if (!YouTubeSettings.instance.returnDislikes) return null;
    try {
      final response = await _client
          .get(Uri.https('returnyoutubedislikeapi.com', '/votes', {'videoId': videoId}))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (likes: (json['likes'] as num?)?.toInt() ?? 0, dislikes: (json['dislikes'] as num?)?.toInt() ?? 0);
    } catch (e) {
      appLogger.d('Return YouTube Dislike failed: $e');
      return null;
    }
  }
}

/// Windows notifications for new videos from favourite channels.
class YouTubeNotifier {
  YouTubeNotifier._();

  static bool _setUp = false;

  /// Called by the app when a notification is clicked, with the video.
  static void Function(YouTubeVideo video)? onOpen;

  static Future<void> notifyNew(List<YouTubeVideo> videos) async {
    if (!Platform.isWindows || videos.isEmpty || !YouTubeSettings.instance.notifyFavorites) return;
    try {
      if (!_setUp) {
        await localNotifier.setup(appName: 'Plezy Retrowave');
        _setUp = true;
      }
      for (final video in videos.take(5)) {
        final notification = LocalNotification(title: video.channelTitle, body: video.title);
        notification.onClick = () => onOpen?.call(video);
        await notification.show();
      }
    } catch (e) {
      appLogger.w('YouTube notification failed', error: e);
    }
  }
}
