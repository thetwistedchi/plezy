import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/youtube/youtube_service.dart';
import '../../services/youtube/youtube_settings.dart';
import '../../services/youtube/youtube_webview.dart';
import '../../theme/player_style.dart';
import '../../utils/app_logger.dart';
import '../../widgets/app_icon.dart';
import 'youtube_linkified_text.dart';
import 'youtube_strings.dart';
import '../../theme/retrowave_colors.dart';


/// Comments of a video, shown beside the player: top or newest first,
/// replies on demand, and writing, editing and deleting your own comments.
class YouTubeCommentsPanel extends StatefulWidget {
  const YouTubeCommentsPanel({
    super.key,
    required this.videoId,
    required this.commentCount,
    required this.onClose,
    this.onSeek,
  });

  final String videoId;
  final int? commentCount;
  final VoidCallback onClose;

  /// Fork: a timestamp in a comment was clicked.
  final ValueChanged<double>? onSeek;

  @override
  State<YouTubeCommentsPanel> createState() => _YouTubeCommentsPanelState();
}

class _YouTubeCommentsPanelState extends State<YouTubeCommentsPanel> {
  final _service = YouTubeService.instance;
  final _settings = YouTubeSettings.instance;
  final _scroll = ScrollController();
  final _input = TextEditingController();

  final List<YtComment> _comments = [];
  final Map<String, List<YtComment>> _replies = {};
  final Set<String> _expanded = {};
  final Set<String> _loadingReplies = {};
  String? _nextPage;
  bool _loading = false;
  bool _disabled = false;
  Object? _error;
  bool _newest = false;
  bool _sending = false;

  /// Comment being replied to, or null for a new top-level comment.
  YtComment? _replyTo;

  /// Comment being edited, with its parent when it is a reply.
  YtComment? _editing;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 400 && !_loading && _nextPage != null) {
      unawaited(_load());
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _comments.clear();
        _replies.clear();
        _expanded.clear();
        _nextPage = null;
      }
    });
    try {
      final page = await _service.commentThreads(widget.videoId, newest: _newest, pageToken: reset ? null : _nextPage);
      if (!mounted) return;
      setState(() {
        _comments.addAll(page.items);
        _nextPage = page.nextPageToken;
      });
    } on YouTubeApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.reason == 'commentsDisabled') {
          _disabled = true;
        } else {
          _error = e;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleReplies(YtComment comment) async {
    if (_expanded.contains(comment.id)) {
      setState(() => _expanded.remove(comment.id));
      return;
    }
    setState(() => _expanded.add(comment.id));
    if (_replies.containsKey(comment.id)) return;
    setState(() => _loadingReplies.add(comment.id));
    try {
      final replies = await _service.replies(comment.id);
      replies.sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
      if (mounted) setState(() => _replies[comment.id] = replies);
    } catch (e) {
      appLogger.d('YouTube replies failed: $e');
    } finally {
      if (mounted) setState(() => _loadingReplies.remove(comment.id));
    }
  }

  void _startReply(YtComment comment) {
    setState(() {
      _replyTo = comment;
      _editing = null;
      _input.text = '';
    });
  }

  void _startEdit(YtComment comment, {String? parentId}) {
    setState(() {
      _editing = comment;
      _replyTo = null;
      _input.text = comment.text;
    });
  }

  void _cancelCompose() {
    setState(() {
      _replyTo = null;
      _editing = null;
      _input.clear();
    });
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final editing = _editing;
      final replyTo = _replyTo;
      if (editing != null) {
        final updated = await _service.editComment(editing.id, text);
        editing
          ..text = updated.text
          ..edited = true;
      } else if (replyTo != null) {
        final reply = await _service.addReply(replyTo.id, text);
        final list = _replies[replyTo.id] ?? <YtComment>[];
        list.add(reply);
        _replies[replyTo.id] = list;
        _expanded.add(replyTo.id);
        replyTo.replyCount += 1;
      } else {
        final comment = await _service.addComment(widget.videoId, text);
        _comments.insert(0, comment);
        if (_scroll.hasClients) unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
      }
      if (!mounted) return;
      setState(() {
        _input.clear();
        _replyTo = null;
        _editing = null;
      });
    } catch (e) {
      appLogger.w('YouTube comment failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${YtStrings.commentFailed}\n$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(YtComment comment, {String? parentId}) async {
    try {
      await _service.deleteComment(comment.id);
      if (!mounted) return;
      setState(() {
        if (parentId == null) {
          _comments.removeWhere((c) => c.id == comment.id);
        } else {
          _replies[parentId]?.removeWhere((c) => c.id == comment.id);
          for (final c in _comments) {
            if (c.id == parentId && c.replyCount > 0) c.replyCount -= 1;
          }
        }
      });
    } catch (e) {
      appLogger.w('YouTube comment delete failed', error: e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  bool _isOwn(YtComment c) =>
      _settings.accountChannelId.isNotEmpty && c.authorChannelId == _settings.accountChannelId;

  @override
  Widget build(BuildContext context) {
    final accent = playerActiveColor(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PlayerChrome.of(context).panel,
        border: Border(left: BorderSide(color: PlayerChrome.of(context).outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(accent),
          Divider(height: 1, color: PlayerChrome.of(context).divider),
          Expanded(child: _body(accent)),
          if (!_disabled) _composer(accent),
        ],
      ),
    );
  }

  Widget _header(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      child: Row(
        children: [
          Text(
            YtStrings.comments,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          if (widget.commentCount != null) ...[
            const SizedBox(width: 8),
            Text('${widget.commentCount}', style: const TextStyle(color: Colors.white54, fontSize: 16)),
          ],
          const Spacer(),
          PopupMenuButton<bool>(
            tooltip: YtStrings.sortTop,
            initialValue: _newest,
            onSelected: (newest) {
              if (newest == _newest) return;
              setState(() => _newest = newest);
              unawaited(_load(reset: true));
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: false, child: Text(YtStrings.sortTop)),
              PopupMenuItem(value: true, child: Text(YtStrings.sortNewest)),
            ],
            icon: const AppIcon(Symbols.sort_rounded, color: Colors.white),
          ),
          IconButton(
            tooltip: YtStrings.close,
            onPressed: widget.onClose,
            icon: const AppIcon(Symbols.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _body(Color accent) {
    if (_disabled) return _note(YtStrings.commentsDisabled);
    if (_error != null && _comments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => unawaited(_load(reset: true)), child: Text(YtStrings.retry)),
            ],
          ),
        ),
      );
    }
    if (_comments.isEmpty) {
      return _loading ? Center(child: CircularProgressIndicator(color: accent)) : _note(YtStrings.noComments);
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
      itemCount: _comments.length + (_nextPage != null || _loading ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _comments.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loading
                  ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                  : TextButton(onPressed: () => unawaited(_load()), child: Text(YtStrings.loadMore)),
            ),
          );
        }
        final comment = _comments[i];
        final expanded = _expanded.contains(comment.id);
        final replies = _replies[comment.id];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CommentTile(
              onSeek: widget.onSeek,
              videoId: widget.videoId,
              comment: comment,
              own: _isOwn(comment),
              canWrite: _settings.canWrite,
              onReply: comment.canReply && _settings.canWrite ? () => _startReply(comment) : null,
              onEdit: () => _startEdit(comment),
              onDelete: () => unawaited(_delete(comment)),
            ),
            if (comment.replyCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => unawaited(_toggleReplies(comment)),
                    style: TextButton.styleFrom(foregroundColor: accent),
                    icon: AppIcon(expanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded, color: accent),
                    label: Text(expanded ? YtStrings.hideReplies : YtStrings.replies(comment.replyCount)),
                  ),
                ),
              ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: _loadingReplies.contains(comment.id)
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final reply in replies ?? const <YtComment>[])
                            _CommentTile(
                              onSeek: widget.onSeek,
                              videoId: widget.videoId,
                              comment: reply,
                              own: _isOwn(reply),
                              canWrite: _settings.canWrite,
                              small: true,
                              onReply: comment.canReply && _settings.canWrite ? () => _startReply(comment) : null,
                              onEdit: () => _startEdit(reply, parentId: comment.id),
                              onDelete: () => unawaited(_delete(reply, parentId: comment.id)),
                            ),
                        ],
                      ),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _note(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
    ),
  );

  Widget _composer(Color accent) {
    if (!_settings.canWrite) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: PlayerChrome.of(context).divider))),
        child: Text(YtStrings.needWriteAccess, style: const TextStyle(color: Colors.white60, fontSize: 13)),
      );
    }
    final label = _replyTo != null
        ? '${YtStrings.reply} @${_replyTo!.author.replaceFirst('@', '')}'
        : _editing != null
        ? YtStrings.edit
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: PlayerChrome.of(context).divider))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Row(
              children: [
                Expanded(
                  child: Text(label, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                TextButton(onPressed: _cancelCompose, child: Text(YtStrings.cancel)),
              ],
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: accent,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _replyTo != null ? YtStrings.addReply : YtStrings.addComment,
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: PlayerChrome.of(context).surface,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: PlayerChrome.of(context).outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: PlayerChrome.of(context).outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: YtStrings.send,
                onPressed: _sending || _input.text.trim().isEmpty ? null : () => unawaited(_submit()),
                style: IconButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const AppIcon(Symbols.send_rounded, fill: 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.own,
    required this.canWrite,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    this.small = false,
    this.onSeek,
    this.videoId,
  });

  final ValueChanged<double>? onSeek;

  /// Fork: for opening the comment on youtube.com, where it can be liked
  /// (the YouTube API offers no way to like a comment).
  final String? videoId;

  final YtComment comment;
  final bool own;
  final bool canWrite;
  final bool small;
  final VoidCallback? onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final avatar = small ? 24.0 : 32.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: SizedBox(
              width: avatar,
              height: avatar,
              child: comment.avatarUrl == null
                  ? ColoredBox(color: PlayerChrome.of(context).surface)
                  : CachedNetworkImage(
                      imageUrl: comment.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: PlayerChrome.of(context).surface),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: comment.author,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      TextSpan(
                        text: '  ${YtStrings.age(comment.publishedAt)}${comment.edited ? ' ${YtStrings.edited}' : ''}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                YouTubeLinkifiedText(
                  comment.text,
                  style: TextStyle(color: PlayerChrome.of(context).text, fontSize: 14, height: 1.4),
                  onSeek: onSeek,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _CommentLikeButton(comment: comment, videoId: videoId),
                    if (onReply != null) ...[
                      const SizedBox(width: 16),
                      InkWell(
                        onTap: onReply,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(
                            YtStrings.reply,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (own && canWrite)
            PopupMenuButton<String>(
              icon: const AppIcon(Symbols.more_vert_rounded, color: Colors.white70, size: 20),
              onSelected: (action) => action == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(YtStrings.edit)),
                PopupMenuItem(value: 'delete', child: Text(YtStrings.delete)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Fork: likes a comment with the signed-in account through a hidden
/// youtube.com page (Windows); elsewhere opens the comment on youtube.com.
class _CommentLikeButton extends StatefulWidget {
  const _CommentLikeButton({required this.comment, required this.videoId});

  final YtComment comment;
  final String? videoId;

  @override
  State<_CommentLikeButton> createState() => _CommentLikeButtonState();
}

class _CommentLikeButtonState extends State<_CommentLikeButton> {
  bool _busy = false;

  Future<void> _toggle(bool liked) async {
    final videoId = widget.videoId;
    if (videoId == null || _busy) return;
    if (!YouTubeWebView.isSupported) {
      await launchUrl(
        Uri.https('www.youtube.com', '/watch', {'v': videoId, 'lc': widget.comment.id}),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    setState(() => _busy = true);
    final ok = await YouTubeWebView.setCommentLiked(videoId, widget.comment.id, like: !liked);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(YtStrings.likeFailed),
          action: SnackBarAction(
            label: YtStrings.openOnYouTube,
            onPressed: () => unawaited(
              launchUrl(
                Uri.https('www.youtube.com', '/watch', {'v': videoId, 'lc': widget.comment.id}),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = playerActiveColor(context);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: YouTubeWebView.likedComments,
      builder: (context, liked, _) {
        final isLiked = liked.contains(widget.comment.id);
        final count = widget.comment.likeCount + (isLiked ? 1 : 0);
        final color = isLiked ? accent : Colors.white54;
        return Tooltip(
          message: isLiked ? YtStrings.unlikeComment : YtStrings.likeComment,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: widget.videoId == null ? null : () => unawaited(_toggle(isLiked)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy)
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                  else
                    AppIcon(Symbols.thumb_up_rounded, size: 16, fill: isLiked ? 1 : 0, color: color),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Text('$count', style: TextStyle(color: color, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
