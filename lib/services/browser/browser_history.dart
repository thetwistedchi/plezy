import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_settings.dart';

class VisitedPage {
  const VisitedPage({required this.url, required this.title});

  final String url;
  final String title;

  String get host => Uri.tryParse(url)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? url;

  Map<String, String> toJson() => {'url': url, 'title': title};
}

/// The most recently visited pages, newest first, one entry per address.
class BrowserHistory extends ChangeNotifier {
  BrowserHistory._();

  static final BrowserHistory instance = BrowserHistory._();

  static const _key = 'browser.history';
  static const maxEntries = 50;

  SharedPreferences? _prefs;
  final List<VisitedPage> _items = [];
  Timer? _saveTimer;

  List<VisitedPage> recent(int count) => _items.take(count).toList();

  Future<void> load() async {
    if (_prefs != null) return;
    final p = _prefs = await SharedPreferences.getInstance();
    await BrowserSettings.instance.load();
    if (!BrowserSettings.instance.keepHistory) {
      await p.remove(_key);
      return;
    }
    try {
      final list = jsonDecode(p.getString(_key) ?? '[]');
      if (list is List) {
        for (final e in list) {
          if (e is Map && e['url'] is String) {
            _items.add(VisitedPage(url: e['url'] as String, title: e['title'] is String ? e['title'] as String : ''));
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  static String _norm(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// Moves [url] to the top, or updates its title when it is already there.
  void visit(String url, String title) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;
    final i = _items.indexWhere((p) => _norm(p.url) == _norm(url));
    if (i == 0) {
      if (title.isEmpty || _items[0].title == title) return;
      _items[0] = VisitedPage(url: url, title: title);
    } else {
      final old = i > 0 ? _items.removeAt(i) : null;
      _items.insert(0, VisitedPage(url: url, title: title.isNotEmpty ? title : (old?.title ?? '')));
      if (_items.length > maxEntries) _items.removeRange(maxEntries, _items.length);
    }
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () => unawaited(_save()));
  }

  Future<void> remove(String url) async {
    _items.removeWhere((p) => _norm(p.url) == _norm(url));
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    await _save();
  }

  /// Saves the list, or removes the saved one when it is not to be kept.
  Future<void> _save() async {
    await load();
    if (!BrowserSettings.instance.keepHistory) {
      await _prefs!.remove(_key);
      return;
    }
    await _prefs!.setString(_key, jsonEncode(_items.map((p) => p.toJson()).toList()));
  }

  /// Applies a changed "keep history" setting to the saved list.
  Future<void> persistChanged() => _save();
}
