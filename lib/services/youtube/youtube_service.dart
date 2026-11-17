import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

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
    required this.viewCount,
    required this.isShort,
    this.duration = Duration.zero,
    this.isUpcoming = false,
    this.isLive = false,
    this.hasDetails = false,
  });

  final String id;
  String title;
  final String channelId;
  String channelTitle;
  String? thumbnailUrl;
  final DateTime publishedAt;
  int viewCount;
  bool isShort;

  /// Zero until the details were fetched from the API.
  Duration duration;

  /// A scheduled premiere or stream that hasn't started.
  bool isUpcoming;

  /// A premiere or stream that is live right now.
  bool isLive;

  /// Whether [duration], [isUpcoming] and [isLive] came from the API.
  bool hasDetails;

  Uri get watchUrl => Uri.https('www.youtube.com', '/watch', {'v': id});

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'channelId': channelId,
    'channelTitle': channelTitle,
    'thumb': thumbnailUrl,
    'published': publishedAt.toIso8601String(),
    'views': viewCount,
    'short': isShort,
    'duration': duration.inSeconds,
    'upcoming': isUpcoming,
    'live': isLive,
    'details': hasDetails,
  };

  static YouTubeVideo? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final published = DateTime.tryParse(json['published'] as String? ?? '');
    if (id == null || published == null) return null;
    return YouTubeVideo(
      id: id,
      title: json['title'] as String? ?? '',
      channelId: json['channelId'] as String? ?? '',
      channelTitle: json['channelTitle'] as String? ?? '',
      thumbnailUrl: json['thumb'] as String?,
      publishedAt: published,
      viewCount: (json['views'] as num?)?.toInt() ?? 0,
      isShort: json['short'] as bool? ?? false,
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      isUpcoming: json['upcoming'] as bool? ?? false,
      isLive: json['live'] as bool? ?? false,
      hasDetails: json['details'] as bool? ?? false,
    );
  }
}

enum YouTubeSort { newest, relevant }

/// Why a video ranks high in the "Most relevant" sort.
enum YouTubeRelevanceReason { trending, favoriteChannel }

/// Fetches the newest uploads of the signed-in user's subscriptions.
///
/// Uploads come from each channel's public RSS feed, which costs no API
/// quota. The API is used only for the subscription list (once a day, one
/// unit per 50 channels) and for the length and live state of videos not
/// seen before (one unit per 50 videos). Everything is cached on disk so the
/// tab shows the last state at once and updates in the background.
class YouTubeService extends ChangeNotifier {
  YouTubeService._();

  static final YouTubeService instance = YouTubeService._();

  static const int _parallelFeeds = 16;
  static const int _maxVideos = 1500;
  static const Duration _subscriptionsMaxAge = Duration(hours: 24);
  static const Duration _detailsWindow = Duration(days: 60);
  static const String _cacheFile = 'youtube_cache.json';

  final http.Client _client = http.Client();

  final Map<String, YouTubeVideo> _byId = {};
  List<YouTubeVideo> _videos = const [];
  List<String> _channelIds = const [];
  DateTime? _subscriptionsFetchedAt;
  Map<String, double> _channelMedianViews = const {};
  bool _cacheLoaded = false;
  bool _loading = false;
  int _channelsDone = 0;
  Object? _error;
  DateTime? _lastUpdated;
  Timer? _timer;
  Future<void>? _inFlight;

  List<YouTubeVideo> get videos => _videos;
  bool get isLoading => _loading;
  Object? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  /// Feed progress while loading, 0..1, or null when not loading.
  double? get progress => _loading && _channelIds.isNotEmpty ? _channelsDone / _channelIds.length : null;
  int get channelsDone => _channelsDone;
  int get channelCount => _channelIds.length;

  /// Shows the cached feed, starts the periodic refresh and refreshes once
  /// when the cache is stale.
  void ensureStarted() {
    final settings = YouTubeSettings.instance;
    _timer?.cancel();
    if (!settings.isSignedIn) return;
    _timer = Timer.periodic(Duration(minutes: settings.refreshMinutes), (_) => unawaited(refresh()));
    unawaited(() async {
      await _loadCache();
      final last = _lastUpdated;
      if (last == null || DateTime.now().difference(last).inMinutes >= settings.refreshMinutes) {
        await refresh();
      }
    }());
  }

  /// Forgets everything, on sign-out.
  void clear() {
    _timer?.cancel();
    _byId.clear();
    _videos = const [];
    _channelIds = const [];
    _subscriptionsFetchedAt = null;
    _lastUpdated = null;
    _error = null;
    _cacheLoaded = false;
    unawaited(_deleteCache());
    notifyListeners();
  }

  /// Refreshes the feed. [reloadSubscriptions] also reloads the channel list,
  /// which otherwise happens once a day.
  Future<void> refresh({bool reloadSubscriptions = false}) =>
      _inFlight ??= _refresh(reloadSubscriptions).whenComplete(() => _inFlight = null);

  Future<void> _refresh(bool reloadSubscriptions) async {
    await _loadCache();
    _loading = true;
    _channelsDone = 0;
    _error = null;
    notifyListeners();
    try {
      final subsAge = _subscriptionsFetchedAt == null
          ? null
          : DateTime.now().difference(_subscriptionsFetchedAt!);
      if (reloadSubscriptions || _channelIds.isEmpty || subsAge == null || subsAge > _subscriptionsMaxAge) {
        _channelIds = await _subscriptions();
        _subscriptionsFetchedAt = DateTime.now();
        final subscribed = _channelIds.toSet();
        _byId.removeWhere((_, v) => !subscribed.contains(v.channelId));
      }

      final queue = [..._channelIds];
      var lastPublish = DateTime.now();
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          final channelId = queue.removeLast();
          for (final video in await _feed(channelId)) {
            final known = _byId[video.id];
            if (known == null) {
              _byId[video.id] = video;
            } else {
              known
                ..title = video.title
                ..channelTitle = video.channelTitle
                ..thumbnailUrl = video.thumbnailUrl ?? known.thumbnailUrl
                ..viewCount = video.viewCount
                ..isShort = video.isShort;
            }
          }
          _channelsDone++;
          if (DateTime.now().difference(lastPublish) > const Duration(milliseconds: 700)) {
            lastPublish = DateTime.now();
            _publish();
          }
        }
      }

      await Future.wait(List.generate(_parallelFeeds, (_) => worker()));
      _publish();
      await _fetchDetails();
      _lastUpdated = DateTime.now();
      _publish();
      unawaited(_saveCache());
    } catch (e, st) {
      appLogger.w('YouTube refresh failed', error: e, stackTrace: st);
      _error = e;
      if (e is YouTubeAuthException && e.signedOut) _timer?.cancel();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Rebuilds the sorted list from [_byId], keeping the newest [_maxVideos].
  void _publish() {
    final all = _byId.values.toList()..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    if (all.length > _maxVideos) {
      for (final v in all.sublist(_maxVideos)) {
        _byId.remove(v.id);
      }
      all.removeRange(_maxVideos, all.length);
    }
    _videos = all;
    _channelMedianViews = _medianViewsByChannel(all);
    notifyListeners();
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
      if (v.viewCount > 0) byChannel.putIfAbsent(v.channelId, () => []).add(v.viewCount);
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

  // ---- RSS ----

  /// The latest uploads of [channelId] from its public feed. Errors are
  /// logged and skipped so one broken channel doesn't stop the refresh.
  Future<List<YouTubeVideo>> _feed(String channelId) async {
    try {
      final response = await _client
          .get(Uri.https('www.youtube.com', '/feeds/videos.xml', {'channel_id': channelId}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];
      return parseFeed(utf8.decode(response.bodyBytes), channelId);
    } catch (e) {
      appLogger.d('YouTube feed failed for $channelId: $e');
      return const [];
    }
  }

  @visibleForTesting
  static List<YouTubeVideo> parseFeed(String xml, String channelId) {
    final document = XmlDocument.parse(xml);
    final channelTitle = document.rootElement.getElement('title')?.innerText ?? '';
    final videos = <YouTubeVideo>[];
    for (final entry in document.findAllElements('entry')) {
      final id = entry.getElement('yt:videoId')?.innerText;
      final published = DateTime.tryParse(entry.getElement('published')?.innerText ?? '');
      if (id == null || id.isEmpty || published == null) continue;
      final link = entry.findElements('link').map((l) => l.getAttribute('href') ?? '').firstWhere(
        (href) => href.isNotEmpty,
        orElse: () => '',
      );
      final group = entry.getElement('media:group');
      final views = group?.getElement('media:community')?.getElement('media:statistics')?.getAttribute('views');
      videos.add(
        YouTubeVideo(
          id: id,
          title: entry.getElement('title')?.innerText ?? '',
          channelId: channelId,
          channelTitle: entry.getElement('author')?.getElement('name')?.innerText ?? channelTitle,
          thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
          publishedAt: published,
          viewCount: int.tryParse(views ?? '') ?? 0,
          isShort: link.contains('/shorts/'),
        ),
      );
    }
    return videos;
  }

  // ---- API ----

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

  /// Length and live state of recent videos not seen before, plus another
  /// look at upcoming and live ones, whose state changes.
  Future<void> _fetchDetails() async {
    final cutoff = DateTime.now().subtract(_detailsWindow);
    final ids = [
      for (final v in _videos)
        if (v.publishedAt.isAfter(cutoff) && (!v.hasDetails || v.isUpcoming || v.isLive)) v.id,
    ];
    for (var i = 0; i < ids.length; i += 50) {
      final json = await _get('videos', {
        'part': 'snippet,contentDetails,liveStreamingDetails',
        'id': ids.skip(i).take(50).join(','),
        'maxResults': '50',
      });
      for (final raw in (json['items'] as List? ?? const [])) {
        final item = raw as Map<String, dynamic>;
        final video = _byId[item['id']];
        if (video == null) continue;
        final broadcast = item['snippet']?['liveBroadcastContent'] as String? ?? 'none';
        final live = item['liveStreamingDetails'] as Map<String, dynamic>?;
        final startedNotEnded = live != null && live['actualStartTime'] != null && live['actualEndTime'] == null;
        video
          ..duration = parseIsoDuration(item['contentDetails']?['duration'] as String? ?? '')
          ..isUpcoming = broadcast == 'upcoming'
          ..isLive = broadcast == 'live' || startedNotEnded
          ..hasDetails = true;
      }
      if (i % 500 == 0) notifyListeners();
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

  // ---- Disk cache ----

  Future<File> _cachePath() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_cacheFile');
  }

  Future<void> _loadCache() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final file = await _cachePath();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _channelIds = [for (final id in (json['channels'] as List? ?? const [])) id as String];
      _subscriptionsFetchedAt = DateTime.tryParse(json['subscriptionsFetchedAt'] as String? ?? '');
      _lastUpdated = DateTime.tryParse(json['updated'] as String? ?? '');
      for (final raw in (json['videos'] as List? ?? const [])) {
        final video = YouTubeVideo.fromJson(raw as Map<String, dynamic>);
        if (video != null) _byId[video.id] = video;
      }
      _publish();
    } catch (e) {
      appLogger.w('YouTube: could not read the cache', error: e);
    }
  }

  Future<void> _saveCache() async {
    try {
      final file = await _cachePath();
      await file.writeAsString(
        jsonEncode({
          'v': 1,
          'channels': _channelIds,
          'subscriptionsFetchedAt': _subscriptionsFetchedAt?.toIso8601String(),
          'updated': _lastUpdated?.toIso8601String(),
          'videos': [for (final v in _videos) v.toJson()],
        }),
      );
    } catch (e) {
      appLogger.w('YouTube: could not write the cache', error: e);
    }
  }

  Future<void> _deleteCache() async {
    try {
      final file = await _cachePath();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Parses an ISO 8601 duration such as PT1H2M3S.
Duration parseIsoDuration(String value) {
  final match = RegExp(r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(value);
  if (match == null) return Duration.zero;
  int part(int i) => int.tryParse(match.group(i) ?? '') ?? 0;
  return Duration(days: part(1), hours: part(2), minutes: part(3), seconds: part(4));
}
