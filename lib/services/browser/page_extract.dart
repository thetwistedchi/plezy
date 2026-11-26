import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fork: reads a web page on the Dart side for the reader view and for
/// "Play video in the app's player". Works without the page's own scripts,
/// so pages that only build their content in JavaScript yield little.
class PageExtract {
  PageExtract._();

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';

  static Future<String> fetchHtml(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: {'User-Agent': _userAgent, 'Accept': 'text/html,*/*'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode >= 400) throw Exception('HTTP ${response.statusCode}');
    // Without a charset in the header package:http falls back to Latin-1;
    // most pages without one are UTF-8.
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.toLowerCase().contains('charset=')) return response.body;
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  static const _mediaExtensions = ['.mp4', '.m4v', '.webm', '.mkv', '.mov', '.m3u8', '.mpd', '.mp3', '.m4a', '.ogg'];

  /// Whether [url] itself points at a media file or stream.
  static bool isMediaUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return _mediaExtensions.any(path.endsWith);
  }

  /// The video id of a YouTube watch, short, live, embed or youtu.be address.
  static String? youTubeVideoId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.|music\.)'), '');
    final segments = uri.pathSegments;
    String? id;
    if (host == 'youtu.be') {
      id = segments.firstOrNull;
    } else if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
      if (segments.firstOrNull == 'watch') {
        id = uri.queryParameters['v'];
      } else if (segments.length >= 2 && const {'embed', 'shorts', 'live', 'v'}.contains(segments.first)) {
        id = segments[1];
      }
    }
    return id != null && RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
  }

  /// Video addresses the page names: Open Graph / Twitter player tags,
  /// `<video>` and `<source>` elements, and direct media links in the markup.
  static List<String> findVideoUrls(String html, String pageUrl) {
    final base = Uri.parse(pageUrl);
    final found = <String>{};
    void add(String? raw) {
      if (raw == null || raw.isEmpty) return;
      final cleaned = _decode(raw.trim()).replaceAll(r'\/', '/');
      final uri = base.resolve(cleaned);
      if (uri.isScheme('http') || uri.isScheme('https')) found.add(uri.toString());
    }

    final meta = RegExp(
      r'''<meta[^>]+(?:property|name)=["'](?:og:video(?::secure_url|:url)?|twitter:player:stream)["'][^>]*content=["']([^"']+)''',
      caseSensitive: false,
    );
    for (final m in meta.allMatches(html)) {
      add(m.group(1));
    }
    final tags = RegExp(r'''<(?:video|source)[^>]+src=["']([^"']+)''', caseSensitive: false);
    for (final m in tags.allMatches(html)) {
      add(m.group(1));
    }
    final direct = RegExp(r'''https?:\\?/\\?/[^"'\s<>]+?\.(?:m3u8|mp4|webm|mpd)(?:\?[^"'\s<>]*)?''', caseSensitive: false);
    for (final m in direct.allMatches(html)) {
      add(m.group(0));
    }
    // Streams first: they usually carry every quality.
    final list = found.toList()..sort((a, b) => _rank(a).compareTo(_rank(b)));
    return list;
  }

  static int _rank(String url) {
    final path = url.toLowerCase();
    if (path.contains('.m3u8')) return 0;
    if (path.contains('.mpd')) return 1;
    if (path.contains('.mp4')) return 2;
    return 3;
  }

  /// The readable part of an article: title and text blocks in order.
  static ({String title, List<({String kind, String text})> blocks}) extractArticle(String html) {
    final title = _text(RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(html)?.group(1) ?? '');
    var body = html
        .replaceAll(RegExp(r'<(script|style|noscript|svg|nav|header|footer|aside|form|iframe)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), ' ')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');
    final article = RegExp(r'<(article|main)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true)
        .allMatches(body)
        .map((m) => m.group(2)!)
        .fold<String>('', (best, s) => s.length > best.length ? s : best);
    if (article.length > 500) body = article;
    final blocks = <({String kind, String text})>[];
    final block = RegExp(r'<(h1|h2|h3|p|li|blockquote|pre)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true);
    for (final m in block.allMatches(body)) {
      final kind = m.group(1)!.toLowerCase();
      final text = _text(m.group(2)!);
      if (text.isEmpty) continue;
      final heading = kind.startsWith('h');
      if (!heading && kind != 'pre' && text.length < (kind == 'li' ? 20 : 40)) continue;
      if (blocks.isNotEmpty && blocks.last.text == text) continue;
      blocks.add((kind: kind, text: text));
    }
    var heading = blocks.where((b) => b.kind == 'h1').map((b) => b.text).firstOrNull ?? title;
    if (heading.isEmpty) heading = title;
    return (title: heading, blocks: blocks.where((b) => !(b.kind == 'h1' && b.text == heading)).toList());
  }

  static String _text(String html) =>
      _decode(html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n').replaceAll(RegExp(r'<[^>]+>'), ''))
          .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
          .replaceAll(RegExp(r' *\n *'), '\n')
          .trim();

  static String _decode(String s) => s
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => _char(int.tryParse(m.group(1)!)))
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => _char(int.tryParse(m.group(1)!, radix: 16)))
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&hellip;', '…')
      .replaceAll('&ndash;', '–')
      .replaceAll('&mdash;', '-')
      .replaceAll('&amp;', '&');

  /// A numeric entity's character; out-of-range codes become a space.
  static String _char(int? code) => code != null && code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : ' ';
}
