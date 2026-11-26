import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/retrowave_colors.dart';
import '../utils/platform_detector.dart';

/// Fork: AI-generated neon-sign SVG glyphs (house, VHS tape, CRT with antennas,
/// horizon lines) for the navigation, the main tabs' top bar actions and the
/// hub headers, drawn as cyan and magenta tubes. Only on the retrowave
/// theme; [AppIcon] swaps them in when called with `retro: true`.
abstract final class RetroGlyphs {
  static const _home = '<path d="M4 11L12 4.5 20 11M6 9.5V19.5H18V9.5"/>|<path d="M9.5 19.5a2.5 2.5 0 0 1 5 0"/>';
  static const _libraries = '<rect x="3" y="6.5" width="18" height="11" rx="2"/>|<circle cx="8.3" cy="12" r="2"/><circle cx="15.7" cy="12" r="2"/>';
  static const _liveTv = '<rect x="3" y="8" width="18" height="12" rx="2.5"/>|<path d="M8.5 3.5 12 7l3.5-3.5"/>';
  static const _explore = '<circle cx="12" cy="12" r="8.8"/>|<path d="M15.3 8.7 13.2 13.2 8.7 15.3 10.8 10.8Z"/>';
  static const _search = '<circle cx="10.5" cy="10.5" r="6.5"/>|<path d="M15.6 15.6 20.5 20.5"/>';
  static const _youtube = '<rect x="3" y="5" width="18" height="13.5" rx="3.5"/>|<path d="M10.3 9v5.4l4.5-2.7Z"/>';
  static const _downloads = '<path d="M12 3.5v10.5M7.5 9.5 12 14l4.5-4.5"/>|<path d="M4.5 19.5h15"/>';
  static const _settings = '<path d="M12.62 5.73L14.41 4.06L15.91 4.68L16.00 7.13L16.87 8.00L19.32 8.09L19.94 9.59L18.27 11.38L18.27 12.62L19.94 14.41L19.32 15.91L16.87 16.00L16.00 16.87L15.91 19.32L14.41 19.94L12.62 18.27L11.38 18.27L9.59 19.94L8.09 19.32L8.00 16.87L7.13 16.00L4.68 15.91L4.06 14.41L5.73 12.62L5.73 11.38L4.06 9.59L4.68 8.09L7.13 8.00L8.00 7.13L8.09 4.68L9.59 4.06L11.38 5.73Z"/>|<circle cx="12" cy="12" r="2.6"/>';
  static const _movie = '<rect x="3.5" y="9.5" width="17" height="10.5" rx="1.8"/>|<path d="M3.8 9.3 19.6 5"/>';
  static const _tv = '<rect x="3" y="4.5" width="18" height="12.5" rx="2.5"/>|<path d="M8.5 20.5h7"/>';
  static const _music = '<path d="M9 17.5V5.5L19 3.5V15.5"/>|<circle cx="6.7" cy="17.5" r="2.3"/><circle cx="16.7" cy="15.5" r="2.3"/>';
  static const _photo = '<rect x="3" y="4.5" width="18" height="15" rx="2.2"/>|<path d="M6.5 16.5 10 12.5l2.5 2.5 2-2 3 3.5"/><circle cx="15.8" cy="8.8" r="1.4"/>';
  static const _share = '<circle cx="18" cy="5.5" r="2.3"/><circle cx="6" cy="12" r="2.3"/><circle cx="18" cy="18.5" r="2.3"/>|<path d="M8.1 10.9 15.9 6.6M8.1 13.1l7.8 4.3"/>';
  static const _folder = '<path d="M3.5 7.5a2 2 0 0 1 2-2h3.8l2 2h7.2a2 2 0 0 1 2 2v8.5a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2Z"/>|<path d="M7 11h10"/>';
  static const _expandMore = '<path d="M6 9l6 6 6-6"/>|';
  static const _expandLess = '<path d="M6 15l6-6 6 6"/>|';
  static const _chevronRight = '|<path d="M9 6l6 6-6 6"/>';
  static const _freeOnPlex = '<path d="M4 6h16a1 1 0 0 1 1 1v3a2 2 0 0 0 0 4v3a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-3a2 2 0 0 0 0-4V7a1 1 0 0 1 1-1Z"/>|<path d="M10 9.8v4.4l3.6-2.2Z"/>';
  static const _arrowDropDown = '|<path d="M7.5 10h9L12 15Z"/>';
  static const _arrowForward = '<path d="M4 12h15"/>|<path d="M13.5 6.5 19 12l-5.5 5.5"/>';
  static const _visibility = '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z"/>|<circle cx="12" cy="12" r="2.8"/>';
  static const _visibilityOff = '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z"/>|<path d="M4 4l16 16"/>';
  static const _dns = '<rect x="3" y="4" width="18" height="6.5" rx="1.8"/><rect x="3" y="13.5" width="18" height="6.5" rx="1.8"/>|<path d="M7 7.25h.01M7 16.75h.01"/>';
  static const _wifi = '<path d="M2.5 9a14 14 0 0 1 19 0M5.8 12.5a9.5 9.5 0 0 1 12.4 0"/>|<path d="M9 16a4.5 4.5 0 0 1 6 0M12 19.5h.01"/>';
  static const _sync = '<path d="M4.5 12a7.5 7.5 0 0 1 13-5.1M19.5 12a7.5 7.5 0 0 1-13 5.1"/>|<path d="M17.8 3.5v3.7h-3.7M6.2 20.5v-3.7h3.7"/>';
  static const _fullscreen = '<path d="M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5"/>|';
  static const _fullscreenExit = '<path d="M9 4v5H4M15 4v5h5M20 15h-5v5M4 15h5v5"/>|';
  static const _party = '<rect x="3" y="8" width="18" height="12" rx="2.5"/>|<path d="M8.5 3.5 12 7l3.5-3.5M7.5 17a2.3 2.3 0 0 1 4.3 0M12.2 17a2.3 2.3 0 0 1 4.3 0"/><circle cx="9.65" cy="12.6" r="1.2"/><circle cx="14.35" cy="12.6" r="1.2"/>';
  static const _refresh = '<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3"/>|<path d="M19.5 3.8V8.3H15"/>';
  static const _phone = '<rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/>|<path d="M10.5 18.5h3"/>';
  static const _monitor = '<rect x="3" y="4" width="18" height="13" rx="2.2"/><path d="M8.5 21h7"/>|<path d="M6 10.5h3l1.5-3 3 6 1.5-3h3"/>';
  static const _account = '<circle cx="12" cy="12" r="8.8"/>|<circle cx="12" cy="10" r="2.9"/><path d="M7.3 17.8a5.5 4.2 0 0 1 9.4 0"/>';
  static const _ruleSettings = '<g transform="translate(-0.7 -1.2)"><path d="M4 6h12M4 11h8M4 16h5"/></g>|<g transform="translate(-0.7 -1.2)"><circle cx="17" cy="16" r="2.4"/><path d="M17 11.6v1.2M17 19.2v1.2M12.6 16h1.2M20.2 16h1.2"/></g>';
  static const _tune = '<path d="M4 7.5h8M16 7.5h4M4 16.5h3M11 16.5h9"/>|<circle cx="14" cy="7.5" r="2"/><circle cx="9" cy="16.5" r="2"/>';
  static const _edit = '<path d="M4.5 19.5 5 15.5 15.5 5a2.1 2.1 0 0 1 3 3L8 18.5Z"/>|<path d="M13.5 7l3 3"/>';
  static const _shuffle = '<path d="M3.5 7h3c4.5 0 6 10 10.5 10h3M18 14.5l2.5 2.5-2.5 2.5"/>|<path d="M3.5 17h3c1.6 0 2.7-1.3 3.6-3M13.4 10c.9-1.7 2-3 3.6-3h3M18 4.5 20.5 7 18 9.5"/>';
  static const _star = '<path d="M12 3.5l2.5 5.2 5.7.8-4.1 4 1 5.6-5.1-2.7-5.1 2.7 1-5.6-4.1-4 5.7-.8Z"/>|';
  static const _swapVert = '<path d="M8 19.5V4.5M4.5 8 8 4.5 11.5 8"/>|<path d="M16 4.5v15M12.5 16l3.5 3.5 3.5-3.5"/>';
  static const _bolt = '|<path d="M13 2.5 5.5 13.5h6L10.5 21.5 18.5 10.5h-6Z"/>';
  static const _help = '<circle cx="12" cy="12" r="8.8"/>|<path d="M9.6 9.5a2.5 2.5 0 0 1 4.8.9c0 1.7-2.4 2.1-2.4 3.8M12 17.2h.01"/>';
  static const _reader = '<path d="M3 5.5h7a2 2 0 0 1 2 2V20a1.5 1.5 0 0 0-1.5-1.5H3ZM21 5.5h-7a2 2 0 0 0-2 2V20a1.5 1.5 0 0 1 1.5-1.5H21Z"/>|<path d="M5.5 9h4M5.5 12h4M14.5 9h4M14.5 12h4"/>';
  static const _textSmaller = '<path d="M3 19 8 6l5 13M4.8 14.5h6.4"/>|<path d="M15.5 12h6"/>';
  static const _textLarger = '<path d="M3 19 8 6l5 13M4.8 14.5h6.4"/>|<path d="M15.5 12h6M18.5 9v6"/>';
  static const _remove = '|<path d="M6 12h12"/>';
  static const _countOnce = '<rect x="3.5" y="3.5" width="17" height="17" rx="2.5"/>|<path d="M10 9l2.5-1.5V16.5"/>';
  static const _checkCircle = '<circle cx="12" cy="12" r="8.5"/>|<path d="M8 12.3l2.7 2.7L16.2 9.5"/>';
  static const _pauseCircle = '<circle cx="12" cy="12" r="8.5"/>|<path d="M10 9v6M14 9v6"/>';
  static const _clapper = '<rect x="3.5" y="9" width="17" height="11" rx="2"/>|<path d="M3.5 9 4.6 4.5h14.8L20.5 9M8.5 4.5 10 9M13.5 4.5 15 9"/>';
  static const _hourglass = '<path d="M7 3.5h10M7 20.5h10"/>|<path d="M8 3.5c0 4 8 4.5 8 8.5s-8 4.5-8 8.5M16 3.5c0 4-8 4.5-8 8.5s8 4.5 8 8.5"/>';
  static const _barChart = '<path d="M3.5 20.5h17"/>|<path d="M6.5 17V11M11 17V6M15.5 17v-8M20 17v-4"/>';
  static const _timer = '<circle cx="12" cy="13.5" r="7.5"/><path d="M9.5 2.5h5"/>|<path d="M12 9.5v4l2.5 1.5"/>';
  static const _addChannel = '<rect x="2.5" y="8" width="13.5" height="10.5" rx="2.2"/><path d="M5 5h8.5"/>|<path d="M7.75 10.9v4.7l3.8-2.35Z"/><path d="M20 9.5v7M16.5 13h7"/>';
  static const _subscriptions = '<rect x="3" y="9.5" width="18" height="11" rx="2.2"/><path d="M6 3.5h12M4.5 6.5h15"/>|<path d="M10.5 12.5v5l4-2.5Z"/>';
  static const _continueWatching = '<path d="M3.5 15a8.5 8.5 0 0 1 17 0M3 18.5h18"/>|<path d="M10.75 9.4v4.6l3.8-2.3Z"/>';
  static const _recentlyAdded = '<path d="M10.5 3.5l1.8 5.2 5.2 1.8-5.2 1.8-1.8 5.2-1.8-5.2-5.2-1.8 5.2-1.8Z"/>|<path d="M18 15l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8Z"/>';
  static const _trending = '<path d="M3.5 16.5 9 11l4 4 7.5-7.5"/>|<path d="M15 7.5h5.5V13"/>';
  static const _hot = '<path d="M12 19.5a2.3 2.3 0 0 1-2.3-2.3c0-1.5 1.2-2.4 2.3-3.7 1.1 1.3 2.3 2.2 2.3 3.7a2.3 2.3 0 0 1-2.3 2.3Z"/>|<path d="M12 2.5c1 3.5 5.5 5.5 5.5 10.5a5.5 5.5 0 0 1-11 0c0-2.3 1-3.8 2.5-5.2.3 1.8 1.1 2.9 2.4 3.4C10.9 8.5 11 5.5 12 2.5Z"/>';
  static const _calendar = '<rect x="3.5" y="5.5" width="17" height="15" rx="2.2"/><path d="M3.5 10.5h17"/>|<path d="M8 3.5v4M16 3.5v4"/>';
  static const _medal = '<circle cx="12" cy="15" r="5.8"/>|<path d="M8 2.5l3 5.5M16 2.5l-3 5.5"/>';
  static const _warning = '<path d="M10.3 4.2a2 2 0 0 1 3.4 0l7.6 13.3a2 2 0 0 1-1.7 3H4.4a2 2 0 0 1-1.7-3Z"/>|<path d="M12 9.5v4.5M12 17h.01"/>';
  static const _mood = '<circle cx="12" cy="12" r="8.8"/>|<path d="M8.5 14.5c.9 1.3 2.1 2 3.5 2s2.6-.7 3.5-2M9 9.8h.01M15 9.8h.01"/>';
  static const _masks = '<path d="M3 4h10v6a5 5 0 0 1-10 0Z"/>|<path d="M11 10h10v6a5 5 0 0 1-10 0Z"/>';
  static const _wand = '<path d="M4 20 15.5 8.5M14 6.5l3.5 3.5"/>|<path d="M19 2.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7ZM7 3v3M5.5 4.5h3"/>';
  static const _rocket = '<path d="M12 15l-3-3c1.5-4.5 5-8 10.5-8.5C19 9 15.5 12.5 12 15Z"/><path d="M9 12H5.5L8 8.5h4"/><path d="M12 15v3.5l3.5-2.5V12"/>|<path d="M6.5 16.5C5 17 4 18.5 4 20c1.5 0 3-1 3.5-2.5"/>';
  static const _moon = '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5Z"/>|<path d="M17 3v3M15.5 4.5h3"/>';
  static const _heart = '|<path d="M12 19.5S4 14.8 4 9.3A4 4 0 0 1 12 7.6 4 4 0 0 1 20 9.3C20 14.8 12 19.5 12 19.5Z"/>';
  static const _playlist = '<g transform="translate(0 -1)"><path d="M4 6h12M4 11h12M4 16h7"/></g>|<g transform="translate(0 -1)"><path d="M15 14v6l5-3Z"/></g>';
  static const _person = '<circle cx="12" cy="8" r="3.8"/>|<path d="M4.5 20.5c.8-3.8 3.8-5.8 7.5-5.8s6.7 2 7.5 5.8"/>';
  static const _history = '<path d="M4.5 12a7.5 7.5 0 1 0 2.2-5.3L4.5 9M4.5 4.8V9H8.7"/>|<path d="M12 8v4l2.8 2"/>';
  static const _play = '|<path d="M8 5.5V18.5L18.5 12Z"/>';
  static const _thumbUp = '<path d="M7 10l4-7c1.5 0 2.5 1 2.5 2.5V9h5a2 2 0 0 1 2 2.3l-1.3 7A2 2 0 0 1 17.2 20H7"/>|<path d="M7 10v10H4V10Z"/>';
  static const _category = '<path d="M12 3.5l4.3 7h-8.6Z"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.2"/>|<circle cx="17" cy="17" r="3.3"/>';
  static const _awesome = '<g transform="translate(0 1)"><path d="M10 4l1.6 4.4L16 10l-4.4 1.6L10 16l-1.6-4.4L4 10l4.4-1.6Z"/></g>|<g transform="translate(0 1)"><path d="M18 3v4M16 5h4M18 15v4M16 17h4"/></g>';

  // In-app browser (AI-generated like the rest).
  static const _globe = '<circle cx="12" cy="12" r="8.8"/><path d="M3.2 12h17.6"/>|<path d="M12 3.2c2.4 2.5 3.6 5.5 3.6 8.8s-1.2 6.3-3.6 8.8c-2.4-2.5-3.6-5.5-3.6-8.8S9.6 5.7 12 3.2Z"/>';
  static const _lock = '<rect x="5" y="10.5" width="14" height="10" rx="2.2"/>|<path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>';
  static const _lockOpen = '<rect x="5" y="10.5" width="14" height="10" rx="2.2"/>|<path d="M8 10.5V8a4 4 0 0 1 7.6-1.7"/>';
  static const _bookmark = '|<path d="M6.5 4.5a1 1 0 0 1 1-1h9a1 1 0 0 1 1 1v16l-5.5-4-5.5 4Z"/>';
  static const _bookmarkAdd = '<g transform="translate(-1.75 0.5)"><path d="M13 3.5H7.5a1 1 0 0 0-1 1v16l5.5-4 5.5 4V11"/></g>|<g transform="translate(-1.75 0.5)"><path d="M18 2.5v6M15 5.5h6"/></g>';
  static const _bookmarks = '<path d="M8 6.5h11v14l-5.5-3.5L8 20.5Z"/>|<path d="M5 17V3.5h10"/>';
  static const _arrowBack = '<path d="M20 12H5"/>|<path d="M10.5 6.5 5 12l5.5 5.5"/>';
  static const _add = '|<path d="M12 5v14M5 12h14"/>';
  static const _close = '|<path d="M6 6 18 18M18 6 6 18"/>';

  static const _openInNew = '<path d="M18 14v4.5A1.5 1.5 0 0 1 16.5 20h-11A1.5 1.5 0 0 1 4 18.5v-11A1.5 1.5 0 0 1 5.5 6H10"/>|<path d="M14 4h6v6M20 4l-9 9"/>';
  static const _more = '<circle cx="12" cy="5.5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="18.5" r="1"/>|';
  static const _volumeUp = '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4Z"/>|<path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/>';
  static const _volumeOff = '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4Z"/>|<path d="M16 9.5l5 5M21 9.5l-5 5"/>';
  static const _shield = '<path d="M12 2.5 4.5 5.5v6c0 4.6 3.2 8.4 7.5 10 4.3-1.6 7.5-5.4 7.5-10v-6Z"/>|<path d="M8.5 12l2.5 2.5 4.5-5"/>';
  static const _pause = '|<path d="M8.5 5.5v13M15.5 5.5v13"/>';


  // Player controls.
  static const _skipNext = '<path d="M6 6v12l8.5-6Z"/>|<path d="M18 6v12"/>';
  static const _skipPrev = '<path d="M18 6v12L9.5 12Z"/>|<path d="M6 6v12"/>';
  static const _fastForward = '<path d="M3.5 6.5v11L11.5 12Z"/>|<path d="M12.5 6.5v11L20.5 12Z"/>';
  static const _fastRewind = '<path d="M20.5 6.5v11L12.5 12Z"/>|<path d="M11.5 6.5v11L3.5 12Z"/>';
  static const _replay10 = '<path d="M4 12a8 8 0 1 0 2.4-5.7L4 8.5M4 4.3v4.2h4.2"/>|<path d="M9.3 9.6l1.3-.9v6.6"/><rect x="12.6" y="8.7" width="3.4" height="6.6" rx="1.7"/>';
  static const _forward10 = '<path d="M20 12a8 8 0 1 1-2.4-5.7L20 8.5M20 4.3v4.2h-4.2"/>|<path d="M8.3 9.6l1.3-.9v6.6"/><rect x="11.6" y="8.7" width="3.4" height="6.6" rx="1.7"/>';
  static const _replay = '<path d="M5 12a7 7 0 1 0 2.1-5L5 9M5 4.8V9h4.2"/>|<path d="M13.5 9.5 11 12l2.5 2.5"/>';
  static const _forward = '<path d="M19 12a7 7 0 1 1-2.1-5L19 9M19 4.8V9h-4.2"/>|<path d="M10.5 9.5 13 12l-2.5 2.5"/>';
  static const _subtitles = '<rect x="3" y="5" width="18" height="14" rx="2.5"/>|<path d="M7 11.5h4M13 11.5h4M7 15h6M15.5 15h1.5"/>';
  static const _subtitlesOff = '<rect x="3" y="5" width="18" height="14" rx="2.5"/>|<path d="M4 4l16 16"/>';
  static const _pip = '<rect x="3" y="5" width="18" height="14" rx="2.5"/>|<rect x="12" y="12" width="6" height="4.5" rx="1"/>';
  static const _miniPlayer = '<rect x="3" y="5" width="18" height="14" rx="2.5"/>|<path d="M7 15h10"/>';
  static const _layers = '<path d="M12 4 3.5 8.5 12 13l8.5-4.5Z"/>|<path d="M3.5 12.5 12 17l8.5-4.5M3.5 16 12 20.5l8.5-4.5"/>';
  static const _record = '|<circle cx="12" cy="12" r="5"/>';
  static const _bedtime = '<path d="M19.5 14.5A8 8 0 1 1 9.5 4.5a6.5 6.5 0 0 0 10 10Z"/>|<path d="M15 4h3.5L15 8h3.5"/>';
  static const _list = '<path d="M9 6h11M9 12h11M9 18h11"/>|<path d="M4.5 6h.01M4.5 12h.01M4.5 18h.01"/>';
  static const _description = '<path d="M6.5 3.5h7.5l4.5 4.5v12a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-15.5a1 1 0 0 1 1-1Z"/>|<path d="M9 12.5h6M9 16h6"/>';
  static const _thumbDown = '<path d="M17 14l-4 7c-1.5 0-2.5-1-2.5-2.5V15h-5a2 2 0 0 1-2-2.3l1.3-7A2 2 0 0 1 6.8 4H17"/>|<path d="M17 14V4h3v10Z"/>';
  static const _accountBox = '<rect x="3.5" y="3.5" width="17" height="17" rx="2.5"/>|<circle cx="12" cy="10" r="2.6"/><path d="M7.5 17.5a5 3.8 0 0 1 9 0"/>';
  static const _fitScreen = '<path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16"/>|<rect x="7" y="9" width="10" height="6" rx="1"/>';
  static const _aspectRatio = '<rect x="3" y="5" width="18" height="14" rx="2.5"/>|<path d="M7 11V9h3M17 13v2h-3"/>';
  static const _overscan = '<rect x="3" y="5" width="18" height="14" rx="2.5"/>|<path d="M6.5 12h11M8.5 10l-2 2 2 2M15.5 10l2 2-2 2"/>';
  static const _theaters = '<rect x="5" y="3.5" width="14" height="17" rx="2"/>|<path d="M9 3.5v17M15 3.5v17"/>';
  static const _check = '|<path d="M5 12.5l4.5 4.5L19 7.5"/>';
  static const _headphones = '<path d="M4 15v-3a8 8 0 0 1 16 0v3"/>|<rect x="3.5" y="14" width="4.5" height="6.5" rx="1.5"/><rect x="16" y="14" width="4.5" height="6.5" rx="1.5"/>';
  static const _bell = '<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15Z"/>|<path d="M10 20.5a2 2 0 0 0 4 0"/>';
  static const _doneAll = '<path d="M2.5 12.5 7 17l9.5-9.5"/>|<path d="M12 16l1 1 9.5-9.5"/>';
  static const _clearAll = '<path d="M4 7h12M4 12h12M4 17h8"/>|<path d="M15.5 15.5l5 5M20.5 15.5l-5 5"/>';
  static const _removeDone = '<path d="M5 12.5l4.5 4.5L19 7.5"/>|<path d="M4 4l16 16"/>';
  static const _resume = '<path d="M6 6v12"/>|<path d="M10 6v12l8.5-6Z"/>';
  static const _comment = '<path d="M4 5.5a1.5 1.5 0 0 1 1.5-1.5h13A1.5 1.5 0 0 1 20 5.5v10a1.5 1.5 0 0 1-1.5 1.5H9l-5 3.5Z"/>|<path d="M8 9h8M8 12.5h5"/>';

  static final Map<IconData, String> _byIcon = {
    Symbols.skip_next_rounded: _skipNext,
    Symbols.skip_previous_rounded: _skipPrev,
    Symbols.fast_forward_rounded: _fastForward,
    Symbols.fast_rewind_rounded: _fastRewind,
    Symbols.replay_10_rounded: _replay10,
    Symbols.forward_10_rounded: _forward10,
    Symbols.replay_5_rounded: _replay,
    Symbols.replay_30_rounded: _replay,
    Symbols.replay_rounded: _replay,
    Symbols.forward_5_rounded: _forward,
    Symbols.forward_30_rounded: _forward,
    Symbols.forward_media_rounded: _forward,
    Symbols.subtitles_rounded: _subtitles,
    Symbols.closed_caption_rounded: _subtitles,
    Symbols.subtitles_off_rounded: _subtitlesOff,
    Symbols.picture_in_picture_alt_rounded: _pip,
    Symbols.call_to_action_rounded: _miniPlayer,
    Symbols.layers_rounded: _layers,
    Symbols.queue_rounded: _playlist,
    Symbols.fiber_manual_record_rounded: _record,
    Symbols.keyboard_arrow_down_rounded: _expandMore,
    Symbols.keyboard_arrow_up_rounded: _expandLess,
    Symbols.bedtime_rounded: _bedtime,
    Symbols.list_rounded: _list,
    Symbols.description_rounded: _description,
    Symbols.thumb_down_rounded: _thumbDown,
    Symbols.comment_rounded: _comment,
    Symbols.theaters_rounded: _theaters,
    Symbols.check_rounded: _check,
    Symbols.notifications_rounded: _bell,
    Symbols.headphones_rounded: _headphones,
    Symbols.done_all_rounded: _doneAll,
    Symbols.clear_all_rounded: _clearAll,
    Symbols.remove_done_rounded: _removeDone,
    Symbols.resume_rounded: _resume,
    Symbols.fit_screen_rounded: _fitScreen,
    Symbols.aspect_ratio_rounded: _aspectRatio,
    Symbols.settings_overscan_rounded: _overscan,
    Symbols.account_box_rounded: _accountBox,
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
    Symbols.looks_one_rounded: _countOnce,
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
    Symbols.add_to_queue_rounded: _addChannel,
    Symbols.timer_rounded: _timer,
    Symbols.bar_chart_rounded: _barChart,
    Symbols.check_circle_rounded: _checkCircle,
    Symbols.pause_circle_rounded: _pauseCircle,
    Symbols.movie_edit_rounded: _clapper,
    Symbols.hourglass_bottom_rounded: _hourglass,
    Symbols.local_fire_department_rounded: _hot,
    Symbols.chrome_reader_mode_rounded: _reader,
    Symbols.text_decrease_rounded: _textSmaller,
    Symbols.text_increase_rounded: _textLarger,
    Symbols.remove_rounded: _remove,
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
    Symbols.dark_mode_rounded: _moon,
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
    Symbols.open_in_new_rounded: _openInNew,
    Symbols.more_vert_rounded: _more,
    Symbols.volume_up_rounded: _volumeUp,
    Symbols.volume_off_rounded: _volumeOff,
    Symbols.pause_rounded: _pause,
    Symbols.shield_rounded: _shield,
  };

  static String? pathsFor(IconData icon) => _byIcon[icon];

  /// Fork: neon tube width, in glyph units (viewBox 24).
  static const double tubeWidth = 1.9;

  static final Map<String, String> _svgCache = {};

  /// [paths] drawn as one flat-coloured stroke of [width].
  static String layer(String paths, String color, double width) => _svgCache.putIfAbsent(
    '$color|$width|$paths',
    () =>
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="$color" '
        'stroke-width="$width" stroke-linecap="round" stroke-linejoin="round">$paths</svg>',
  );
}

/// One neon colour of a [RetroGlyph]: tube, bright core and glow.
class _NeonTone {
  const _NeonTone(this.tube, this.core, this.halo);

  final String tube;
  final String core;
  final String halo;
}

/// One [RetroGlyphs] glyph at [size] (the ambient icon size when null).
/// [opacity] dims it, e.g. for unselected navigation entries.
///
/// Fork: drawn like a neon sign. The main shape is a cyan tube, one accent a
/// magenta tube, each with a faint bright core and a soft glow in its own
/// colour. The glow is skipped on TV, where blur filters cost too much.
class RetroGlyph extends StatelessWidget {
  const RetroGlyph(
    this.paths, {
    super.key,
    this.size,
    this.opacity = 1,
    this.semanticLabel,
    this.glow = true,
    this.soft = false,
  });

  /// Cyan paths and magenta paths, separated by `|`.
  final String paths;
  final double? size;
  final double opacity;
  final String? semanticLabel;

  /// Draw the soft glow (never on TV). Off for small badges in long grids.
  final bool glow;

  /// Calmer variant for the player: pastel tubes, thinner, no glow.
  final bool soft;

  static const _cyan = _NeonTone('#00E5FF', '#F2FCFF', '#0090FF');
  static const _magenta = _NeonTone('#FF2BD0', '#FFE6F8', '#C800E0');
  static const _softCyan = _NeonTone('#7FEFFF', '#F2FCFF', '#0090FF');
  static const _softMagenta = _NeonTone('#FF6FDC', '#FFE6F8', '#C800E0');

  @override
  Widget build(BuildContext context) {
    final s = size ?? IconTheme.of(context).size ?? 24;
    final unit = s / 24;
    final w = soft ? 1.8 : RetroGlyphs.tubeWidth;

    Widget svg(String p, String color, double width, {double alpha = 1}) {
      Widget child = SvgPicture.string(RetroGlyphs.layer(p, color, width), width: s, height: s);
      if (alpha < 1) child = Opacity(opacity: alpha, child: child);
      return child;
    }

    Widget blurred(Widget child, double sigma) => ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
      child: child,
    );

    final split = paths.indexOf('|');
    final parts = <(String, _NeonTone)>[
      (split < 0 ? paths : paths.substring(0, split), soft ? _softCyan : _cyan),
      if (split >= 0) (paths.substring(split + 1), soft ? _softMagenta : _magenta),
    ].where((p) => p.$1.isNotEmpty).toList();

    final glow = this.glow && !soft && !PlatformDetector.isTV();
    Widget glyph = RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (glow)
            for (final (p, tone) in parts) ...[
              blurred(svg(p, tone.halo, w * 2.6, alpha: 0.42), unit * 1.4),
              blurred(svg(p, tone.halo, w * 1.4, alpha: 0.6), unit * 0.5),
            ],
          for (final (p, tone) in parts) ...[
            svg(p, tone.tube, w),
            svg(p, tone.core, w * 0.24, alpha: 0.55),
          ],
        ],
      ),
    );
    glyph = Semantics(label: semanticLabel, image: semanticLabel != null, child: glyph);
    if (opacity < 1) glyph = Opacity(opacity: opacity, child: glyph);
    return SizedBox(width: s, height: s, child: glyph);
  }

  /// The glyph for [icon] when the retrowave theme is active, else null.
  static String? pathsIfActive(BuildContext context, IconData? icon) {
    if (icon == null || !RetroColors.isActive(context)) return null;
    return RetroGlyphs.pathsFor(icon);
  }
}
