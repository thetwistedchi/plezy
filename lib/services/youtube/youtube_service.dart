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
import 'youtube_channels.dart';
import 'youtube_extras.dart';
import 'youtube_settings.dart';
import 'youtube_notification_history.dart';

class YouTubeApiException implements Exception {
  YouTubeApiException(this.statusCode, this.message, {this.reason});

  final int statusCode;
  final String message;

  /// Google's machine-readable reason, e.g. commentsDisabled.
  final String? reason;

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
    this.description,
    this.categoryId,
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

  /// From the RSS feed; kept in memory only (for chapters without the API).
  String? description;

  /// YouTube's category id (e.g. `10` Music), from the API details.
  String? categoryId;

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
    'cat': ?categoryId,
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
      categoryId: json['cat'] as String?,
    );
  }
}

enum YouTubeSort { newest, relevant }

enum YouTubeFilter { all, unwatched, continueWatching }

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
  int _totalChannels = 0;
  Object? _error;
  DateTime? _lastUpdated;
  Timer? _timer;
  Future<void>? _inFlight;

  List<YouTubeVideo> get videos => _videos;
  bool get isLoading => _loading;
  Object? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  /// Feed progress while loading, 0..1, or null when not loading.
  double? get progress => _loading && _totalChannels > 0 ? _channelsDone / _totalChannels : null;
  int get channelsDone => _channelsDone;
  int get channelCount => _totalChannels;

  /// Whether there is anything to load: a Google sign-in or channels added
  /// in the app.
  static bool get isAvailable => YouTubeSettings.instance.isSignedIn || !YouTubeChannels.instance.isEmpty;

  /// Shows the cached feed, starts the periodic refresh and refreshes once
  /// when the cache is stale.
  void ensureStarted() {
    final settings = YouTubeSettings.instance;
    _timer?.cancel();
    if (!isAvailable) return;
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
      final signedIn = YouTubeSettings.instance.isSignedIn;
      await YouTubeChannels.instance.load();
      if (signedIn) {
        final subsAge = _subscriptionsFetchedAt == null
            ? null
            : DateTime.now().difference(_subscriptionsFetchedAt!);
        if (reloadSubscriptions || _channelIds.isEmpty || subsAge == null || subsAge > _subscriptionsMaxAge) {
          _channelIds = await _subscriptions();
          _subscriptionsFetchedAt = DateTime.now();
        }
      } else {
        _channelIds = const [];
      }
      final allChannels = {..._channelIds, ...YouTubeChannels.instance.ids};
      _byId.removeWhere((_, v) => !allChannels.contains(v.channelId));
      _totalChannels = allChannels.length;

      final previousUpdate = _lastUpdated;
      final knownIds = _byId.keys.toSet();
      final queue = [...allChannels];
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
                ..isShort = video.isShort
                ..description = video.description;
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
      if (previousUpdate != null) {
        final settings = YouTubeSettings.instance;
        final fresh = [
          for (final v in _videos)
            if (!knownIds.contains(v.id) &&
                settings.isFavorite(v.channelId) &&
                v.publishedAt.isAfter(previousUpdate.subtract(const Duration(hours: 1))) &&
                (settings.showShorts || !v.isShort))
              v,
        ];
        unawaited(YouTubeNotificationHistory.instance.add(fresh));
        unawaited(YouTubeNotifier.notifyNew(fresh));
      }
      if (signedIn) await _fetchDetails();
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

  /// Videos to show, after the Shorts / premiere / hidden filters and the sort.
  List<YouTubeVideo> visibleVideos({required YouTubeSort sort, YouTubeFilter filter = YouTubeFilter.all}) {
    final settings = YouTubeSettings.instance;
    final list = _videos.where((v) {
      if (!settings.showShorts && v.isShort) return false;
      if (!settings.showPremieres && (v.isUpcoming || v.isLive)) return false;
      // Fork: minimum length (videos without a known length stay).
      if (settings.minMinutes > 0 &&
          v.duration > Duration.zero &&
          v.duration < Duration(minutes: settings.minMinutes)) {
        return false;
      }
      if (settings.isHidden(v.id) || settings.isMuted(v.channelId)) return false;
      switch (filter) {
        case YouTubeFilter.all:
          return true;
        case YouTubeFilter.unwatched:
          return !settings.isWatched(v.id);
        case YouTubeFilter.continueWatching:
          final p = settings.progressFraction(v.id);
          return p != null && p > 0 && p < 0.95;
      }
    }).toList();
    if (filter == YouTubeFilter.continueWatching) return list;
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
          description: group?.getElement('media:description')?.innerText,
        ),
      );
    }
    return videos;
  }

  /// The latest uploads of one channel from its feed (no quota), with the
  /// cached details where known.
  Future<List<YouTubeVideo>> channelFeed(String channelId) async {
    final videos = await _feed(channelId);
    for (final v in videos) {
      final known = _byId[v.id];
      if (known != null && known.hasDetails) {
        v
          ..duration = known.duration
          ..isUpcoming = known.isUpcoming
          ..isLive = known.isLive
          ..hasDetails = true;
      }
    }
    videos.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return videos;
  }

  /// Caption tracks, storyboard spec, views and upload date from the public
  /// watch page (no quota, no account). The embedded player doesn't expose
  /// these reliably.
  Future<YtWatchInfo?> watchPageInfo(String videoId) async {
    try {
      final response = await _client
          .get(
            Uri.https('www.youtube.com', '/watch', {'v': videoId, 'hl': 'en'}),
            headers: {'Cookie': 'SOCS=CAI; CONSENT=YES+cb', 'Accept-Language': 'en'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final json = _extractJsonObject(response.body, 'ytInitialPlayerResponse');
      if (json == null) return null;
      final captions = json['captions']?['playerCaptionsTracklistRenderer'] as Map<String, dynamic>?;
      String text(Object? node) {
        if (node is Map) {
          if (node['simpleText'] is String) return node['simpleText'] as String;
          final runs = node['runs'];
          if (runs is List) return runs.map((r) => r is Map ? (r['text'] ?? '') : '').join();
        }
        return '';
      }

      final tracks = <({String code, String name, String kind})>[
        for (final t in (captions?['captionTracks'] as List? ?? const []))
          if (t is Map)
            (
              code: t['languageCode'] as String? ?? '',
              name: text(t['name']).isEmpty ? (t['languageCode'] as String? ?? '') : text(t['name']),
              kind: t['kind'] as String? ?? '',
            ),
      ];
      final translations = <({String code, String name})>[
        for (final l in (captions?['translationLanguages'] as List? ?? const []))
          if (l is Map) (code: l['languageCode'] as String? ?? '', name: text(l['languageName'])),
      ];
      final details = json['videoDetails'] as Map<String, dynamic>? ?? const {};
      final micro = json['microformat']?['playerMicroformatRenderer'] as Map<String, dynamic>? ?? const {};
      return YtWatchInfo(
        captionTracks: tracks,
        translationLanguages: translations,
        storyboardSpec: json['storyboards']?['playerStoryboardSpecRenderer']?['spec'] as String?,
        viewCount: int.tryParse(details['viewCount']?.toString() ?? ''),
        publishDate: DateTime.tryParse(micro['publishDate'] as String? ?? ''),
        description: details['shortDescription'] as String?,
      );
    } catch (e) {
      appLogger.d('YouTube watch page failed for $videoId: $e');
      return null;
    }
  }

  /// First video of a public YouTube search (no quota, no account). Prefers
  /// a result whose title contains [preferWord]. Used for movie trailers.
  Future<YouTubeVideo?> searchFirstVideo(String query, {String? preferWord}) async {
    final results = await search(query, limit: 8);
    if (results.isEmpty) return null;
    final word = preferWord?.toLowerCase();
    if (word == null) return results.first;
    return results.firstWhere((v) => v.title.toLowerCase().contains(word), orElse: () => results.first);
  }

  /// Fork: a public YouTube search (no quota, no account), parsed from the
  /// results page. Returns up to [limit] videos; channels, playlists and
  /// Shorts shelves are skipped.
  Future<List<YouTubeVideo>> search(String query, {int limit = 40}) async {
    try {
      final response = await _client
          .get(
            Uri.https('www.youtube.com', '/results', {'search_query': query, 'hl': 'en'}),
            headers: {'Cookie': 'SOCS=CAI; CONSENT=YES+cb', 'Accept-Language': 'en'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];
      final data = _extractJsonObject(response.body, 'var ytInitialData');
      if (data == null) return const [];
      final renderers = <Map<String, dynamic>>[];
      final seen = <String>{};
      void walk(Object? node) {
        if (renderers.length >= limit) return;
        if (node is Map) {
          final video = node['videoRenderer'];
          if (video is Map<String, dynamic> && video['videoId'] is String) {
            if (seen.add(video['videoId'] as String)) renderers.add(video);
            return;
          }
          for (final value in node.values) {
            walk(value);
          }
        } else if (node is List) {
          for (final value in node) {
            walk(value);
          }
        }
      }

      walk(data);
      return [for (final r in renderers) _videoFromRenderer(r)];
    } catch (e) {
      appLogger.d('YouTube search failed for "$query"', error: e);
      return const [];
    }
  }

  static String _rendererText(Object? node) {
    if (node is Map) {
      if (node['simpleText'] is String) return node['simpleText'] as String;
      final runs = node['runs'];
      if (runs is List) return runs.map((r) => r is Map ? (r['text'] ?? '') : '').join();
    }
    return '';
  }

  /// "3 days ago" (English, as requested with hl=en) to a date.
  static DateTime _fromRelative(String text) {
    final now = DateTime.now();
    final m = RegExp(r'(\d+)\s+(second|minute|hour|day|week|month|year)').firstMatch(text);
    if (m == null) return now;
    final n = int.parse(m.group(1)!);
    return switch (m.group(2)) {
      'second' => now.subtract(Duration(seconds: n)),
      'minute' => now.subtract(Duration(minutes: n)),
      'hour' => now.subtract(Duration(hours: n)),
      'day' => now.subtract(Duration(days: n)),
      'week' => now.subtract(Duration(days: 7 * n)),
      'month' => now.subtract(Duration(days: 30 * n)),
      _ => now.subtract(Duration(days: 365 * n)),
    };
  }

  static YouTubeVideo _videoFromRenderer(Map<String, dynamic> r) {
    final ownerText = r['ownerText'] ?? r['longBylineText'];
    final ownerRuns = ownerText is Map ? ownerText['runs'] : null;
    final Object? owner = ownerRuns is List && ownerRuns.isNotEmpty ? ownerRuns.first : null;
    String? channelId;
    if (owner is Map) {
      final endpoint = owner['navigationEndpoint'];
      final browse = endpoint is Map ? endpoint['browseEndpoint'] : null;
      final browseId = browse is Map ? browse['browseId'] : null;
      if (browseId is String) channelId = browseId;
    }
    Duration length = Duration.zero;
    final lengthText = _rendererText(r['lengthText']);
    final parts = lengthText.split(':').map(int.tryParse).toList();
    if (lengthText.isNotEmpty && parts.every((p) => p != null)) {
      var seconds = 0;
      for (final p in parts) {
        seconds = seconds * 60 + p!;
      }
      length = Duration(seconds: seconds);
    }
    final viewsText = _rendererText(r['viewCountText']);
    final views = int.tryParse(viewsText.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final upcoming = r['upcomingEventData'] != null;
    final live = !upcoming && lengthText.isEmpty && viewsText.contains('watching');
    final id = r['videoId'] as String;
    return YouTubeVideo(
      id: id,
      title: _rendererText(r['title']),
      channelId: channelId ?? '',
      channelTitle: owner is Map && owner['text'] is String ? owner['text'] as String : '',
      thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      publishedAt: _fromRelative(_rendererText(r['publishedTimeText'])),
      viewCount: views,
      isShort: false,
      duration: length,
      isUpcoming: upcoming,
      isLive: live,
      hasDetails: length > Duration.zero || upcoming || live,
    );
  }

  /// Finds `name = {...}` in a page and decodes the object by matching braces.
  static Map<String, dynamic>? _extractJsonObject(String html, String name) {
    final marker = html.indexOf(name);
    if (marker < 0) return null;
    final start = html.indexOf('{', marker);
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < html.length; i++) {
      final c = html.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == 0x5C) {
          escaped = true;
        } else if (c == 0x22) {
          inString = false;
        }
        continue;
      }
      if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        depth--;
        if (depth == 0) {
          return jsonDecode(html.substring(start, i + 1)) as Map<String, dynamic>;
        }
      }
    }
    return null;
  }

  // ---- API ----

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) => _request('GET', path, query);

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    Map<String, String> query, {
    Object? body,
    bool retried = false,
  }) async {
    final token = await YouTubeAuth.instance.accessToken();
    final request = http.Request(method, Uri.https('www.googleapis.com', '/youtube/v3/$path', query))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await _client.send(request));
    if (response.statusCode == 401 && !retried) {
      YouTubeAuth.instance.invalidateAccessToken();
      return _request(method, path, query, body: body, retried: true);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final (message, reason) = _apiError(response.body);
      throw YouTubeApiException(response.statusCode, message, reason: reason);
    }
    if (response.body.isEmpty) return const {};
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
        if (v.publishedAt.isAfter(cutoff) && (!v.hasDetails || v.categoryId == null || v.isUpcoming || v.isLive)) v.id,
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
          ..categoryId = item['snippet']?['categoryId'] as String? ?? video.categoryId
          ..hasDetails = true;
      }
      if (i % 500 == 0) notifyListeners();
    }
  }

  /// Name and channel ID of the signed-in account, for the settings screen
  /// and for recognising the user's own comments.
  Future<({String? name, String? channelId})> fetchAccount() async {
    final json = await _get('channels', {'part': 'snippet', 'mine': 'true'});
    final items = json['items'] as List? ?? const [];
    if (items.isEmpty) return (name: null, channelId: null);
    final item = items.first as Map;
    return (name: item['snippet']?['title'] as String?, channelId: item['id'] as String?);
  }

  /// Title, description and counts of one video.
  Future<YtVideoInfo?> videoInfo(String videoId) async {
    final json = await _get('videos', {'part': 'snippet,statistics', 'id': videoId});
    final items = json['items'] as List? ?? const [];
    if (items.isEmpty) return null;
    final item = items.first as Map<String, dynamic>;
    final snippet = item['snippet'] as Map<String, dynamic>? ?? const {};
    final stats = item['statistics'] as Map<String, dynamic>? ?? const {};
    return YtVideoInfo(
      title: snippet['title'] as String? ?? '',
      channelTitle: snippet['channelTitle'] as String? ?? '',
      description: snippet['description'] as String? ?? '',
      likeCount: int.tryParse(stats['likeCount']?.toString() ?? ''),
      commentCount: int.tryParse(stats['commentCount']?.toString() ?? ''),
    );
  }

  /// Name, avatar, banner and counts of a channel (1 unit).
  Future<YtChannelInfo?> channelInfo(String channelId) async {
    final json = await _get('channels', {'part': 'snippet,statistics,brandingSettings', 'id': channelId});
    final items = json['items'] as List? ?? const [];
    if (items.isEmpty) return null;
    final item = items.first as Map<String, dynamic>;
    final snippet = item['snippet'] as Map<String, dynamic>? ?? const {};
    final stats = item['statistics'] as Map<String, dynamic>? ?? const {};
    final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? const {};
    final avatar = (thumbs['high'] ?? thumbs['medium'] ?? thumbs['default']) as Map?;
    final banner = item['brandingSettings']?['image']?['bannerExternalUrl'] as String?;
    return YtChannelInfo(
      id: channelId,
      title: snippet['title'] as String? ?? '',
      handle: snippet['customUrl'] as String?,
      description: snippet['description'] as String? ?? '',
      avatarUrl: avatar?['url'] as String?,
      bannerUrl: banner == null ? null : '$banner=w1920',
      subscriberCount: stats['hiddenSubscriberCount'] == true
          ? null
          : int.tryParse(stats['subscriberCount']?.toString() ?? ''),
      videoCount: int.tryParse(stats['videoCount']?.toString() ?? ''),
    );
  }

  /// Fork: a channel's public playlists (signed in; Data API).
  Future<List<({String id, String title, int count, String? thumbnail})>> channelPlaylists(String channelId) async {
    final page = await _get('playlists', {
      'part': 'snippet,contentDetails',
      'channelId': channelId,
      'maxResults': '50',
    });
    return [
      for (final raw in (page['items'] as List? ?? const []))
        if (raw is Map && raw['id'] is String)
          (
            id: raw['id'] as String,
            title: (raw['snippet']?['title'] as String?) ?? '',
            count: (raw['contentDetails']?['itemCount'] as num?)?.toInt() ?? 0,
            thumbnail: raw['snippet']?['thumbnails']?['medium']?['url'] as String?,
          ),
    ];
  }

  /// Fork: the signed-in account's own playlists (not Watch later, which the
  /// API no longer hands out).
  Future<List<({String id, String title, int count, String? thumbnail})>> myPlaylists() async {
    final result = <({String id, String title, int count, String? thumbnail})>[];
    String? token;
    do {
      final page = await _get('playlists', {
        'part': 'snippet,contentDetails',
        'mine': 'true',
        'maxResults': '50',
        'pageToken': ?token,
      });
      for (final raw in (page['items'] as List? ?? const [])) {
        if (raw is Map && raw['id'] is String) {
          result.add((
            id: raw['id'] as String,
            title: (raw['snippet']?['title'] as String?) ?? '',
            count: (raw['contentDetails']?['itemCount'] as num?)?.toInt() ?? 0,
            thumbnail: raw['snippet']?['thumbnails']?['medium']?['url'] as String?,
          ));
        }
      }
      token = page['nextPageToken'] as String?;
    } while (token != null && result.length < 500);
    return result;
  }

  /// Fork: the videos of a playlist in its order (up to [limit]).
  Future<List<YouTubeVideo>> playlistVideos(String playlistId, {int limit = 200}) async {
    final videos = <YouTubeVideo>[];
    String? token;
    do {
      final page = await channelUploads('', playlistId: playlistId, pageToken: token);
      videos.addAll(page.items);
      token = page.nextPageToken;
    } while (token != null && videos.length < limit);
    return videos;
  }

  /// One page (50) of a channel's uploads, newest first, with details
  /// (2 units). Fork: [playlistId] reads another playlist the same way.
  Future<({List<YouTubeVideo> items, String? nextPageToken})> channelUploads(
    String channelId, {
    String? pageToken,
    String? playlistId,
  }) async {
    if (playlistId == null && !channelId.startsWith('UC')) {
      return (items: const <YouTubeVideo>[], nextPageToken: null);
    }
    final page = await _get('playlistItems', {
      'part': 'contentDetails',
      'playlistId': playlistId ?? 'UU${channelId.substring(2)}',
      'maxResults': '50',
      'pageToken': ?pageToken,
    });
    final ids = [
      for (final item in (page['items'] as List? ?? const []))
        if ((item as Map)['contentDetails']?['videoId'] case final String id) id,
    ];
    if (ids.isEmpty) return (items: const <YouTubeVideo>[], nextPageToken: null);
    final json = await _get('videos', {
      'part': 'snippet,contentDetails,statistics,liveStreamingDetails',
      'id': ids.join(','),
      'maxResults': '50',
    });
    final byId = <String, YouTubeVideo>{};
    for (final raw in (json['items'] as List? ?? const [])) {
      final item = raw as Map<String, dynamic>;
      final id = item['id'] as String?;
      final snippet = item['snippet'] as Map<String, dynamic>?;
      if (id == null || snippet == null) continue;
      final broadcast = snippet['liveBroadcastContent'] as String? ?? 'none';
      final duration = parseIsoDuration(item['contentDetails']?['duration'] as String? ?? '');
      final known = _byId[id];
      byId[id] = YouTubeVideo(
        id: id,
        title: snippet['title'] as String? ?? '',
        channelId: playlistId == null ? channelId : (snippet['channelId'] as String? ?? channelId),
        channelTitle: snippet['channelTitle'] as String? ?? '',
        thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        publishedAt: DateTime.tryParse(snippet['publishedAt'] as String? ?? '') ?? DateTime.now(),
        viewCount: int.tryParse(item['statistics']?['viewCount']?.toString() ?? '') ?? 0,
        isShort: known?.isShort ?? (duration > Duration.zero && duration <= const Duration(seconds: 60)),
        duration: duration,
        isUpcoming: broadcast == 'upcoming',
        isLive: broadcast == 'live',
        hasDetails: true,
      );
    }
    return (
      items: [for (final id in ids) ?byId[id]],
      nextPageToken: page['nextPageToken'] as String?,
    );
  }

  /// 'like', 'dislike' or 'none'.
  Future<String> myRating(String videoId) async {
    final json = await _get('videos/getRating', {'id': videoId});
    final items = json['items'] as List? ?? const [];
    if (items.isEmpty) return 'none';
    return (items.first as Map)['rating'] as String? ?? 'none';
  }

  Future<void> rate(String videoId, String rating) => _request('POST', 'videos/rate', {'id': videoId, 'rating': rating});

  Future<({List<YtComment> items, String? nextPageToken})> commentThreads(
    String videoId, {
    required bool newest,
    String? pageToken,
  }) async {
    final json = await _get('commentThreads', {
      'part': 'snippet',
      'videoId': videoId,
      'order': newest ? 'time' : 'relevance',
      'maxResults': '20',
      'textFormat': 'plainText',
      'pageToken': ?pageToken,
    });
    final items = <YtComment>[];
    for (final raw in (json['items'] as List? ?? const [])) {
      final thread = raw as Map<String, dynamic>;
      final snippet = thread['snippet'] as Map<String, dynamic>? ?? const {};
      final top = snippet['topLevelComment'] as Map<String, dynamic>?;
      if (top == null) continue;
      items.add(
        YtComment.fromJson(
          top,
          replyCount: (snippet['totalReplyCount'] as num?)?.toInt() ?? 0,
          canReply: snippet['canReply'] as bool? ?? false,
        ),
      );
    }
    return (items: items, nextPageToken: json['nextPageToken'] as String?);
  }

  Future<List<YtComment>> replies(String parentId) async {
    final result = <YtComment>[];
    String? pageToken;
    do {
      final json = await _get('comments', {
        'part': 'snippet',
        'parentId': parentId,
        'maxResults': '100',
        'textFormat': 'plainText',
        'pageToken': ?pageToken,
      });
      for (final raw in (json['items'] as List? ?? const [])) {
        result.add(YtComment.fromJson(raw as Map<String, dynamic>));
      }
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null && result.length < 500);
    return result;
  }

  Future<YtComment> addComment(String videoId, String text) async {
    final json = await _request(
      'POST',
      'commentThreads',
      {'part': 'snippet'},
      body: {
        'snippet': {
          'videoId': videoId,
          'topLevelComment': {
            'snippet': {'textOriginal': text},
          },
        },
      },
    );
    final top = json['snippet']?['topLevelComment'] as Map<String, dynamic>;
    return YtComment.fromJson(top, canReply: true);
  }

  Future<YtComment> addReply(String parentId, String text) async {
    final json = await _request(
      'POST',
      'comments',
      {'part': 'snippet'},
      body: {
        'snippet': {'parentId': parentId, 'textOriginal': text},
      },
    );
    return YtComment.fromJson(json);
  }

  Future<YtComment> editComment(String commentId, String text) async {
    final json = await _request(
      'PUT',
      'comments',
      {'part': 'snippet'},
      body: {
        'id': commentId,
        'snippet': {'textOriginal': text},
      },
    );
    return YtComment.fromJson(json);
  }

  Future<void> deleteComment(String commentId) => _request('DELETE', 'comments', {'id': commentId});

  static (String, String?) _apiError(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      final errors = error?['errors'] as List?;
      final reason = errors == null || errors.isEmpty ? null : (errors.first as Map)['reason'] as String?;
      return ((error?['message'] ?? body).toString(), reason);
    } catch (_) {
      return (body, null);
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

class YtVideoInfo {
  YtVideoInfo({
    required this.title,
    required this.channelTitle,
    required this.description,
    required this.likeCount,
    required this.commentCount,
  });

  final String title;
  final String channelTitle;
  final String description;

  /// Null when the creator hides the count.
  final int? likeCount;

  /// Null when comments are turned off.
  final int? commentCount;
}

class YtComment {
  YtComment({
    required this.id,
    required this.author,
    required this.authorChannelId,
    required this.avatarUrl,
    required this.text,
    required this.likeCount,
    required this.publishedAt,
    required this.edited,
    this.replyCount = 0,
    this.canReply = false,
  });

  factory YtComment.fromJson(Map<String, dynamic> json, {int replyCount = 0, bool canReply = false}) {
    final s = json['snippet'] as Map<String, dynamic>? ?? const {};
    final published = DateTime.tryParse(s['publishedAt'] as String? ?? '') ?? DateTime.now();
    final updated = DateTime.tryParse(s['updatedAt'] as String? ?? '');
    return YtComment(
      id: json['id'] as String? ?? '',
      author: s['authorDisplayName'] as String? ?? '',
      authorChannelId: s['authorChannelId']?['value'] as String? ?? '',
      avatarUrl: s['authorProfileImageUrl'] as String?,
      text: (s['textOriginal'] ?? s['textDisplay'] ?? '') as String,
      likeCount: (s['likeCount'] as num?)?.toInt() ?? 0,
      publishedAt: published,
      edited: updated != null && updated.difference(published).inSeconds.abs() > 5,
      replyCount: replyCount,
      canReply: canReply,
    );
  }

  final String id;
  final String author;
  final String authorChannelId;
  final String? avatarUrl;
  String text;
  final int likeCount;
  final DateTime publishedAt;
  bool edited;
  int replyCount;
  final bool canReply;
}

class YtChannelInfo {
  YtChannelInfo({
    required this.id,
    required this.title,
    required this.handle,
    required this.description,
    required this.avatarUrl,
    required this.bannerUrl,
    required this.subscriberCount,
    required this.videoCount,
  });

  final String id;
  final String title;
  final String? handle;
  final String description;
  final String? avatarUrl;
  final String? bannerUrl;
  final int? subscriberCount;
  final int? videoCount;

  Uri get url => Uri.https('www.youtube.com', '/channel/$id');
}

class YtWatchInfo {
  YtWatchInfo({
    required this.captionTracks,
    required this.translationLanguages,
    required this.storyboardSpec,
    required this.viewCount,
    required this.publishDate,
    required this.description,
  });

  final List<({String code, String name, String kind})> captionTracks;
  final List<({String code, String name})> translationLanguages;
  final String? storyboardSpec;
  final int? viewCount;
  final DateTime? publishDate;
  final String? description;
}
