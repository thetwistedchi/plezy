import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Fork: text with clickable links (open in the browser) and timestamps
/// such as 1:23 or 1:02:03 (jump there in the video), for descriptions and
/// comments.
class YouTubeLinkifiedText extends StatefulWidget {
  const YouTubeLinkifiedText(this.text, {super.key, required this.style, this.onSeek, this.linkColor});

  final String text;
  final TextStyle style;
  final ValueChanged<double>? onSeek;
  final Color? linkColor;

  @override
  State<YouTubeLinkifiedText> createState() => _YouTubeLinkifiedTextState();
}

class _YouTubeLinkifiedTextState extends State<YouTubeLinkifiedText> {
  static final _pattern = RegExp(r'(https?://[^\s<>"]+)|(\b(?:\d{1,2}:)?\d{1,2}:\d{2}\b)');
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  static double? _seconds(String stamp) {
    final parts = stamp.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    var total = 0;
    for (final p in parts) {
      total = total * 60 + p!;
    }
    return total.toDouble();
  }

  List<InlineSpan> _spans() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final link = widget.style.copyWith(
      color: widget.linkColor ?? const Color(0xFF22D2EB),
      decoration: TextDecoration.underline,
      decorationColor: (widget.linkColor ?? const Color(0xFF22D2EB)).withValues(alpha: 0.6),
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _pattern.allMatches(widget.text)) {
      final url = m.group(1);
      final stamp = m.group(2);
      VoidCallback? onTap;
      if (url != null) {
        // Trailing punctuation belongs to the sentence, not the link.
        final clean = url.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
        final uri = Uri.tryParse(clean);
        if (uri != null) onTap = () => launchUrl(uri, mode: LaunchMode.externalApplication);
        if (clean.length != url.length) {
          spans.add(TextSpan(text: widget.text.substring(last, m.start)));
          final r = TapGestureRecognizer()..onTap = onTap;
          _recognizers.add(r);
          spans.add(TextSpan(text: clean, style: link, recognizer: r));
          last = m.start + clean.length;
          continue;
        }
      } else if (stamp != null && widget.onSeek != null) {
        final s = _seconds(stamp);
        if (s != null) onTap = () => widget.onSeek!(s);
      }
      if (onTap == null) continue;
      spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      final r = TapGestureRecognizer()..onTap = onTap;
      _recognizers.add(r);
      spans.add(TextSpan(text: m.group(0), style: link, recognizer: r));
      last = m.end;
    }
    spans.add(TextSpan(text: widget.text.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(TextSpan(style: widget.style, children: _spans()));
  }
}
