import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
       _cropLetterbox = cropLetterbox && (Platform.isWindows || Platform.isLinux),
       _zoomScale = normalizeZoomScale(initialZoomScale),
       _playerSize = initialPlayerSize {
    _debouncedUpdateVideoFilter = debounce(
      updateVideoFilter,
      const Duration(milliseconds: 50),
      leading: true,
      trailing: true,
    );
    _aspectFileSub = player.streams.fileLoaded.listen((_) => _videoAspect = null);
    _aspectRestartSub = player.streams.playbackRestart.listen((_) => unawaited(_readVideoAspect()));
    if (Platform.isWindows) {
      _hdrBrightness = SettingsService.instanceOrNull?.listenable(SettingsService.hdrBrightness);
      _hdrBrightness?.addListener(updateVideoFilter);
      _hdrFileSub = player.streams.fileLoaded.listen((_) => _isHdr = false);
      _hdrRestartSub = player.streams.playbackRestart.listen((_) => unawaited(_checkHdr()));
    }
    if (_cropLetterbox) {
      _fileLoadedSub = player.streams.fileLoaded.listen((_) => _resetLetterbox());
      _positionSub = player.streams.position.listen(_maybeDetectLetterbox);
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
      if (_boxFitMode == 1) updateVideoFilter();
    } catch (_) {}
  }

  /// Zoom factor that makes the (cropped) picture as tall as the player.
  double _fitHeightZoom(Size? playerSize) {
    var aspect = _videoAspect;
    final crop = RegExp(r'^(\d+)x(\d+)').firstMatch(_letterboxCrop);
    final sourceW = _cropSourceWidth;
    final sourceH = _cropSourceHeight;
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
      updateVideoFilter();
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

  final bool _cropLetterbox;
  StreamSubscription<void>? _fileLoadedSub;
  StreamSubscription<Duration>? _positionSub;
  bool _letterboxChecked = false;
  bool _letterboxDetecting = false;
  String _letterboxCrop = '';
  int? _cropSourceWidth;
  int? _cropSourceHeight;

  static const _cropLabel = 'plezycrop';

  void _resetLetterbox() {
    _letterboxChecked = false;
    if (_letterboxCrop.isEmpty) return;
    _letterboxCrop = '';
    updateVideoFilter();
  }

  void _maybeDetectLetterbox(Duration position) {
    if (_letterboxChecked || _letterboxDetecting) return;
    // Past studio logos and black openings.
    if (position < const Duration(seconds: 10)) return;
    _letterboxDetecting = true;
    unawaited(_detectLetterbox());
  }

  Future<void> _detectLetterbox() async {
    var filterAdded = false;
    try {
      final width = int.tryParse(await player.getProperty('width') ?? '');
      final height = int.tryParse(await player.getProperty('height') ?? '');
      if (width == null || height == null || width <= 0 || height <= 0) return;
      await player.command(['vf', 'add', '@$_cropLabel:cropdetect=limit=24:round=2:reset=0']);
      filterAdded = true;
      await Future<void>.delayed(const Duration(seconds: 2));
      Future<int?> meta(String key) async =>
          int.tryParse(await player.getProperty('vf-metadata/$_cropLabel/lavfi.cropdetect.$key') ?? '');
      final w = await meta('w');
      final h = await meta('h');
      final x = await meta('x');
      final y = await meta('y');
      var crop = '';
      if (w != null && h != null && x != null && y != null && w > width / 2 && h > height / 2) {
        // Only clear bars count: at least 4 % of the height or the width.
        final bars = (height - h) >= height * 0.04 || (width - w) >= width * 0.04;
        if (bars) crop = '${w}x$h+$x+$y';
      }
      _cropSourceWidth = width;
      _cropSourceHeight = height;
      appLogger.d('Letterbox detection: ${crop.isEmpty ? 'none' : crop} (video ${width}x$height)');
      if (crop != _letterboxCrop) {
        _letterboxCrop = crop;
        updateVideoFilter();
      }
    } catch (e) {
      appLogger.w('Letterbox detection failed', error: e);
    } finally {
      _letterboxChecked = true;
      _letterboxDetecting = false;
      if (filterAdded) {
        try {
          await player.command(['vf', 'remove', '@$_cropLabel']);
        } catch (_) {}
      }
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
    updateVideoFilter();
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
        await _applyProperty('panscan', '0');
        await _applyProperty(
          'video-zoom',
          (videoZoomPropertyForScale(zoomScale) + math.log(fitZoom) / math.ln2).toStringAsFixed(4),
        );
      }
      if (_hdrBrightness != null) await _applyProperty('gamma', _hdrGamma);
      // Last: older libmpv builds have no video-crop and refuse it.
      if (_cropLetterbox) {
        await _applyProperty('video-crop', zoomScale <= 1.0001 ? _letterboxCrop : '');
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
