import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A channel followed in the app itself, without a Google account.
class LocalChannel {
  LocalChannel(this.id, this.title);

  final String id;
  final String title;

  Map<String, String> toJson() => {'id': id, 'title': title};
}

/// Channels followed in the app without signing in to Google: added by URL
/// or @handle, or imported from a Google Takeout subscriptions.csv. Their
/// uploads come from the public RSS feeds, so nothing here needs an account.
class YouTubeChannels extends ChangeNotifier {
  YouTubeChannels._();

  static final YouTubeChannels instance = YouTubeChannels._();

  static const _kKey = 'youtube_local_channels';
  static final RegExp _channelId = RegExp(r'UC[\w-]{22}');

  /// Skips YouTube's EU cookie consent page for the one request that reads
  /// a channel page.
  static const _consentCookie = 'SOCS=CAI; CONSENT=YES+cb';

  final http.Client _client = http.Client();
  SharedPreferences? _prefs;
  Future<void>? _loading;
  List<LocalChannel> _channels = [];

  bool get isLoaded => _prefs != null;
  List<LocalChannel> get channels => List.unmodifiable(_channels);
  List<String> get ids => [for (final c in _channels) c.id];
  bool get isEmpty => _channels.isEmpty;
  bool contains(String id) => _channels.any((c) => c.id == id);

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_kKey);
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      _channels = [
        for (final e in list)
          if (e is Map && e['id'] is String) LocalChannel(e['id'] as String, e['title'] as String? ?? ''),
      ];
    } catch (_) {
      _channels = [];
    }
    _prefs = prefs;
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs!.setString(_kKey, jsonEncode([for (final c in _channels) c.toJson()]));
    notifyListeners();
  }

  Future<bool> add(LocalChannel channel) async {
    await load();
    if (contains(channel.id)) return false;
    _channels.add(channel);
    _channels.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    await _save();
    return true;
  }

  Future<void> remove(String id) async {
    await load();
    _channels.removeWhere((c) => c.id == id);
    await _save();
  }

  Future<void> clear() async {
    await load();
    _channels.clear();
    await _save();
  }

  /// Imports Google Takeout's subscriptions.csv
  /// ("Channel Id,Channel Url,Channel Title"). Returns how many were new.
  Future<int> importTakeoutCsv(String csv) async {
    await load();
    var added = 0;
    for (final line in const LineSplitter().convert(csv)) {
      final id = _channelId.firstMatch(line)?.group(0);
      if (id == null || contains(id)) continue;
      final cells = _splitCsvLine(line);
      final title = cells.length >= 3 ? cells.sublist(2).join(',').trim() : id;
      _channels.add(LocalChannel(id, title.isEmpty ? id : title));
      added++;
    }
    _channels.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    await _save();
    return added;
  }

  static List<String> _splitCsvLine(String line) {
    final cells = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == ',' && !quoted) {
        cells.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    cells.add(buffer.toString());
    return cells;
  }

  /// Finds the channel behind a channel URL, a video URL, an @handle or a
  /// channel ID. Null when it can't be found.
  Future<LocalChannel?> resolve(String input) async {
    var text = input.trim();
    if (text.isEmpty) return null;
    final directId = RegExp(r'^UC[\w-]{22}$').hasMatch(text) ? text : null;

    Uri page;
    if (directId != null) {
      page = Uri.https('www.youtube.com', '/channel/$directId');
    } else if (text.startsWith('@')) {
      page = Uri.https('www.youtube.com', '/$text');
    } else {
      if (!text.contains('://')) text = 'https://$text';
      final uri = Uri.tryParse(text);
      if (uri == null || !uri.host.contains('youtu')) return null;
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        page = Uri.https('www.youtube.com', '/watch', {'v': uri.pathSegments.first});
      } else {
        page = Uri.https('www.youtube.com', uri.path, uri.queryParameters.isEmpty ? null : uri.queryParameters);
      }
    }

    final response = await _client
        .get(page, headers: {'Cookie': _consentCookie, 'Accept-Language': 'en'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final html = response.body;

    String? id = directId;
    if (page.path == '/watch') {
      id ??= RegExp(r'"channelId":"(UC[\w-]{22})"').firstMatch(html)?.group(1);
    }
    id ??= RegExp(r'<meta itemprop="identifier" content="(UC[\w-]{22})"').firstMatch(html)?.group(1);
    id ??= RegExp(r'"externalId":"(UC[\w-]{22})"').firstMatch(html)?.group(1);
    id ??= RegExp(r'"browseId":"(UC[\w-]{22})"').firstMatch(html)?.group(1);
    if (id == null) return null;

    var title = RegExp(r'<meta property="og:title" content="([^"]*)"').firstMatch(html)?.group(1) ?? '';
    if (page.path == '/watch') {
      title = RegExp(r'"ownerChannelName":"([^"]*)"').firstMatch(html)?.group(1) ?? title;
    }
    return LocalChannel(id, _unescape(title).isEmpty ? id : _unescape(title));
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
