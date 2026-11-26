import 'dart:async';

import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/retro_strings.dart';
import '../../media/media_hub.dart';
import '../../widgets/media_context_menu.dart' show MediaMenuExtraEntry;
import '../settings_service.dart';

/// Fork: a card design per Home row (poster, wide backdrop, small posters),
/// chosen in the row's card menu.
class HomeRowStyles {
  HomeRowStyles._();

  static String rowKey(MediaHub hub) => '${hub.serverId ?? ''}:${hub.identifier ?? hub.id}';

  static HomeRowCardStyle styleFor(MediaHub hub) {
    final key = '${rowKey(hub)}=';
    for (final entry in SettingsService.instance.read(SettingsService.homeRowCardStyles)) {
      if (entry.startsWith(key)) {
        final name = entry.substring(key.length);
        return HomeRowCardStyle.values.firstWhere((s) => s.name == name, orElse: () => HomeRowCardStyle.standard);
      }
    }
    return HomeRowCardStyle.standard;
  }

  static Future<void> setStyle(MediaHub hub, HomeRowCardStyle style) {
    final key = '${rowKey(hub)}=';
    final svc = SettingsService.instance;
    final next = [
      for (final entry in svc.read(SettingsService.homeRowCardStyles))
        if (!entry.startsWith(key)) entry,
      if (style != HomeRowCardStyle.standard) '$key${style.name}',
    ];
    return svc.write(SettingsService.homeRowCardStyles, next);
  }

  static String label(HomeRowCardStyle style) => switch (style) {
    HomeRowCardStyle.standard => RetroStrings.rowStyleStandard,
    HomeRowCardStyle.poster => RetroStrings.rowStylePoster,
    HomeRowCardStyle.wide => RetroStrings.rowStyleWide,
    HomeRowCardStyle.small => RetroStrings.rowStyleSmall,
  };

  /// Card menu entry: switches the row to the next design and names it.
  static MediaMenuExtraEntry menuEntry(MediaHub hub) {
    final current = styleFor(hub);
    final next = HomeRowCardStyle.values[(current.index + 1) % HomeRowCardStyle.values.length];
    return MediaMenuExtraEntry(
      icon: switch (next) {
        HomeRowCardStyle.standard => Symbols.view_agenda_rounded,
        HomeRowCardStyle.poster => Symbols.view_column_rounded,
        HomeRowCardStyle.wide => Symbols.view_carousel_rounded,
        HomeRowCardStyle.small => Symbols.view_module_rounded,
      },
      label: RetroStrings.rowCardStyle(label(next)),
      onSelected: () => unawaited(setStyle(hub, next)),
    );
  }
}
