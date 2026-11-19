import '../../i18n/strings.g.dart';

/// YouTube's standard video categories (ids are stable across regions).
abstract final class YouTubeCategories {
  static const Map<String, (String, String)> _names = {
    '1': ('Film & Animation', 'Film & Animation'),
    '2': ('Cars & Vehicles', 'Autos & Fahrzeuge'),
    '10': ('Music', 'Musik'),
    '15': ('Pets & Animals', 'Tiere'),
    '17': ('Sports', 'Sport'),
    '19': ('Travel & Events', 'Reisen & Events'),
    '20': ('Gaming', 'Gaming'),
    '22': ('People & Blogs', 'Menschen & Blogs'),
    '23': ('Comedy', 'Comedy'),
    '24': ('Entertainment', 'Unterhaltung'),
    '25': ('News & Politics', 'Nachrichten & Politik'),
    '26': ('How-to & Style', 'Praktische Tipps & Styling'),
    '27': ('Education', 'Bildung'),
    '28': ('Science & Technology', 'Wissenschaft & Technik'),
    '29': ('Nonprofits & Activism', 'Soziales Engagement'),
  };

  static String? name(String? id) {
    final entry = _names[id];
    if (entry == null) return null;
    return LocaleSettings.currentLocale == AppLocale.de ? entry.$2 : entry.$1;
  }

  /// Each channel's most common category among [videos] (channel id →
  /// category id). Channels without category data are left out.
  static Map<String, String> ofChannels(Iterable<({String channelId, String? categoryId})> videos) {
    final counts = <String, Map<String, int>>{};
    for (final v in videos) {
      final category = v.categoryId;
      if (category == null || v.channelId.isEmpty || !_names.containsKey(category)) continue;
      final perChannel = counts.putIfAbsent(v.channelId, () => {});
      perChannel[category] = (perChannel[category] ?? 0) + 1;
    }
    return {
      for (final entry in counts.entries)
        entry.key: entry.value.entries.reduce((a, b) => b.value > a.value ? b : a).key,
    };
  }
}
