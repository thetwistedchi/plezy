import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/retrowave_colors.dart';

/// Fork: AI-generated outrun-style SVG glyphs (sunset house, VHS tape, CRT with antennas,
/// horizon lines) for the navigation, the main tabs' top bar actions and the
/// hub headers, stroked with the cyan to magenta fade. Only on the retrowave
/// theme; [AppIcon] swaps them in when called with `retro: true`.
abstract final class RetroGlyphs {
  static const _home = '<path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10v10h13V10"/><path d="M8.5 16.5a3.5 3.5 0 0 1 7 0"/><path d="M7.5 18.5h9"/>';
  static const _libraries = '<rect x="2.5" y="6" width="19" height="12" rx="1.5"/><circle cx="7.5" cy="12" r="2"/><circle cx="16.5" cy="12" r="2"/><path d="M9.5 12h5"/><path d="M6 18l1.5-2.5h9L18 18"/>';
  static const _liveTv = '<rect x="3" y="7" width="18" height="12" rx="2"/><path d="M8 3l4 4 4-4"/><circle cx="17.5" cy="10.5" r="1"/><path d="M6.5 12.5h7M6.5 15.5h9"/>';
  static const _explore = '<circle cx="12" cy="12" r="9"/><path d="M15.5 8.5l-2 5-5 2 2-5z"/><path d="M3 12h1.5M19.5 12H21"/>';
  static const _search = '<circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5 21 21"/><path d="M5.5 11.5h10M6.8 14h7.4"/><path d="M10.5 11.5v4.5"/>';
  static const _youtube = '<rect x="3" y="4" width="18" height="11.5" rx="3"/><path d="M10.5 7.3v5l4.2-2.5z"/><path d="M5 18.5h14M8 21.5h8"/>';
  static const _downloads = '<path d="M12 2.5v10"/><path d="M7.5 8l4.5 4.5L16.5 8"/><path d="M3 16h18"/><path d="M6 19h12"/><path d="M9 21.5h6"/>';
  static const _settings = '<circle cx="12" cy="12" r="5.5"/><circle cx="12" cy="12" r="2.2"/><path d="M17.50 12.00L20.60 12.00"/><path d="M15.89 15.89L18.08 18.08"/><path d="M12.00 17.50L12.00 20.60"/><path d="M8.11 15.89L5.92 18.08"/><path d="M6.50 12.00L3.40 12.00"/><path d="M8.11 8.11L5.92 5.92"/><path d="M12.00 6.50L12.00 3.40"/><path d="M15.89 8.11L18.08 5.92"/><path d="M2 22h20"/>';
  static const _movie = '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 3v18M16 3v18M4 8h4M4 12h4M4 16h4M16 8h4M16 12h4M16 16h4"/>';
  static const _tv = '<rect x="2.5" y="4.5" width="19" height="12.5" rx="2.5"/><path d="M12 17v3.5M8 21h8"/><path d="M6 10.5h12M7.5 13.5h9"/>';
  static const _music = '<path d="M9 18V5.5l11-2.5v13"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/>';
  static const _photo = '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M8.5 13a3.5 3.5 0 0 1 7 0"/><path d="M5.5 15.5h13M7 18h10"/>';
  static const _share = '<circle cx="18" cy="5" r="2.5"/><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="19" r="2.5"/><path d="M8.2 10.8l7.6-4.6M8.2 13.2l7.6 4.6"/>';
  static const _folder = '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M3 11h18"/>';
  static const _expandMore = '<path d="M6 9l6 6 6-6"/>';
  static const _expandLess = '<path d="M6 15l6-6 6 6"/>';
  static const _chevronRight = '<path d="M9 6l6 6-6 6"/>';
  static const _freeOnPlex = '<path d="M4 6h16a1 1 0 0 1 1 1v3a2 2 0 0 0 0 4v3a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-3a2 2 0 0 0 0-4V7a1 1 0 0 1 1-1z"/><path d="M15.5 6v2M15.5 11v2M15.5 16v2"/><path d="M8 9.8v4.4l3.6-2.2z"/>';
  static const _arrowDropDown = '<path d="M7 10l5 5 5-5z"/>';
  static const _arrowForward = '<path d="M4 12h16M14 6l6 6-6 6"/>';
  static const _visibility = '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>';
  static const _visibilityOff = '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/><path d="M3.5 3.5l17 17"/>';
  static const _dns = '<rect x="3" y="4" width="18" height="6.5" rx="1.5"/><rect x="3" y="13.5" width="18" height="6.5" rx="1.5"/><path d="M7 7.25h.01M7 16.75h.01M11 7.25h6M11 16.75h6"/>';
  static const _wifi = '<path d="M2 9a15 15 0 0 1 20 0"/><path d="M5.5 12.5a10 10 0 0 1 13 0"/><path d="M9 16a5 5 0 0 1 6 0"/><path d="M12 19.5h.01"/>';
  static const _sync = '<path d="M4 12a8 8 0 0 1 13.7-5.7L20 8.5"/><path d="M20 4v4.5h-4.5"/><path d="M20 12a8 8 0 0 1-13.7 5.7L4 15.5"/><path d="M4 20v-4.5h4.5"/>';
  static const _fullscreen = '<path d="M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5"/>';
  static const _fullscreenExit = '<path d="M9 4v5H4M15 4v5h5M20 15h-5v5M4 15h5v5"/>';
  static const _party = '<rect x="3" y="7" width="18" height="12" rx="2"/><path d="M8 3l4 4 4-4"/><circle cx="9.5" cy="11.5" r="1.4"/><circle cx="14.5" cy="11.5" r="1.4"/><path d="M7 16.5c.6-1.4 1.5-2 2.5-2s1.9.6 2.5 2c.6-1.4 1.5-2 2.5-2s1.9.6 2.5 2"/>';
  static const _refresh = '<path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 4v5h-5"/><path d="M8.5 14.5a3.5 3.5 0 0 1 7 0"/><path d="M8 16.5h8"/>';
  static const _phone = '<rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M10.5 18.5h3"/><path d="M9 12.5a3 3 0 0 1 6 0"/><path d="M8.5 14.5h7"/>';
  static const _monitor = '<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M6 11h3l1.5-3 3 6 1.5-3h3"/><path d="M8 21h8M12 17v4"/>';
  static const _account = '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="3"/><path d="M6.5 18.5c1.3-2 3.2-3 5.5-3s4.2 1 5.5 3"/>';
  static const _ruleSettings = '<path d="M4 6h12M4 11h8M4 16h5"/><circle cx="17" cy="16" r="2.6"/><circle cx="17" cy="16" r="0.9"/><path d="M19.60 16.00L21.60 16.00"/><path d="M18.84 17.84L20.25 19.25"/><path d="M17.00 18.60L17.00 20.60"/><path d="M15.16 17.84L13.75 19.25"/><path d="M14.40 16.00L12.40 16.00"/><path d="M15.16 14.16L13.75 12.75"/><path d="M17.00 13.40L17.00 11.40"/><path d="M18.84 14.16L20.25 12.75"/>';
  static const _tune = '<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>';
  static const _edit = '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13 7l4 4"/>';
  static const _shuffle = '<path d="M3 7h4l10 10h4"/><path d="M3 17h4l3-3"/><path d="M14 10l3-3h4"/><path d="M18 4l3 3-3 3"/><path d="M18 14l3 3-3 3"/>';
  static const _star = '<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z" fill="url(#g)"/>';
  static const _swapVert = '<path d="M8 20V4M4 8l4-4 4 4"/><path d="M16 4v16M12 16l4 4 4-4"/>';
  static const _bolt = '<path d="M13 2 5 13.5h6L10 22l9-12.5h-6z"/>';
  static const _help = '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 0 1 4.9.7c0 1.7-2.4 2-2.4 3.8"/><path d="M12 17h.01"/>';
  static const _subscriptions = '<path d="M6 3h12M4.5 6.5h15"/><rect x="3" y="10" width="18" height="11" rx="2"/><path d="M10.5 13v5l4-2.5z"/>';
  static const _continueWatching = '<path d="M3 13a9 9 0 0 1 18 0"/><path d="M3.5 15.5h17M5 18h14M7.5 20.5h9"/><path d="M10.2 6.5v5l4-2.5z"/>';
  static const _recentlyAdded = '<path d="M11 3l1.8 5.7 5.7 1.8-5.7 1.8L11 18l-1.8-5.7-5.7-1.8 5.7-1.8z"/><path d="M18.5 15l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/>';
  static const _trending = '<path d="M3 16l6-6 4 4 8-8"/><path d="M15 6h6v6"/><path d="M3 21h18"/>';
  static const _hot = '<path d="M12 2c1 3.5 5 5.5 5 10.5a5 5 0 0 1-10 0c0-2.2 1-3.7 2.5-5 .2 1.8 1 3 2.5 3.5C11 8.5 11 5 12 2z"/>';
  static const _calendar = '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/><path d="M9 17.5a3 3 0 0 1 6 0"/>';
  static const _medal = '<path d="M8 2l4 6 4-6"/><circle cx="12" cy="15" r="6"/><path d="M12 12l1 2 2.2.3-1.6 1.5.4 2.2-2-1-2 1 .4-2.2-1.6-1.5L11 14z"/>';
  static const _warning = '<path d="M12 3l10 18H2z"/><path d="M12 10v5"/><path d="M12 18h.01"/>';
  static const _mood = '<circle cx="12" cy="12" r="9"/><path d="M8.5 14.5c.9 1.3 2.1 2 3.5 2s2.6-.7 3.5-2"/><path d="M9 9.5h.01M15 9.5h.01"/>';
  static const _masks = '<path d="M3 4h10v6a5 5 0 0 1-10 0z"/><path d="M11 10h10v6a5 5 0 0 1-10 0z"/><path d="M6 7.5h.01M10 7.5h.01M14 13.5h.01M18 13.5h.01"/>';
  static const _wand = '<path d="M4 20 16 8"/><path d="M14 6l4 4"/><path d="M19 2.5l.6 1.4 1.4.6-1.4.6-.6 1.4-.6-1.4-1.4-.6 1.4-.6z"/><path d="M7 3v3M5.5 4.5h3"/>';
  static const _rocket = '<path d="M12 15l-3-3c1.5-4.5 5-8 10.5-8.5C19 9 15.5 12.5 12 15z"/><path d="M9 12H5.5L8 8.5h4"/><path d="M12 15v3.5l3.5-2.5V12"/><path d="M6.5 16.5C5 17 4 18.5 4 20c1.5 0 3-1 3.5-2.5"/>';
  static const _moon = '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/><path d="M17 3v3M15.5 4.5h3"/>';
  static const _heart = '<path d="M12 20s-8-4.8-8-10.5A4.5 4.5 0 0 1 12 7a4.5 4.5 0 0 1 8 2.5C20 15.2 12 20 12 20z"/>';
  static const _playlist = '<path d="M4 6h12M4 11h12M4 16h7"/><path d="M15 14v6l5-3z"/>';
  static const _person = '<circle cx="12" cy="8" r="4"/><path d="M4.5 21c.8-4 3.8-6 7.5-6s6.7 2 7.5 6"/>';
  static const _history = '<path d="M4 12a8 8 0 1 0 2.4-5.7L4 8.5"/><path d="M4 4v4.5h4.5"/><path d="M12 8v4.5l3 2"/>';
  static const _play = '<path d="M8 5v14l11-7z"/>';
  static const _thumbUp = '<path d="M7 10v10H4V10z"/><path d="M7 10l4-7c1.5 0 2.5 1 2.5 2.5V9h5a2 2 0 0 1 2 2.3l-1.3 7A2 2 0 0 1 17.2 20H7"/>';
  static const _category = '<path d="M12 3l4.5 7.5h-9z"/><circle cx="17" cy="17" r="3.5"/><rect x="3.5" y="13.5" width="7" height="7" rx="1"/>';
  static const _awesome = '<path d="M10 4l1.6 4.4L16 10l-4.4 1.6L10 16l-1.6-4.4L4 10l4.4-1.6z"/><path d="M18 3v4M16 5h4M18 15v4M16 17h4"/>';

  // In-app browser (AI-generated like the rest).
  static const _globe = '<circle cx="12" cy="12" r="9"/><path d="M12 3c2.6 2.6 3.8 5.6 3.8 9s-1.2 6.4-3.8 9c-2.6-2.6-3.8-5.6-3.8-9S9.4 5.6 12 3z"/><path d="M3 12h18M4.6 7.5h14.8M4.6 16.5h14.8"/>';
  static const _lock = '<rect x="5" y="10.5" width="14" height="10.5" rx="2"/><path d="M8 10.5v-3a4 4 0 0 1 8 0v3"/><path d="M8.5 15h7M10 18h4"/>';
  static const _lockOpen = '<rect x="5" y="10.5" width="14" height="10.5" rx="2"/><path d="M8 10.5v-3a4 4 0 0 1 7.6-1.7"/><path d="M12 14v3.5"/>';
  static const _bookmark = '<path d="M6 3.5h12v17l-6-4-6 4z" fill="url(#g)"/>';
  static const _bookmarkAdd = '<path d="M13 3.5H6v17l6-4 6 4V11"/><path d="M18 2.5v6M15 5.5h6"/>';
  static const _bookmarks = '<path d="M8 6.5h11v14l-5.5-3.5L8 20.5z"/><path d="M5 17V3.5h10"/>';
  static const _arrowBack = '<path d="M20 12H4M10 6l-6 6 6 6"/>';
  static const _add = '<path d="M12 5v14M5 12h14"/>';
  static const _close = '<path d="M6 6l12 12M18 6 6 18"/>';

  static final Map<IconData, String> _byIcon = {
    Symbols.home_rounded: _home,
    Symbols.video_library_rounded: _libraries,
    Symbols.live_tv_rounded: _liveTv,
    Symbols.explore_rounded: _explore,
    Symbols.search_rounded: _search,
    Symbols.smart_display_rounded: _youtube,
    Symbols.download_rounded: _downloads,
    Symbols.settings_rounded: _settings,
    Symbols.movie_rounded: _movie,
    Symbols.tv_rounded: _tv,
    Symbols.music_note_rounded: _music,
    Symbols.photo_rounded: _photo,
    Symbols.share_rounded: _share,
    Symbols.folder_rounded: _folder,
    Symbols.expand_more_rounded: _expandMore,
    Symbols.expand_less_rounded: _expandLess,
    Symbols.chevron_right_rounded: _chevronRight,
    Symbols.arrow_forward_rounded: _arrowForward,
    Symbols.arrow_drop_down_rounded: _arrowDropDown,
    Symbols.local_activity_rounded: _freeOnPlex,
    Symbols.visibility_rounded: _visibility,
    Symbols.visibility_off_rounded: _visibilityOff,
    Symbols.dns_rounded: _dns,
    Symbols.wifi_rounded: _wifi,
    Symbols.sync_rounded: _sync,
    Symbols.fullscreen_rounded: _fullscreen,
    Symbols.fullscreen_exit_rounded: _fullscreenExit,
    Symbols.group_rounded: _party,
    Symbols.refresh_rounded: _refresh,
    Symbols.phone_android_rounded: _phone,
    Symbols.monitor_heart_rounded: _monitor,
    Symbols.account_circle_rounded: _account,
    Symbols.rule_settings_rounded: _ruleSettings,
    Symbols.tune_rounded: _tune,
    Symbols.edit_rounded: _edit,
    Symbols.shuffle_rounded: _shuffle,
    Symbols.star_rounded: _star,
    Symbols.swap_vert_rounded: _swapVert,
    Symbols.bolt_rounded: _bolt,
    Symbols.flash_on_rounded: _bolt,
    Symbols.help_rounded: _help,
    Symbols.subscriptions_rounded: _subscriptions,
    Symbols.play_circle_rounded: _continueWatching,
    Symbols.new_releases_rounded: _recentlyAdded,
    Symbols.schedule_rounded: _recentlyAdded,
    Symbols.trending_up_rounded: _trending,
    Symbols.whatshot_rounded: _hot,
    Symbols.calendar_month_rounded: _calendar,
    Symbols.military_tech_rounded: _medal,
    Symbols.warning_amber_rounded: _warning,
    Symbols.mood_rounded: _mood,
    Symbols.theater_comedy_rounded: _masks,
    Symbols.auto_fix_high_rounded: _wand,
    Symbols.rocket_launch_rounded: _rocket,
    Symbols.nights_stay_rounded: _moon,
    Symbols.favorite_border_rounded: _heart,
    Symbols.playlist_play_rounded: _playlist,
    Symbols.person_rounded: _person,
    Symbols.history_rounded: _history,
    Symbols.play_arrow_rounded: _play,
    Symbols.thumb_up_rounded: _thumbUp,
    Symbols.category_rounded: _category,
    Symbols.auto_awesome_rounded: _awesome,
    Symbols.public_rounded: _globe,
    Symbols.lock_rounded: _lock,
    Symbols.lock_open_rounded: _lockOpen,
    Symbols.bookmark_rounded: _bookmark,
    Symbols.bookmark_add_rounded: _bookmarkAdd,
    Symbols.bookmarks_rounded: _bookmarks,
    Symbols.arrow_back_rounded: _arrowBack,
    Symbols.add_rounded: _add,
    Symbols.close_rounded: _close,
  };

  static String? pathsFor(IconData icon) => _byIcon[icon];

  static final Map<String, String> _svgCache = {};

  static String svg(String paths) => _svgCache.putIfAbsent(
    paths,
    () =>
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="url(#g)" '
        'stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round">'
        '<defs><linearGradient id="g" x1="0" y1="0" x2="24" y2="24" gradientUnits="userSpaceOnUse">'
        // Cyan to a lighter magenta: the theme's #C10093 is only about 2.3:1
        // on the night background, this end about 6:1.
        '<stop offset="0" stop-color="#3FDDF0"/><stop offset="1" stop-color="#EC4FC4"/></linearGradient></defs>'
        '$paths</svg>',
  );
}

/// One [RetroGlyphs] glyph at [size] (the ambient icon size when null).
/// [opacity] dims it, e.g. for unselected navigation entries.
class RetroGlyph extends StatelessWidget {
  const RetroGlyph(this.paths, {super.key, this.size, this.opacity = 1, this.semanticLabel});

  final String paths;
  final double? size;
  final double opacity;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final s = size ?? IconTheme.of(context).size ?? 24;
    Widget glyph = SvgPicture.string(RetroGlyphs.svg(paths), width: s, height: s, semanticsLabel: semanticLabel);
    if (opacity < 1) glyph = Opacity(opacity: opacity, child: glyph);
    return SizedBox(width: s, height: s, child: glyph);
  }

  /// The glyph for [icon] when the retrowave theme is active, else null.
  static String? pathsIfActive(BuildContext context, IconData? icon) {
    if (icon == null || !RetroColors.isActive(context)) return null;
    return RetroGlyphs.pathsFor(icon);
  }
}
