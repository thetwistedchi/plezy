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

  RetrowaveRelease withNotes(String notes) =>
      RetrowaveRelease(version: version, name: name, notes: notes, pageUrl: pageUrl, assets: assets);
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

  /// The version the last install handed over to the installer.
  static const _keyAttempted = 'retrowave_update_attempted';
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
      // Installed before, yet this build is still older: that release's
      // files are not the version they claim. Offering it again on every
      // start would loop; Check for updates still offers it.
      if (!manual && prefs.getString(_keyAttempted) == release.version) {
        appLogger.w('Update to ${release.version} was installed but this build is still $currentVersion');
        return null;
      }
      // Several releases since this build: show all their notes.
      return release.withNotes(await _notesSince(currentVersion, release));
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
    // The installer or APK of the update that brought this version is done.
    unawaited(_deleteDownloads());
    if (last == null) return null;
    try {
      final response = await http
          .get(
            Uri.https('api.github.com', '/repos/$_repo/releases/tags/v$currentVersion'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final release = _parse(jsonDecode(response.body) as Map<String, dynamic>);
      // Updated across several releases: what is new in all of them.
      return release.withNotes(await _notesSince(last, release));
    } catch (e) {
      appLogger.d('What\'s new lookup failed', error: e);
      return null;
    }
  }

  /// This version's own release, for its notes; null when offline or when
  /// GitHub has no release for it.
  static Future<RetrowaveRelease?> currentRelease() async {
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
      appLogger.d('Release notes lookup failed', error: e);
      return null;
    }
  }

  /// The notes of every release after [installed] up to [target], newest
  /// first, each under its version as a heading. Only [target]'s own notes
  /// when it is the only one, or when the list cannot be read.
  static Future<String> _notesSince(String installed, RetrowaveRelease target) async {
    try {
      final response = await http
          .get(
            Uri.https('api.github.com', '/repos/$_repo/releases', {'per_page': '30'}),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return target.notes;
      final releases = [
        for (final r in jsonDecode(response.body) as List)
          if (r is Map<String, dynamic> && r['draft'] != true && r['prerelease'] != true) _parse(r),
      ].where((r) => isNewer(r.version, installed) && !isNewer(r.version, target.version)).toList()
        ..sort((a, b) => isNewer(a.version, b.version) ? -1 : (isNewer(b.version, a.version) ? 1 : 0));
      if (releases.length <= 1) return target.notes;
      return [for (final r in releases) _withVersionHeading(r)].join('\n\n');
    } catch (e) {
      appLogger.d('Release list unavailable', error: e);
      return target.notes;
    }
  }

  /// A release's notes with `## <version>` as its first line, in place of
  /// its `## Plezy Retrowave <version>` title.
  static String _withVersionHeading(RetrowaveRelease release) {
    final lines = release.notes.trim().split(RegExp(r'\r?\n'));
    if (lines.isNotEmpty && lines.first.trimLeft().startsWith('## Plezy Retrowave')) lines.removeAt(0);
    return ['## ${release.version}', ...lines].join('\n').trim();
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
        // Remembered so a release whose files are older than they claim is
        // not offered on every start (Android's prompt can be cancelled, so
        // only here).
        final prefs = await BaseSharedPreferencesService.sharedCache();
        await prefs.setString(_keyAttempted, release.version);
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

  static Future<void> _deleteDownloads() async {
    try {
      final dir = await getTemporaryDirectory();
      for (final name in [_arm64Apk, _universalApk, _installerAsset]) {
        final file = File('${dir.path}${Platform.pathSeparator}$name');
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      appLogger.d('Could not remove old update downloads', error: e);
    }
  }

  static Future<File> _download(String url, String name, void Function(double)? onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    final client = http.Client();
    try {
      // A stalled connection fails instead of leaving the dialog busy forever.
      final response = await client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw StateError('Download answered ${response.statusCode}');
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      // A cut-off download must not be handed to the installer.
      if (total > 0 && received != total) throw StateError('Download incomplete ($received of $total bytes)');
      return file;
    } finally {
      client.close();
    }
  }
}
