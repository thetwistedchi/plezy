import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Bookmark {
  const Bookmark({required this.title, required this.url});

  final String title;
  final String url;

  String get host => Uri.tryParse(url)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? url;

  Map<String, String> toJson() => {'title': title, 'url': url};

  static Bookmark? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    final title = json['title'];
    return Bookmark(title: title is String && title.isNotEmpty ? title : url, url: url);
  }
}

/// The browser's bookmarks, in the user's order.
class BrowserBookmarks extends ChangeNotifier {
  BrowserBookmarks._();

  static final BrowserBookmarks instance = BrowserBookmarks._();

  static const _key = 'browser.bookmarks';
  SharedPreferences? _prefs;
  final List<Bookmark> _items = [];

  List<Bookmark> get items => List.unmodifiable(_items);

  Future<void> load() async {
    if (_prefs != null) return;
    final p = _prefs = await SharedPreferences.getInstance();
    try {
      final list = jsonDecode(p.getString(_key) ?? '[]');
      if (list is List) _items.addAll(list.map(Bookmark.fromJson).whereType<Bookmark>());
    } catch (_) {}
    notifyListeners();
  }

  static String _norm(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  bool contains(String? url) => url != null && _items.any((b) => _norm(b.url) == _norm(url));

  Future<void> add(Bookmark bookmark) async {
    if (contains(bookmark.url)) return;
    _items.add(bookmark);
    await _save();
  }

  /// Fork: imports the bookmarks of a browser's HTML export (Chrome,
  /// Firefox, Edge, Brave and Safari all write the Netscape bookmark format).
  /// Already known addresses are skipped. Returns how many were added.
  Future<int> importHtml(String html) async {
    final link = RegExp(r'<a\s[^>]*href\s*=\s*"([^"]+)"[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true);
    var added = 0;
    for (final m in link.allMatches(html)) {
      final url = _unescape(m.group(1)!.trim());
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) continue;
      if (contains(url)) continue;
      final title = _unescape(m.group(2)!.replaceAll(RegExp('<[^>]*>'), '').trim());
      _items.add(Bookmark(title: title.isEmpty ? url : title, url: url));
      added++;
    }
    if (added > 0) await _save();
    return added;
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  Future<void> remove(String url) async {
    _items.removeWhere((b) => _norm(b.url) == _norm(url));
    await _save();
  }

  Future<void> rename(String url, String title) async {
    final i = _items.indexWhere((b) => _norm(b.url) == _norm(url));
    if (i < 0) return;
    _items[i] = Bookmark(title: title.trim().isEmpty ? _items[i].url : title.trim(), url: _items[i].url);
    await _save();
  }

  Future<void> move(int from, int to) async {
    if (from < 0 || from >= _items.length) return;
    final item = _items.removeAt(from);
    _items.insert(to.clamp(0, _items.length), item);
    await _save();
  }

  Future<void> _save() async {
    await load();
    await _prefs!.setString(_key, jsonEncode(_items.map((b) => b.toJson()).toList()));
    notifyListeners();
  }
}
