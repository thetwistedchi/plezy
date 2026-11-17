import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';
import 'youtube_auth.dart';
import 'youtube_settings.dart';

class YouTubeApiException implements Exception {
  YouTubeApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'YouTube API $statusCode: $message';
}

class YouTubeVideo {
  YouTubeVideo({
    required this.id,
    required this.title,
    required this.channelId,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.publishedAt,
    required this.duration,
    required this.viewCount,
    required this.isUpcoming,
    required this.isLive,
  });

  final String id;
  final String title;
  final String channelId;
  final String channelTitle;
  final String? thumbnailUrl;
  final DateTime publishedAt;
  final Duration duration;
  final int viewCount;

  /// A scheduled premiere or stream that hasn't started.
  final bool isUpcoming;

  /// A premiere or stream that is live right now.
  final bool isLive;

  bool isShort = false;

  Uri get watchUrl => Uri.https('www.youtube.com', '/watch', {'v': id});
}

enum YouTubeSort { newest, relevant }

/// Why a video ranks high in the "Most relevant" sort.
enum YouTubeRelevanceReason { trending, favoriteChannel }

/// Fetches the newest uploads of the signed-in user's subscriptions.
///
/// Quota per refresh: one unit per 50 subscriptions, one per channel for its
/// uploads playlist and one per 50 videos for details. With ~100 channels
/// that is ~105 units, so a 30 minute refresh stays far inside the default
/// 10,000 units a day.
class YouTubeService extends ChangeNotifier {
  YouTubeService._();

  static final YouTubeService instance = YouTubeService._();

  static const int _uploadsPerChannel = 6;
  static const int _maxVideos = 300;
  static const int _parallel = 8;

  final http.Client _client = http.Client();
  final Map<String, bool> _shortCache = {};

  List<YouTubeVideo> _videos = const [];
  Map<String, double> _channelMedianViews = const {};
  bool _loading = false;
  Object? _error;
  DateTime? _lastUpdated;
  Timer? _timer;
  Future<void>? _inFlight;

  List<YouTubeVideo> get videos => _videos;
  bool get isLoading => _loading;
  Object? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  /// Starts (or restarts) the periodic refresh and loads once if needed.
  void ensureStarted() {
    final settings = YouTubeSettings.instance;
    _timer?.cancel();
    if (!settings.isSignedIn) return;
    _timer = Timer.periodic(Duration(minutes: settings.refreshMinutes), (_) => unawaited(refresh()));
    final last = _lastUpdated;
    if (last == null || DateTime.now().difference(last).inMinutes >= settings.refreshMinutes) {
      unawaited(refresh());
    }
  }

  void clear() {
    _timer?.cancel();
    _videos = const [];
    _lastUpdated = null;
    _error = null;
    notifyListeners();
  }

  Future<void> refresh() => _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<void> _refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final channels = await _subscriptions();
      final videoIds = <String>[];
      for (var i = 0; i < channels.length; i += _parallel) {
        final batch = channels.skip(i).take(_parallel);
        final results = await Future.wait(batch.map(_latestUploads));
        for (final ids in results) {
          videoIds.addAll(ids);
        }
      }
      final videos = await _videoDetails(videoIds);
      await _detectShorts(videos);
      videos.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      _videos = videos.take(_maxVideos).toList();
      _channelMedianViews = _medianViewsByChannel(_videos);
      _lastUpdated = DateTime.now();
    } catch (e, st) {
      appLogger.w('YouTube refresh failed', error: e, stackTrace: st);
      _error = e;
      if (e is YouTubeAuthException && e.signedOut) _timer?.cancel();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Videos to show, after the Shorts / premiere filters and the sort.
  List<YouTubeVideo> visibleVideos({required YouTubeSort sort, required bool unwatchedOnly}) {
    final settings = YouTubeSettings.instance;
    final list = _videos.where((v) {
      if (!settings.showShorts && v.isShort) return false;
      if (!settings.showPremieres && (v.isUpcoming || v.isLive)) return false;
      if (unwatchedOnly && settings.isWatched(v.id)) return false;
      return true;
    }).toList();
    if (sort == YouTubeSort.relevant) {
      final now = DateTime.now();
      final scores = {for (final v in list) v.id: _relevance(v, now)};
      list.sort((a, b) => scores[b.id]!.compareTo(scores[a.id]!));
    }
    return list;
  }

  /// How many times more views [video] has than its channel's usual video.
  double trendFactor(YouTubeVideo video) {
    final median = _channelMedianViews[video.channelId] ?? 0;
    if (median <= 0) return 1;
    return video.viewCount / median;
  }

  YouTubeRelevanceReason? relevanceReason(YouTubeVideo video) {
    if (trendFactor(video) >= 2) return YouTubeRelevanceReason.trending;
    if (YouTubeSettings.instance.channelOpens(video.channelId) >= 3) return YouTubeRelevanceReason.favoriteChannel;
    return null;
  }

  double _relevance(YouTubeVideo video, DateTime now) {
    final ageHours = max(0, now.difference(video.publishedAt).inMinutes) / 60;
    final freshness = pow(0.5, ageHours / 48).toDouble();
    final trend = log(1 + trendFactor(video).clamp(0, 10));
    final affinity = log(1 + YouTubeSettings.instance.channelOpens(video.channelId));
    return freshness * 2 + trend + affinity * 0.8;
  }

  static Map<String, double> _medianViewsByChannel(List<YouTubeVideo> videos) {
    final byChannel = <String, List<int>>{};
    for (final v in videos) {
      byChannel.putIfAbsent(v.channelId, () => []).add(v.viewCount);
    }
    return {
      for (final e in byChannel.entries)
        if (e.value.length >= 3) e.key: _median(e.value),
    };
  }

  static double _median(List<int> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid].toDouble() : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query, {bool retried = false}) async {
    final token = await YouTubeAuth.instance.accessToken();
    final response = await _client.get(
      Uri.https('www.googleapis.com', '/youtube/v3/$path', query),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );
    if (response.statusCode == 401 && !retried) {
      YouTubeAuth.instance.invalidateAccessToken();
      return _get(path, query, retried: true);
    }
    if (response.statusCode != 200) {
      throw YouTubeApiException(response.statusCode, _apiError(response.body));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Channel IDs of every subscription.
  Future<List<String>> _subscriptions() async {
    final ids = <String>[];
    String? pageToken;
    do {
      final json = await _get('subscriptions', {
        'part': 'snippet',
        'mine': 'true',
        'maxResults': '50',
        'pageToken': ?pageToken,
      });
      for (final item in (json['items'] as List? ?? const [])) {
        final id = (item as Map)['snippet']?['resourceId']?['channelId'] as String?;
        if (id != null) ids.add(id);
      }
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null);
    return ids;
  }

  /// The newest upload IDs of [channelId], via its "uploads" playlist.
  Future<List<String>> _latestUploads(String channelId) async {
    if (!channelId.startsWith('UC')) return const [];
    try {
      final json = await _get('playlistItems', {
        'part': 'contentDetails',
        'playlistId': 'UU${channelId.substring(2)}',
        'maxResults': '$_uploadsPerChannel',
      });
      return [
        for (final item in (json['items'] as List? ?? const []))
          if ((item as Map)['contentDetails']?['videoId'] case final String id) id,
      ];
    } on YouTubeApiException catch (e) {
      // A channel without public uploads has no uploads playlist.
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  Future<List<YouTubeVideo>> _videoDetails(List<String> ids) async {
    final videos = <YouTubeVideo>[];
    for (var i = 0; i < ids.length; i += 50) {
      final chunk = ids.skip(i).take(50).join(',');
      final json = await _get('videos', {
        'part': 'snippet,contentDetails,statistics,liveStreamingDetails',
        'id': chunk,
        'maxResults': '50',
      });
      for (final raw in (json['items'] as List? ?? const [])) {
        final video = _parseVideo(raw as Map<String, dynamic>);
        if (video != null) videos.add(video);
      }
    }
    return videos;
  }

  static YouTubeVideo? _parseVideo(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final snippet = json['snippet'] as Map<String, dynamic>?;
    if (id == null || snippet == null) return null;
    final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? const {};
    final thumb = (thumbs['maxres'] ?? thumbs['standard'] ?? thumbs['high'] ?? thumbs['medium']) as Map?;
    final broadcast = snippet['liveBroadcastContent'] as String? ?? 'none';
    final live = json['liveStreamingDetails'] as Map<String, dynamic>?;
    final startedNotEnded = live != null && live['actualStartTime'] != null && live['actualEndTime'] == null;
    return YouTubeVideo(
      id: id,
      title: snippet['title'] as String? ?? '',
      channelId: snippet['channelId'] as String? ?? '',
      channelTitle: snippet['channelTitle'] as String? ?? '',
      thumbnailUrl: thumb?['url'] as String?,
      publishedAt: DateTime.tryParse(snippet['publishedAt'] as String? ?? '') ?? DateTime.now(),
      duration: parseIsoDuration(json['contentDetails']?['duration'] as String? ?? ''),
      viewCount: int.tryParse(json['statistics']?['viewCount']?.toString() ?? '') ?? 0,
      isUpcoming: broadcast == 'upcoming',
      isLive: broadcast == 'live' || startedNotEnded,
    );
  }

  /// Shorts can't be told apart through the API. A video up to three minutes
  /// long is checked against youtube.com/shorts/<id>, which answers 200 for a
  /// Short and redirects to the normal watch page otherwise.
  Future<void> _detectShorts(List<YouTubeVideo> videos) async {
    final candidates = videos.where((v) => v.duration > Duration.zero && v.duration <= const Duration(minutes: 3));
    final unknown = [
      for (final v in candidates)
        if (!_shortCache.containsKey(v.id)) v,
    ];
    for (var i = 0; i < unknown.length; i += _parallel) {
      await Future.wait(unknown.skip(i).take(_parallel).map((v) async => _shortCache[v.id] = await _isShort(v.id)));
    }
    for (final v in videos) {
      v.isShort = _shortCache[v.id] ?? false;
    }
  }

  Future<bool> _isShort(String id) async {
    try {
      final request = http.Request('HEAD', Uri.https('www.youtube.com', '/shorts/$id'))..followRedirects = false;
      final response = await _client.send(request).timeout(const Duration(seconds: 8));
      await response.stream.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Display name of the signed-in channel, for the settings screen.
  Future<String?> fetchAccountName() async {
    final json = await _get('channels', {'part': 'snippet', 'mine': 'true'});
    final items = json['items'] as List? ?? const [];
    if (items.isEmpty) return null;
    return (items.first as Map)['snippet']?['title'] as String?;
  }

  static String _apiError(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['error']?['message'] ?? body).toString();
    } catch (_) {
      return body;
    }
  }
}

/// Parses an ISO 8601 duration such as PT1H2M3S.
Duration parseIsoDuration(String value) {
  final match = RegExp(r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(value);
  if (match == null) return Duration.zero;
  int part(int i) => int.tryParse(match.group(i) ?? '') ?? 0;
  return Duration(days: part(1), hours: part(2), minutes: part(3), seconds: part(4));
}
