import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../retrowave_version.dart';
import '../../utils/app_logger.dart';
import '../base_shared_preferences_service.dart';
import 'dart:convert';

/// A newer fork release on GitHub.
class RetrowaveRelease {
  const RetrowaveRelease({required this.version, required this.name, required this.notes, required this.pageUrl, required this.assets});

  final String version;
  final String name;
  final String notes;
  final String pageUrl;

  /// File name → download URL.
  final Map<String, String> assets;
}

/// How [RetrowaveUpdater.install] can update this copy of the app.
enum RetrowaveUpdateMode {
  /// Windows installed copy: run the new installer, which reopens the app.
  windowsInstaller,

  /// Android: download the APK and open the system install prompt.
  androidApk,

  /// Portable Windows: open the release page.
  releasePage,
}

/// Updates the fork from its own GitHub releases (thetwistedchi/plezy), not
/// from upstream Plezy.
abstract final class RetrowaveUpdater {
  static const _repo = 'thetwistedchi/plezy';
  static const _installerAsset = 'plezy-retrowave-installer.exe';
  static const _arm64Apk = 'plezy-retrowave-arm64.apk';
  static const _universalApk = 'plezy-retrowave-universal.apk';
  static const _keyLastCheck = 'retrowave_update_last_check';
  static const _keySkipped = 'retrowave_update_skipped';
  /// Startup checks run every launch; this only stops a burst of restarts
  /// from asking GitHub again within minutes.
  static const _cooldown = Duration(minutes: 10);

  /// While the app stays open, how often to look again.
  static const recheckInterval = Duration(hours: 6);
  static const _channel = MethodChannel('com.thetwistedchi.plezyretrowave/update');

  static String get currentVersion => retrowaveVersion;

  /// Whether this platform gets update checks at all.
  static bool get isSupported => Platform.isWindows || Platform.isAndroid;

  static RetrowaveUpdateMode get mode {
    if (Platform.isAndroid) return RetrowaveUpdateMode.androidApk;
    if (Platform.isWindows && _isInstalledWindowsCopy()) return RetrowaveUpdateMode.windowsInstaller;
    return RetrowaveUpdateMode.releasePage;
  }

  /// The Inno Setup installer leaves unins000.exe next to plezy.exe; the
  /// portable 7z does not.
  static bool _isInstalledWindowsCopy() {
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      return File('$dir${Platform.pathSeparator}unins000.exe').existsSync();
    } catch (_) {
      return false;
    }
  }

  /// The latest release if it is newer than this build. [manual] ignores the
  /// once-a-day limit and a skipped version, and rethrows failures.
  static Future<RetrowaveRelease?> check({bool manual = false}) async {
    if (!isSupported) return null;
    final prefs = await BaseSharedPreferencesService.sharedCache();
    if (!manual) {
      final last = DateTime.tryParse(prefs.getString(_keyLastCheck) ?? '');
      if (last != null && DateTime.now().difference(last) < _cooldown && !last.isAfter(DateTime.now())) return null;
      await prefs.setString(_keyLastCheck, DateTime.now().toIso8601String());
    }
    try {
      final response = await http
          .get(
            Uri.https('api.github.com', '/repos/$_repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw StateError('GitHub answered ${response.statusCode}');
      final release = _parse(jsonDecode(response.body) as Map<String, dynamic>);
      if (!isNewer(release.version, currentVersion)) return null;
      if (!manual && prefs.getString(_keySkipped) == release.version) return null;
      return release;
    } catch (e, st) {
      appLogger.w('Update check failed', error: e, stackTrace: st);
      if (manual) rethrow;
      return null;
    }
  }

  static RetrowaveRelease _parse(Map<String, dynamic> data) {
    final tag = (data['tag_name'] as String? ?? '').trim();
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    return RetrowaveRelease(
      version: version,
      name: data['name'] as String? ?? 'Plezy Retrowave $version',
      notes: data['body'] as String? ?? '',
      pageUrl: data['html_url'] as String? ?? 'https://github.com/$_repo/releases/latest',
      assets: {
        for (final a in (data['assets'] as List? ?? const []))
          if (a is Map && a['name'] is String && a['browser_download_url'] is String)
            a['name'] as String: a['browser_download_url'] as String,
      },
    );
  }

  static const _keyLastRunVersion = 'retrowave_last_run_version';

  /// Once after the app was updated: this version's release (for its notes).
  /// Null on a fresh install, on later starts, or when GitHub has no release
  /// for this version.
  static Future<RetrowaveRelease?> whatsNewAfterUpdate() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final last = prefs.getString(_keyLastRunVersion);
    if (last == currentVersion) return null;
    await prefs.setString(_keyLastRunVersion, currentVersion);
    if (last == null) return null;
    try {
      final response = await http
          .get(
            Uri.https('api.github.com', '/repos/$_repo/releases/tags/v$currentVersion'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return _parse(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      appLogger.d('What\'s new lookup failed', error: e);
      return null;
    }
  }

  static Future<void> skip(String version) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_keySkipped, version);
  }

  /// `1.10.0` > `1.9.3`; extra parts count as zero.
  static bool isNewer(String candidate, String current) {
    List<int> parts(String v) => [for (final p in v.split('.')) int.tryParse(p.split(RegExp(r'[-+]')).first) ?? 0];
    final a = parts(candidate);
    final b = parts(current);
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Runs the update for [release]. [onProgress] gets 0..1 while downloading.
  /// Returns a short problem description, or null when handed over (on
  /// Windows the app then closes; on Android the install prompt is open).
  static Future<String?> install(RetrowaveRelease release, {void Function(double progress)? onProgress}) async {
    switch (mode) {
      case RetrowaveUpdateMode.releasePage:
        await launchUrl(Uri.parse(release.pageUrl), mode: LaunchMode.externalApplication);
        return null;
      case RetrowaveUpdateMode.windowsInstaller:
        final url = release.assets[_installerAsset];
        if (url == null) return 'missing:$_installerAsset';
        final file = await _download(url, _installerAsset, onProgress);
        // Silent install over this copy; the installer's launch entry reopens
        // the app afterwards. Exit so the files are free to replace.
        await Process.start(file.path, const [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/CLOSEAPPLICATIONS',
        ], mode: ProcessStartMode.detached);
        exit(0);
      case RetrowaveUpdateMode.androidApk:
        final is64 = Platform.version.contains('arm64') || Platform.version.contains('x64');
        final name = is64 && release.assets.containsKey(_arm64Apk) ? _arm64Apk : _universalApk;
        final url = release.assets[name];
        if (url == null) return 'missing:$name';
        final file = await _download(url, name, onProgress);
        final result = await _channel.invokeMethod<String>('installApk', {'path': file.path});
        return result == 'needsPermission' ? 'needsPermission' : null;
    }
  }

  static Future<File> _download(String url, String name, void Function(double)? onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) throw StateError('Download answered ${response.statusCode}');
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }
}
