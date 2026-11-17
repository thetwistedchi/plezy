import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';
import 'youtube_settings.dart';

/// A community-marked part of a video, from SponsorBlock.
class SponsorSegment {
  SponsorSegment({required this.start, required this.end, required this.category, required this.isHighlight});

  final double start;
  final double end;
  final String category;

  /// A "highlight" marker: a single point to jump to, not a range to skip.
  final bool isHighlight;

  bool contains(double t) => t >= start && t < end - 0.3;
}

/// Segment data from https://sponsor.ajay.app (CC BY-NC-SA 4.0).
class SponsorBlock {
  SponsorBlock._();

  static final http.Client _client = http.Client();

  static Future<List<SponsorSegment>> segments(String videoId) async {
    final settings = YouTubeSettings.instance;
    if (!settings.sponsorBlockEnabled) return const [];
    final categories = [
      for (final c in sponsorBlockDefaults.keys)
        if (settings.segmentMode(c) != SegmentMode.off) c,
      'poi_highlight',
    ];
    try {
      final response = await _client
          .get(
            Uri.https('sponsor.ajay.app', '/api/skipSegments', {
              'videoID': videoId,
              'categories': jsonEncode(categories),
              'actionTypes': jsonEncode(['skip', 'poi']),
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) return const [];
      if (response.statusCode != 200) return const [];
      final list = jsonDecode(response.body) as List;
      return [
        for (final raw in list)
          if (raw is Map && raw['segment'] is List && (raw['segment'] as List).length == 2)
            SponsorSegment(
              start: ((raw['segment'] as List)[0] as num).toDouble(),
              end: ((raw['segment'] as List)[1] as num).toDouble(),
              category: raw['category'] as String? ?? '',
              isHighlight: raw['actionType'] == 'poi' || raw['category'] == 'poi_highlight',
            ),
      ]..sort((a, b) => a.start.compareTo(b.start));
    } catch (e) {
      appLogger.d('SponsorBlock lookup failed for $videoId: $e');
      return const [];
    }
  }
}

/// A creator-set chapter, read from the video description.
class YtChapter {
  YtChapter(this.start, this.title);

  final double start;
  final String title;
}

final RegExp _timestamp = RegExp(r'(?:^|\s|\(|\[)((?:\d{1,2}:)?\d{1,2}:\d{2})(?=$|\s|\)|\]|[-–—:|.,])');

/// Parses chapters the way YouTube does: timestamps in the description, the
/// first at 0:00, at least three, ascending, each at least 10 seconds long.
List<YtChapter> parseChapters(String description) {
  final chapters = <YtChapter>[];
  for (final rawLine in const LineSplitter().convert(description)) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final match = _timestamp.firstMatch(line);
    if (match == null) continue;
    final seconds = _toSeconds(match.group(1)!);
    if (seconds == null) continue;
    final title = line
        .replaceRange(match.start, match.end, ' ')
        .replaceAll(RegExp(r'^[\s\-–—:|.\)\]]+|[\s\-–—:|]+$'), '')
        .trim();
    chapters.add(YtChapter(seconds.toDouble(), title.isEmpty ? match.group(1)! : title));
  }
  if (chapters.length < 3 || chapters.first.start != 0) return const [];
  for (var i = 1; i < chapters.length; i++) {
    if (chapters[i].start - chapters[i - 1].start < 10) return const [];
  }
  return chapters;
}

int? _toSeconds(String stamp) {
  final parts = stamp.split(':').map(int.tryParse).toList();
  if (parts.any((p) => p == null)) return null;
  var total = 0;
  for (final p in parts) {
    total = total * 60 + p!;
  }
  return total;
}
