import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rate_limiter/rate_limiter.dart';

import '../media/video_zoom.dart';
import '../mpv/mpv.dart';

import '../utils/app_logger.dart';
import 'ambient_lighting_service.dart';
import 'settings_service.dart';

/// Manages video filtering, aspect ratio modes, and subtitle positioning for video playback.
///
/// This service handles:
/// - BoxFit mode cycling (contain → cover → fill)
/// - Video cropping calculations for fill screen mode
/// - Subtitle positioning adjustments based on crop parameters
/// - Debounced video filter updates on resize events
/// - Ambient-lighting-friendly reset to contain mode
class VideoFilterManager {
  static const double zoomStep = 0.01;

  /// How close a pinch has to get to 100%, in whole percent, before it snaps
  /// there exactly.
  ///
  /// [normalizeZoomScale] rounds to whole percent, so an unaided pinch has to
  /// land inside half a percent of 1.0 to undo itself — in practice it leaves
  /// the picture at 99% or 101% and the viewer cannot tell why it still looks
  /// cropped. A detent makes the pinch a reliable inverse of itself.
  ///
  /// Deliberately applied to the pinch handler only, never inside
  /// [normalizeZoomScale]: [zoomStep] is 1%, so a global detent would trap the
  /// keyboard and slider paths at 1.0 with no way to step out.
  static const int pinchZoomResetDetentPercent = 3;

  /// Snaps a pinch-derived [scale] to exactly 1.0 inside the detent.
  ///
  /// Compared in whole percent like [normalizeZoomScale], not in raw doubles:
  /// `(0.97 - 1.0).abs()` is 0.030000000000000027, so a float comparison against
  /// a 0.03 band drops the very boundary it is meant to include.
  static double snapPinchZoomScale(double scale) {
    final percent = (scale * 100).round();
    return (percent - 100).abs() <= pinchZoomResetDetentPercent ? 1.0 : scale;
  }

  final Player player;

  /// Whether [Player.setVideoZoom] scales the native video layer itself, so
  /// the mpv `video-zoom` property must stay 0. On iOS/tvOS/macOS the avfoundation
  /// VO re-renders zoomed frames through Core Image, which destroys HDR and
  /// Dolby Vision passthrough — zoom must stay out of mpv's pipeline there.
  final bool nativeVideoZoom;

  /// BoxFit mode state: 0=contain (letterbox), 1=cover (fill screen), 2=fill (stretch)
  int _boxFitMode;

  /// Store the boxFitMode before entering PiP so it can be restored
  int? _prePipBoxFitMode;

  /// Store the zoom level before entering PiP so it can be restored
  double? _prePipZoomScale;

  /// Store whether ambient lighting was active before entering PiP
  bool? _prePipAmbientLighting;

  /// Ambient lighting service reference, disabled for PiP and restored after it.
  AmbientLightingService? ambientLightingService;

  /// Custom video zoom layered on top of the selected fit mode.
  double _zoomScale;

  /// Current player viewport size
  Size? _playerSize;

  /// Debounced video filter update with leading edge execution
  late final Debounce _debouncedUpdateVideoFilter;

  /// Last values actually written to the player. A missing key means unknown,
  /// so the next run rewrites it.
  final Map<String, String> _appliedProps = {};
  int? _appliedBoxFitMode;
  double? _appliedVideoZoom;

  /// In-progress update loop; concurrent callers mark it dirty and share it.
  Future<void>? _updateLoop;
  bool _updateDirty = false;

  /// Callback invoked when boxFitMode changes, for external persistence
  final void Function(int mode)? onBoxFitModeChanged;

  VideoFilterManager({
    required this.player,
    this.nativeVideoZoom = false,
    int initialBoxFitMode = 0,
    double initialZoomScale = 1.0,
    Size? initialPlayerSize,
    this.onBoxFitModeChanged,
    bool cropLetterbox = false,
  }) : _boxFitMode = _keepAspect(initialBoxFitMode),
       // ignore: prefer_initializing_formals, a public name for the private field
       _cropLetterbox = cropLetterbox,
       _canCrop = Platform.isWindows || Platform.isLinux,
       _zoomScale = normalizeZoomScale(initialZoomScale),
       _playerSize = initialPlayerSize {
    _debouncedUpdateVideoFilter = debounce(
      updateVideoFilter,
      const Duration(milliseconds: 50),
      leading: true,
      trailing: true,
    );
    _aspectFileSub = player.streams.fileLoaded.listen((_) => _videoAspect = null);
    _aspectRestartSub = player.streams.playbackRestart.listen((_) {
      _lastRestart = DateTime.now();
      unawaited(_readVideoAspect());
    });
    if (Platform.isWindows) {
      _hdrBrightness = SettingsService.instanceOrNull?.listenable(SettingsService.hdrBrightness);
      _hdrBrightness?.addListener(updateVideoFilter);
      _hdrFileSub = player.streams.fileLoaded.listen((_) => _isHdr = false);
      _hdrRestartSub = player.streams.playbackRestart.listen((_) => unawaited(_checkHdr()));
    }
    if (_canCrop) {
      _fileLoadedSub = player.streams.fileLoaded.listen((_) => _resetLetterbox());
      _positionSub = player.streams.position.listen(_onPosition);
    }
  }

  /// Retrowave keeps the aspect ratio: the stretching fill mode (2) is gone,
  /// and a stored 2 reads as contain.
  static int _keepAspect(int mode) => mode == 1 ? 1 : 0;

  // ---- Fit height ----
  //
  // Mode 1 fills the screen's height and never cuts the top or bottom: a
  // picture wider than the screen is zoomed until it is as tall as the screen
  // (the sides are cut); a narrower one already is (bars at the sides).

  StreamSubscription<void>? _aspectFileSub;
  StreamSubscription<void>? _aspectRestartSub;
  double? _videoAspect;

  Future<void> _readVideoAspect() async {
    try {
      final aspect = double.tryParse(await player.getProperty('video-params/aspect') ?? '');
      if (aspect == null || !aspect.isFinite || aspect <= 0 || aspect == _videoAspect) return;
      _videoAspect = aspect;
      if (_boxFitMode == 1) unawaited(updateVideoFilter());
    } catch (_) {}
  }

  /// Zoom factor that makes the (cropped) picture as tall as the player.
  double _fitHeightZoom(Size? playerSize) {
    var aspect = _videoAspect;
    final crop = RegExp(r'^(\d+)x(\d+)').firstMatch(_letterboxCrop);
    final sourceW = _cropSourceWidth;
    final sourceH = _cropSourceHeight;
    // Fork: without video-crop (older libmpv), zoom until the picture inside
    // the bars is as tall as the player; the bars end up off screen.
    if (!_cropSupported && aspect != null && crop != null && sourceH != null && sourceH > 0) {
      if (playerSize == null || playerSize.width <= 0 || playerSize.height <= 0) return 1.0;
      final h = int.parse(crop.group(2)!);
      final playerAspect = playerSize.width / playerSize.height;
      final frameHeight = aspect > playerAspect ? playerAspect / aspect : 1.0;
      final contentHeight = frameHeight * h / sourceH;
      return contentHeight > 0 ? math.max(1.0, 1 / contentHeight) : 1.0;
    }
    if (aspect != null && crop != null && sourceW != null && sourceH != null) {
      // The display aspect of the whole frame, reshaped by the crop.
      final w = int.parse(crop.group(1)!);
      final h = int.parse(crop.group(2)!);
      if (w > 0 && h > 0) aspect = aspect * (w / sourceW) / (h / sourceH);
    }
    if (aspect == null || playerSize == null || playerSize.width <= 0 || playerSize.height <= 0) return 1.0;
    final playerAspect = playerSize.width / playerSize.height;
    return aspect > playerAspect ? aspect / playerAspect : 1.0;
  }

  // ---- HDR brightness ----
  //
  // Windows: HDR (PQ/HLG) video gets mpv's gamma lifted by the HDR
  // brightness setting, which brightens the midtones that PQ masters keep dim
  // for dark rooms. SDR video is left alone.

  ValueNotifier<int>? _hdrBrightness;
  StreamSubscription<void>? _hdrFileSub;
  StreamSubscription<void>? _hdrRestartSub;
  bool _isHdr = false;

  Future<void> _checkHdr() async {
    try {
      final gamma = await player.getProperty('video-params/gamma');
      final hdr = gamma == 'pq' || gamma == 'hlg';
      if (hdr == _isHdr) return;
      _isHdr = hdr;
      unawaited(updateVideoFilter());
    } catch (_) {}
  }

  /// mpv `gamma` for the current video: 0 to +40 for HDR, 0 otherwise.
  String get _hdrGamma {
    final level = (_hdrBrightness?.value ?? 0).clamp(0, 100);
    return _isHdr && level > 0 ? (level * 0.4).round().toString() : '0';
  }

  // ---- Letterbox crop ----
  //
  // With [_cropLetterbox] on, a few seconds into each file the cropdetect
  // filter samples the picture; black bars baked into the video are then
  // cropped with `video-crop`, so a 2.39:1 film fills an ultrawide screen.
  // Contain mode only: cover and zoom already fill.

  /// The setting: crop black bars in Fit mode too. Fit height always does.
  final bool _cropLetterbox;
  final bool _canCrop;

  bool get _wantsCrop => _canCrop && (_cropLetterbox || _boxFitMode == 1);

  bool _aspectReading = false;

  void _onPosition(Duration position) {
    // playbackRestart is not reported by every backend: read the aspect
    // from the first position update too.
    if (_videoAspect == null && !_aspectReading && position > Duration.zero) {
      _aspectReading = true;
      unawaited(_readVideoAspect().whenComplete(() => _aspectReading = false));
    }
    _maybeDetectLetterbox(position);
  }
  StreamSubscription<void>? _fileLoadedSub;
  StreamSubscription<Duration>? _positionSub;
  bool _letterboxChecked = false;
  bool _cropSupported = true;
  DateTime? _lastRestart;
  DateTime? _letterboxRetryAt;
  bool _letterboxRechecked = false;
  _Box? _letterboxContent;
  bool _letterboxDetecting = false;
  String _letterboxCrop = '';
  int? _cropSourceWidth;
  int? _cropSourceHeight;


  void _resetLetterbox() {
    _letterboxChecked = false;
    _letterboxRetryAt = null;
    _letterboxRechecked = false;
    _letterboxContent = null;
    if (_letterboxCrop.isEmpty) return;
    _letterboxCrop = '';
    updateVideoFilter();
  }

  void _maybeDetectLetterbox(Duration position) {
    if (!_wantsCrop || _letterboxDetecting) return;
    if (!_letterboxChecked) {
      // Past studio logos and black openings (switching to Fit height later
      // in a film checks on the next position update).
      if (position < const Duration(seconds: 10)) return;
      // Fork: an all-dark sample is tried again a little later.
      if (_letterboxRetryAt case final at? when DateTime.now().isBefore(at)) return;
      // Fork: not right after a seek or a resume, when mpv may not have a
      // frame to take a screenshot of yet.
      if (_lastRestart case final at? when DateTime.now().difference(at) < const Duration(seconds: 2)) return;
      _letterboxDetecting = true;
      appLogger.d('Letterbox detection: sampling at $position');
      unawaited(_detectLetterbox());
    } else if (!_letterboxRechecked &&
        !_cropSupported &&
        _letterboxCrop.isNotEmpty &&
        position >= const Duration(minutes: 5)) {
      // Fork: only without video-crop. With it, mpv's screenshots are already
      // cropped, so the second look saw no bars and dropped the crop.
      // A second look, which can only shrink the crop.
      _letterboxDetecting = true;
      unawaited(_detectLetterbox(recheck: true));
    }
  }

  /// Finds black bars from a few screenshots of the video (no filter: the
  /// cropdetect filter cannot take hardware-decoded frames, and switching the
  /// decoder to copy mode would stutter). Each shot is decoded small and
  /// scanned for dark rows and columns; the content box is the union over all
  /// shots, so one dark scene does not crop real picture.
  ///
  /// Bars are taken as symmetric: top and bottom (and left and right) are
  /// both cut by the smaller of the two, so a dark sky at the top alone
  /// crops nothing. With [recheck] (minutes into the film) the crop can only
  /// shrink: the new picture area is joined with the current one.
  Future<void> _detectLetterbox({bool recheck = false}) async {
    var sampledDark = false;
    try {
      final width = int.tryParse(await player.getProperty('width') ?? '');
      final height = int.tryParse(await player.getProperty('height') ?? '');
      if (width == null || height == null || width <= 0 || height <= 0) return;

      var content = await _sampleContent();
      if (content == null) {
        // Fork: every shot was dark (a night scene, a fade): look again in
        // 20 s instead of giving up for the whole file.
        if (!recheck) sampledDark = true;
        appLogger.d('Letterbox detection: only dark frames, trying again shortly');
        return;
      }
      // Symmetric bars: the smaller side decides.
      final vertical = math.min(content.top, 1 - content.bottom);
      final horizontal = math.min(content.left, 1 - content.right);
      content = _Box(horizontal, vertical, 1 - horizontal, 1 - vertical);
      if (recheck && _letterboxContent != null) content = content.union(_letterboxContent!);

      var crop = '';
      // Only clear bars count: at least 4 % of the height or the width.
      if (vertical * 2 >= 0.04 || horizontal * 2 >= 0.04) {
        int even(double v) => (v / 2).round() * 2;
        final x = even(content.left * width);
        final y = even(content.top * height);
        final w = even((content.right - content.left) * width);
        final h = even((content.bottom - content.top) * height);
        if (w > width / 2 && h > height / 2 && (w < width || h < height)) crop = '${w}x$h+$x+$y';
      }
      if (recheck && crop.isEmpty && _letterboxCrop.isEmpty) return;
      _letterboxContent = crop.isEmpty ? null : content;
      _cropSourceWidth = width;
      _cropSourceHeight = height;
      appLogger.d(
        'Letterbox ${recheck ? 'recheck' : 'detection'}: ${crop.isEmpty ? 'none' : crop} (video ${width}x$height)',
      );
      if (crop != _letterboxCrop) {
        _letterboxCrop = crop;
        unawaited(updateVideoFilter());
      }
    } catch (e) {
      appLogger.w('Letterbox detection failed, trying again shortly', error: e);
      if (!recheck) sampledDark = true;
    } finally {
      if (recheck) {
        _letterboxRechecked = true;
      } else if (sampledDark) {
        _letterboxRetryAt = DateTime.now().add(const Duration(seconds: 20));
      } else {
        _letterboxChecked = true;
        _letterboxRetryAt = null;
      }
      _letterboxDetecting = false;
    }
  }

  /// The picture area over three cheap screenshots 1.5 s apart, or null.
  Future<_Box?> _sampleContent() async {
    final dir = await getTemporaryDirectory();
    // Cheap shots: low JPEG quality, no high bit depth. The user's own
    // screenshot settings are put back afterwards.
    const cheap = {'screenshot-format': 'jpg', 'screenshot-jpeg-quality': '40', 'screenshot-high-bit-depth': 'no'};
    final saved = <String, String>{};
    for (final MapEntry(:key, :value) in cheap.entries) {
      try {
        final old = await player.getProperty(key);
        if (old != null) saved[key] = old;
        await player.setProperty(key, value);
      } catch (_) {}
    }
    _Box? content;
    try {
      for (var shot = 0; shot < 3; shot++) {
        if (shot > 0) await Future<void>.delayed(const Duration(milliseconds: 1500));
        final file = File(p.join(dir.path, 'plezy_letterbox_$shot.jpg'));
        try {
          await player.command(['screenshot-to-file', file.path, 'video']);
          if (!await file.exists()) continue;
          final box = await _contentBox(await file.readAsBytes());
          if (box != null) content = content == null ? box : content.union(box);
        } finally {
          if (await file.exists()) unawaited(file.delete().catchError((_) => file));
        }
      }
    } finally {
      for (final MapEntry(:key, :value) in saved.entries) {
        try {
          await player.setProperty(key, value);
        } catch (_) {}
      }
    }
    return content;
  }

  /// The non-black area of one screenshot, as fractions of its size, or null
  /// for a frame that is (nearly) all dark.
  static Future<_Box?> _contentBox(Uint8List bytes) async {
    const scanWidth = 320;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: scanWidth);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final w = image.width;
      final h = image.height;
      final px = data.buffer.asUint8List();
      // A pixel is picture when brighter than this (0-255 luma).
      const threshold = 28;
      bool bright(int x, int y) {
        final o = (y * w + x) * 4;
        final luma = (px[o] * 299 + px[o + 1] * 587 + px[o + 2] * 114) ~/ 1000;
        return luma > threshold;
      }

      // A row or column is picture when more than 1 % of it is bright.
      bool rowLit(int y) {
        var n = 0;
        for (var x = 0; x < w; x++) {
          if (bright(x, y) && ++n > w ~/ 100) return true;
        }
        return false;
      }

      bool colLit(int x) {
        var n = 0;
        for (var y = 0; y < h; y++) {
          if (bright(x, y) && ++n > h ~/ 100) return true;
        }
        return false;
      }

      var top = 0;
      while (top < h && !rowLit(top)) {
        top++;
      }
      if (top >= h) return null;
      var bottom = h - 1;
      while (bottom > top && !rowLit(bottom)) {
        bottom--;
      }
      var left = 0;
      while (left < w && !colLit(left)) {
        left++;
      }
      var right = w - 1;
      while (right > left && !colLit(right)) {
        right--;
      }
      return _Box(left / w, top / h, (right + 1) / w, (bottom + 1) / h);
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  /// Current BoxFit mode (0=contain, 1=cover; fill is not offered)
  int get boxFitMode => _boxFitMode;

  double get zoomScale => _zoomScale;

  Size? get playerSize => _playerSize;

  static double normalizeZoomScale(double scale) {
    final clamped = scale.clamp(minimumVideoZoom, maximumVideoZoom).toDouble();
    final percent = (clamped * 100).round();
    if (percent == 100) return 1.0;
    return percent / 100;
  }

  static double videoZoomPropertyForScale(double scale) {
    final normalized = normalizeZoomScale(scale);
    if (normalized == 1.0) return 0.0;
    return math.log(normalized) / math.ln2;
  }

  double setZoomScale(double scale) {
    final next = normalizeZoomScale(scale);
    if (_zoomScale == next) return _zoomScale;
    _zoomScale = next;
    updateVideoFilter();
    return _zoomScale;
  }

  /// Cycle through BoxFit modes: contain → cover → fill → contain (for button)
  void cycleBoxFitMode() {
    _boxFitMode = (_boxFitMode + 1) % 2;
    _lookAgainForBars();
    onBoxFitModeChanged?.call(_boxFitMode);
    updateVideoFilter();
  }

  /// Apply an externally resolved BoxFit mode (scoped-preference re-resolution
  /// on an in-place item change). Does not fire [onBoxFitModeChanged]: the
  /// value came from the store, so echoing it back would be redundant.
  void setBoxFitMode(int mode) {
    final next = _keepAspect(mode);
    if (_boxFitMode == next) return;
    _boxFitMode = next;
    _lookAgainForBars();
    updateVideoFilter();
  }

  /// Fork: switching to Fit height without a crop looks for bars again on
  /// the next position update (the earlier look may have found none).
  void _lookAgainForBars() {
    if (_boxFitMode != 1 || _letterboxCrop.isNotEmpty || _letterboxDetecting) return;
    _letterboxChecked = false;
    _letterboxRetryAt = null;
  }

  /// Reset to contain mode (mode 0). Used when enabling ambient lighting.
  void resetToContain() {
    if (_boxFitMode != 0 || (_zoomScale - 1.0).abs() > 0.0001) {
      _boxFitMode = 0;
      _zoomScale = 1.0;
      updateVideoFilter();
    }
  }

  /// Force contain mode for PiP (no cropping/stretching)
  void enterPipMode() {
    // Disable ambient lighting for PiP — it wastes space on blurred borders
    if (ambientLightingService?.isEnabled == true) {
      _prePipAmbientLighting = true;
      ambientLightingService!.disable();
    }
    if (_boxFitMode != 0) {
      _prePipBoxFitMode = _boxFitMode;
      _boxFitMode = 0; // Contain mode
    }
    if ((_zoomScale - 1.0).abs() > 0.0001) {
      _prePipZoomScale = _zoomScale;
      _zoomScale = 1.0;
    }
    if (_prePipBoxFitMode != null || _prePipZoomScale != null) {
      updateVideoFilter();
    }
  }

  /// Restore previous mode when exiting PiP
  void exitPipMode() {
    var shouldUpdate = false;
    if (_prePipBoxFitMode != null) {
      _boxFitMode = _prePipBoxFitMode!;
      _prePipBoxFitMode = null;
      shouldUpdate = true;
    }
    if (_prePipZoomScale != null) {
      _zoomScale = normalizeZoomScale(_prePipZoomScale!);
      _prePipZoomScale = null;
      shouldUpdate = true;
    }
    if (shouldUpdate) updateVideoFilter();
  }

  /// Whether ambient lighting was active before entering PiP
  bool get hadAmbientLightingBeforePip => _prePipAmbientLighting == true;

  void clearPipAmbientLightingFlag() {
    _prePipAmbientLighting = null;
  }

  void updatePlayerSize(Size size) {
    // Check if size actually changed to avoid unnecessary updates
    if (_playerSize == null ||
        (_playerSize!.width - size.width).abs() > 0.1 ||
        (_playerSize!.height - size.height).abs() > 0.1) {
      _playerSize = size;
      debouncedUpdateVideoFilter();
    }
  }

  /// Update the video scaling and positioning based on current display mode.
  /// Writes are diffed against the last applied values and serialized: while a
  /// run is in flight, further calls coalesce into one trailing re-run instead
  /// of interleaving stale writes (pinch zoom calls this per gesture tick).
  /// Owns `video-aspect-override` (the stretch of fill mode); ambient lighting
  /// fills through `keepaspect` instead and never writes it.
  Future<void> updateVideoFilter() {
    final running = _updateLoop;
    if (running != null) {
      _updateDirty = true;
      return running;
    }
    final loop = _runUpdateLoop();
    _updateLoop = loop;
    return loop;
  }

  Future<void> _runUpdateLoop() async {
    try {
      do {
        _updateDirty = false;
        await _applyVideoFilter();
      } while (_updateDirty);
    } finally {
      _updateLoop = null;
    }
  }

  Future<void> _applyVideoFilter() async {
    try {
      final boxFitMode = _boxFitMode;
      final zoomScale = _zoomScale;
      final playerSize = _playerSize;
      final coverMode = boxFitMode == 1;

      // ExoPlayer handles scaling via AspectRatioFrameLayout (no-op on mpv
      // backends). The MPV properties below still run — on ExoPlayer they
      // forward to setMpvProperty, which queues them for any future fallback.
      if (_appliedBoxFitMode != boxFitMode) {
        _appliedBoxFitMode = null;
        await player.setBoxFitMode(boxFitMode);
        _appliedBoxFitMode = boxFitMode;
      }
      if (_appliedVideoZoom != zoomScale) {
        _appliedVideoZoom = null;
        await player.setVideoZoom(zoomScale);
        _appliedVideoZoom = zoomScale;
      }

      // Compute final target values up-front: each mpv write takes effect
      // immediately, so transient intermediate values would flash on screen.
      var aspectOverride = 'no';
      if (boxFitMode == 2) {
        // Fill/stretch mode - override aspect ratio to match player (stretches video)
        if (playerSize != null && playerSize.width > 0 && playerSize.height > 0) {
          final playerAspect = playerSize.width / playerSize.height;
          if (playerAspect.isFinite && playerAspect > 0) {
            aspectOverride = playerAspect.toString();
            appLogger.d('Stretch mode: aspect-override=$playerAspect (player: $playerSize)');
          }
        }
      }

      await _applyProperty('video-aspect-override', aspectOverride);
      await _applyProperty('sub-ass-force-margins', coverMode || zoomScale > 1.0001 ? 'yes' : 'no');
      if (nativeVideoZoom) {
        await _applyProperty('panscan', coverMode ? '1.0' : '0');
        await _applyProperty('video-zoom', '0.0');
      } else {
        // Fit height (see above) instead of panscan, which also cut the top
        // and bottom on ultrawide screens.
        final fitZoom = coverMode ? _fitHeightZoom(playerSize) : 1.0;
        if (coverMode) {
          appLogger.d('Fit height: zoom=$fitZoom aspect=$_videoAspect crop=$_letterboxCrop player=${playerSize == null ? 'none' : '${playerSize.width.round()}x${playerSize.height.round()}'}');
        }
        await _applyProperty('panscan', '0');
        await _applyProperty(
          'video-zoom',
          (videoZoomPropertyForScale(zoomScale) + math.log(fitZoom) / math.ln2).toStringAsFixed(4),
        );
      }
      if (_hdrBrightness != null) await _applyProperty('gamma', _hdrGamma);
      // Last: older libmpv builds have no video-crop and refuse it.
      if (_canCrop && _cropSupported) {
        try {
          await _applyProperty('video-crop', _wantsCrop && zoomScale <= 1.0001 ? _letterboxCrop : '');
        } catch (e) {
          // Fork: fall back to zooming past the bars (see _fitHeightZoom).
          appLogger.w('video-crop not supported, Fit height zooms past the bars instead', error: e);
          _cropSupported = false;
          if (_boxFitMode == 1) unawaited(updateVideoFilter());
        }
      }
    } catch (e) {
      appLogger.w('Failed to update video filter', error: e);
    }
  }

  Future<void> _applyProperty(String name, String value) async {
    if (_appliedProps[name] == value) return;
    // Uncache while in flight so a failed write is retried on the next run.
    _appliedProps.remove(name);
    await player.setProperty(name, value);
    _appliedProps[name] = value;
  }

  /// Debounced version of updateVideoFilter for resize events.
  /// Uses leading-edge debounce: first call executes immediately,
  /// subsequent calls within 50ms are debounced.
  void debouncedUpdateVideoFilter() => _debouncedUpdateVideoFilter();

  void dispose() {
    _debouncedUpdateVideoFilter.cancel();
    unawaited(_fileLoadedSub?.cancel());
    unawaited(_aspectFileSub?.cancel());
    unawaited(_aspectRestartSub?.cancel());
    _hdrBrightness?.removeListener(updateVideoFilter);
    unawaited(_hdrFileSub?.cancel());
    unawaited(_hdrRestartSub?.cancel());
    unawaited(_positionSub?.cancel());
  }
}

/// A rectangle in fractions of a frame.
class _Box {
  const _Box(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  _Box union(_Box o) => _Box(
    math.min(left, o.left),
    math.min(top, o.top),
    math.max(right, o.right),
    math.max(bottom, o.bottom),
  );
}
