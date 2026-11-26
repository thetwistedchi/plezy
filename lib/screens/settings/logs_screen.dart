import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart' show FileType;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import '../../focus/focusable_action_bar.dart';
import '../../widgets/dialog_action_button.dart';
import '../../widgets/app_icon.dart';
import '../../focus/key_event_utils.dart';
import '../../navigation/page_refresh_shortcut.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/mounted_set_state_mixin.dart';
import '../../utils/dialogs.dart';
import '../../main.dart' show gitCommit;
import '../../services/background_work_diagnostics_service.dart';
import '../../services/device_performance.dart';
import '../../services/file_picker_service.dart';
import '../../services/log_upload_service.dart' show constrainLogUploadPayload;
import '../../i18n/retro_strings.dart';
import '../../services/startup_diagnostics.dart';
import '../../services/video_decode_capabilities.dart';
import '../../utils/app_logger.dart';
import '../../utils/app_version.dart';
import '../../retrowave_version.dart';
import '../../utils/formatters.dart';
import '../../utils/platform_detector.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/system_bottom_inset.dart';

const previousStartupFailureKey = Key('logs-previous-startup-failure');

/// `SelectionArea` claims plain arrow keys as no-op caret moves, which starves
/// `DirectionalFocusIntent` and pins D-pad focus on the app-bar back button.
/// Only the collapsing (unshifted) variants are disabled; Shift+Arrow selection
/// still reaches the region's own handler via [callingAction].
class _CollapsingSelectionMoveAction<T extends DirectionalCaretMovementIntent> extends Action<T> {
  @override
  bool isEnabled(T intent) => !intent.collapseSelection && (callingAction?.isEnabled(intent) ?? false);

  @override
  bool consumesKey(T intent) => callingAction?.consumesKey(intent) ?? false;

  @override
  Object? invoke(T intent) => callingAction?.invoke(intent);
}

/// `SelectionArea` concatenates adjacent selectables with no separator; each
/// log row (and the device header) is its own paragraph, so a copied
/// drag-selection ran records together. The scrollable owns the delegate that
/// does the concatenation (and the lazy-row/autoscroll bookkeeping), so the
/// boundary is added per record: every selected record ends its text with
/// `\n`, and [_RecordSelectionDelegate] drops the one dangling after the last
/// record so a partial drag copies exactly what was highlighted.
class _RecordBoundaryDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final text = super.getSelectedContent()?.plainText;
    // A drag ending at offset 0 of a row selects nothing in it: no boundary.
    if (text == null || text.isEmpty) return null;
    return SelectedContent(plainText: '$text\n');
  }
}

class _RecordSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final text = super.getSelectedContent()?.plainText;
    if (text == null) return null;
    return SelectedContent(plainText: text.endsWith('\n') ? text.substring(0, text.length - 1) : text);
  }
}

/// One selectable record: the device header or a single log entry.
class _LogRecord extends StatefulWidget {
  const _LogRecord({required this.child});

  final Widget child;

  @override
  State<_LogRecord> createState() => _LogRecordState();
}

class _LogRecordState extends State<_LogRecord> {
  final _RecordBoundaryDelegate _boundary = _RecordBoundaryDelegate();

  @override
  void dispose() {
    _boundary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionContainer(delegate: _boundary, child: widget.child);
}

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, this.httpClient, this.deviceInfoPlugin});

  final MediaServerHttpClient? httpClient;
  final DeviceInfoPlugin? deviceInfoPlugin;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> with MountedSetStateMixin {
  List<LogEntry> _logs = [];
  String _deviceInfo = '';
  final ScrollController _scrollController = ScrollController();
  // skipTraversal: selection is pointer-driven; the region must not become a
  // D-pad/Tab stop between the action bar and the scrollable body.
  final FocusNode _selectionFocusNode = FocusNode(skipTraversal: true, debugLabel: 'logs-selection');
  final _RecordSelectionDelegate _recordSelection = _RecordSelectionDelegate();


  @override
  void initState() {
    super.initState();
    _logs = MemoryLogOutput.getLogs();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    final appVersion = await AppVersion.current();
    final deviceInfo = widget.deviceInfoPlugin ?? DeviceInfoPlugin();
    final buffer = StringBuffer();
    final commitSuffix = gitCommit.isNotEmpty ? ' ${gitCommit.substring(0, 7)}' : '';
    buffer.writeln(
      // Fork: the Retrowave version first; the upstream base follows.
      'Plezy Retrowave $retrowaveVersion (based on ${t.app.title} v${appVersion.versionOrUnknown})$commitSuffix',
    );

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      buffer.writeln('Android ${info.version.release} (API ${info.version.sdkInt})');
      buffer.writeln('${info.manufacturer} ${info.model}');
      if (PlatformDetector.isTV()) {
        final reasons = TvDetectionService.tvDetectionReasonsSync();
        final suffix = reasons.isEmpty ? '' : ' (${reasons.join(', ')})';
        buffer.writeln('TV mode: yes$suffix');
      }
      // Renderer + effects tier turn "did the reduced tier engage on this
      // device" into something answerable from any uploaded log (#1349).
      String renderer;
      try {
        renderer = await const MethodChannel('com.plezy/theme').invokeMethod<String>('getRenderer') ?? 'unknown';
      } catch (_) {
        renderer = 'unknown';
      }
      buffer.writeln('Renderer: $renderer');
      // "Are downloads allowed to run in the background" is the single most
      // asked support question; answering it from the uploaded log turns a
      // four-message thread into one reply.
      final backgroundWork = BackgroundWorkDiagnosticsService.instance;
      await backgroundWork.refresh();
      buffer.writeln('Background: ${backgroundWork.describeSync()}');
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      buffer.writeln('iOS ${info.systemVersion}');
      buffer.writeln(info.utsname.machine);
    } else if (Platform.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      buffer.writeln('macOS ${info.osRelease}');
      buffer.writeln(info.model);
    } else if (Platform.isLinux) {
      final info = await deviceInfo.linuxInfo;
      buffer.writeln('Linux ${info.versionId ?? info.id}');
    }

    buffer.writeln('Effects: ${DevicePerformance.describeSync()}');
    buffer.writeln('Display: ${DevicePerformance.describeDisplay()}');
    buffer.writeln('Video decoders: ${VideoDecodeCapabilities.describeSync()}');

    setStateIfMounted(() => _deviceInfo = buffer.toString().trimRight());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _selectionFocusNode.dispose();
    _recordSelection.dispose();
    super.dispose();
  }

  void _loadLogs() {
    setState(() {
      _logs = MemoryLogOutput.getLogs();
    });
  }

  String _formatTime(DateTime time) {
    final hour = padNumber(time.hour, 2);
    final minute = padNumber(time.minute, 2);
    final second = padNumber(time.second, 2);
    final millisecond = padNumber(time.millisecond, 3);
    return '$hour:$minute:$second.$millisecond';
  }

  /// Whether there is anything worth copying, uploading or clearing.
  ///
  /// A launch that failed the startup gate leaves an empty in-memory buffer —
  /// that process is gone — but does leave a persisted record. Gating the
  /// actions on the buffer alone would show that record and then refuse to let
  /// the user do anything with it, which is the whole point of #1732.
  bool get _hasDiagnostics => _logs.isNotEmpty || StartupDiagnosticsStore.pending != null;

  Future<void> _clearLogs() async {
    // The startup record is part of the same diagnostic payload, so clearing
    // logs drops it too, or it would silently reappear in the next upload.
    // Awaited before rebuilding so the banner cannot survive the clear.
    await StartupDiagnosticsStore.clear();
    if (!mounted) return;
    setState(() {
      MemoryLogOutput.clearLogs();
      _logs = [];
    });
    showSuccessSnackBar(context, t.messages.logsCleared);
  }

  String _formatAllLogs({int? maxBytes}) {
    final sections = <String>[
      if (_deviceInfo.isNotEmpty) _deviceInfo,
      // A launch that failed the startup gate leaves no in-memory log at all —
      // the buffer died with that process. This is the only place its record
      // can reach a maintainer (#1732).
      ?StartupDiagnosticsStore.pending?.describe(),
    ];
    final header = sections.isEmpty ? '' : '${sections.join('\n\n')}\n---\n';
    final logs = StringBuffer();
    var isFirst = true;
    for (final log in _logs.reversed) {
      if (!isFirst) {
        logs.write('\n');
      }
      isFirst = false;

      logs.write('[${_formatTime(log.timestamp)}] [${log.level.name.toUpperCase()}] ${log.message}');
      if (log.error != null) {
        logs.write('\nError: ${log.error}');
      }
      if (log.stackTrace != null) {
        logs.write('\nStack trace:\n${log.stackTrace}');
      }
    }
    final logText = logs.toString();
    return maxBytes == null
        ? '$header$logText'
        : constrainLogUploadPayload(header: header, logs: logText, maxBytes: maxBytes);
  }

  /// Android binder transactions are capped around 1 MiB and
  /// `Clipboard.setData` crosses one; an oversized payload aborts with
  /// TransactionTooLargeException. UTF-16 parceling can double the UTF-8
  /// size, so stay well below the limit. Trimming keeps the newest lines,
  /// matching the upload path.
  static const int _maxClipboardBytes = 256 * 1024;

  void _copyAllLogs() {
    Clipboard.setData(ClipboardData(text: _formatAllLogs(maxBytes: _maxClipboardBytes)));
    showSuccessSnackBar(context, t.messages.logsCopied);
  }

  /// Fork: logs are saved to a file instead of uploaded. The upload went to
  /// the upstream Plezy log service, whose developers can't help with this
  /// fork. Android TV has no file picker, so there the file goes to the
  /// app's own folder on shared storage, which `adb pull` can read.
  Future<void> _saveLogs() async {
    final bytes = Uint8List.fromList(utf8.encode(_formatAllLogs()));
    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(RegExp('[:T]'), '-');
    final fileName = 'plezy-retrowave-log-$stamp.txt';
    try {
      if (Platform.isAndroid && PlatformDetector.isTV()) {
        final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        final file = File(p.join(dir.path, fileName));
        await file.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        unawaited(
          showScopedDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(RetroStrings.logsSaved),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(RetroStrings.logsSavedTvHint),
                  const SizedBox(height: 8),
                  SelectableText('adb pull ${file.path}', style: const TextStyle(fontFamily: 'monospace')),
                ],
              ),
              actions: [
                DialogActionButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(), label: t.common.close),
              ],
            ),
          ),
        );
        return;
      }
      final path = await FilePickerService.instance.saveFile(
        dialogTitle: RetroStrings.saveLogs,
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['txt'],
      );
      if (path == null || !mounted) return;
      // Desktop pickers only return the chosen path; write the file there.
      if (!Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        if (!await file.exists() || await file.length() == 0) await file.writeAsBytes(bytes, flush: true);
      }
      if (!mounted) return;
      showSuccessSnackBar(context, RetroStrings.logsSaved);
    } catch (e) {
      appLogger.w('Saving logs failed', error: e);
      if (!mounted) return;
      showErrorSnackBar(context, RetroStrings.logsSaveFailed);
    }
  }

  Color _getLevelColor(Level level) {
    switch (level) {
      case Level.error:
      case Level.fatal:
        return Colors.red;
      case Level.warning:
        return Colors.orange;
      case Level.info:
        return Colors.blue;
      case Level.debug:
      case Level.trace:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  void _scroll(double delta) {
    final pos = _scrollController.position;
    _scrollController.animateTo(
      (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  TextStyle? _logTextStyle(ThemeData theme) =>
      theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 12, height: 1.5);

  List<TextSpan> _buildDeviceInfoSpans() {
    return [
      TextSpan(
        text: '$_deviceInfo\n',
        style: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
      ),
      TextSpan(
        text: '---',
        style: TextStyle(color: Colors.grey.withValues(alpha: 0.3)),
      ),
    ];
  }

  List<TextSpan> _buildEntrySpans(LogEntry log) {
    final color = _getLevelColor(log.level);
    return [
      TextSpan(
        text: '[${_formatTime(log.timestamp)}] ',
        style: TextStyle(color: color.withValues(alpha: 0.6)),
      ),
      TextSpan(
        text: '[${log.level.name.toUpperCase()}] ',
        style: TextStyle(color: color, fontWeight: .bold),
      ),
      TextSpan(text: log.message),
      if (log.error != null)
        TextSpan(
          text: '\n  Error: ${log.error}',
          style: TextStyle(color: color),
        ),
      if (log.stackTrace != null)
        TextSpan(
          text: '\n  ${log.stackTrace.toString().replaceAll('\n', '\n  ')}',
          style: TextStyle(color: Colors.grey.withValues(alpha: 0.7)),
        ),
    ];
  }

  /// Banner for a startup failure recorded by an earlier launch.
  ///
  /// Returns null when there is none, so the caller can splice it in with a
  /// null-aware element.
  Widget? _buildPreviousFailureBanner(ThemeData theme) {
    final failure = StartupDiagnosticsStore.pending;
    if (failure == null) return null;

    return SliverToBoxAdapter(
      key: previousStartupFailureKey,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcon(Symbols.error_rounded, size: 18, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.startup.previousFailureTitle,
                    style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              failure.describe(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 12,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        final backResult = handleBackKeyNavigation(context, event);
        if (backResult != KeyEventResult.ignored) return backResult;
        final refreshResult = handlePageRefreshShortcut(event, _loadLogs);
        if (refreshResult != KeyEventResult.ignored) return refreshResult;
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _scroll(80);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _scroll(-80);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: PrimaryScrollController(
        controller: _scrollController,
        child: Scaffold(
          body: Actions(
            actions: <Type, Action<Intent>>{
              ExtendSelectionByCharacterIntent: _CollapsingSelectionMoveAction<ExtendSelectionByCharacterIntent>(),
              ExtendSelectionVerticallyToAdjacentLineIntent:
                  _CollapsingSelectionMoveAction<ExtendSelectionVerticallyToAdjacentLineIntent>(),
            },
            child: SelectionArea(
              focusNode: _selectionFocusNode,
              child: SelectionContainer(
                delegate: _recordSelection,
                // Horizontal-only SafeArea: log rows clear a landscape notch
                // or iPhone Duo's portrait sensor column.
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: CustomScrollView(
                    primary: true,
                    slivers: [
                      CustomAppBar(
                        // Chrome is not log content; keep it out of drag-selection.
                        title: SelectionContainer.disabled(child: Text(t.screens.logs)),
                        pinned: true,
                        actions: [
                          FocusableActionBar(
                            // Fork: Left from the first button moves on to the
                            // back arrow instead of stopping at the row's edge.
                            onNavigateLeft: () =>
                                FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.left),
                            actions: [
                              FocusableAction(
                                icon: Symbols.refresh_rounded,
                                tooltip: t.common.refresh,
                                onPressed: _loadLogs,
                              ),
                              FocusableAction(
                                icon: Symbols.save_rounded,
                                tooltip: RetroStrings.saveLogs,
                                onPressed: _hasDiagnostics ? _saveLogs : null,
                              ),
                              FocusableAction(
                                icon: Symbols.content_copy_rounded,
                                tooltip: t.logs.copyLogs,
                                onPressed: _hasDiagnostics ? _copyAllLogs : null,
                              ),
                              FocusableAction(
                                icon: Symbols.delete_outline_rounded,
                                tooltip: t.logs.clearLogs,
                                onPressed: _hasDiagnostics ? _clearLogs : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                      // A launch that failed the startup gate leaves nothing in the
                      // in-memory buffer — that process is gone. Show its record
                      // here, where the user can actually act on it (#1732).
                      ?_buildPreviousFailureBanner(theme),
                      if (_logs.isEmpty)
                        SliverFillRemaining(child: Center(child: Text(t.messages.noLogsAvailable)))
                      else ...[
                        if (_deviceInfo.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                            sliver: SliverToBoxAdapter(
                              child: _LogRecord(
                                child: Text.rich(
                                  TextSpan(style: _logTextStyle(theme), children: _buildDeviceInfoSpans()),
                                ),
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(12, _deviceInfo.isEmpty ? 12 : 0, 12, 12),
                          // One widget per entry so only the visible slice is laid
                          // out. The buffer holds up to 5 MiB of text; as a single
                          // paragraph that was a multi-second frame and hundreds of
                          // MB of glyph data — an OOM kill on phones and TVs.
                          sliver: SliverList.builder(
                            itemCount: _logs.length,
                            itemBuilder: (context, index) => _LogRecord(
                              child: Text.rich(
                                TextSpan(style: _logTextStyle(theme), children: _buildEntrySpans(_logs[index])),
                              ),
                            ),
                          ),
                        ),
                        // Only the log body needs it: the empty state already fills
                        // the viewport, so a trailing inset would just add slack.
                        const SliverSystemBottomInset(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
