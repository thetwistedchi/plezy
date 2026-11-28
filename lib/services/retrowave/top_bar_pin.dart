import '../settings_service.dart';

/// Fork: whether the top bar of libraries (and YouTube) stays visible while
/// scrolling. An app-wide setting, which a library can override.
abstract final class TopBarPin {
  static bool get appDefault => SettingsService.instance.read(SettingsService.pinTopBar);

  /// The library's own choice, or null when it follows the app setting.
  static bool? overrideFor(String libraryKey) {
    for (final entry in SettingsService.instance.read(SettingsService.pinTopBarLibraries)) {
      final i = entry.lastIndexOf('|');
      if (i > 0 && entry.substring(0, i) == libraryKey) return entry.substring(i + 1) == '1';
    }
    return null;
  }

  static bool forLibrary(String? libraryKey) =>
      (libraryKey == null ? null : overrideFor(libraryKey)) ?? appDefault;

  static Future<void> setOverride(String libraryKey, bool? pinned) async {
    final entries = [
      for (final entry in SettingsService.instance.read(SettingsService.pinTopBarLibraries))
        if (!entry.startsWith('$libraryKey|')) entry,
      if (pinned != null) '$libraryKey|${pinned ? 1 : 0}',
    ];
    await SettingsService.instance.write(SettingsService.pinTopBarLibraries, entries);
  }
}
