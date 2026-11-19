import 'package:flutter/material.dart';

/// Just enough Markdown for release notes: `#`–`###` headings, `-`/`*`
/// bullets (indented ones nest), `**bold**` and `` `code` ``. Anything else
/// shows as plain text.
class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.text, {super.key});

  final String text;

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^(\s*)[-*]\s+(.*)$');
  static final _inline = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`)');

  List<InlineSpan> _spans(String line, TextStyle base, ThemeData theme) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start)));
      final token = m.group(0)!;
      if (token.startsWith('**')) {
        spans.add(TextSpan(text: token.substring(2, token.length - 2), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: TextStyle(
              fontFamily: 'monospace',
              backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            ),
          ),
        );
      }
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium ?? const TextStyle();
    final children = <Widget>[];
    for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 6));
        continue;
      }
      if (_heading.firstMatch(line) case final m?) {
        final level = m.group(1)!.length;
        final style = (level <= 2 ? theme.textTheme.titleMedium : theme.textTheme.titleSmall)?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        );
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 6, bottom: 2),
            child: Text.rich(TextSpan(children: _spans(m.group(2)!, style ?? body, theme)), style: style),
          ),
        );
        continue;
      }
      if (_bullet.firstMatch(line) case final m?) {
        final depth = (m.group(1)!.replaceAll('\t', '  ').length / 2).floor();
        children.add(
          Padding(
            padding: EdgeInsets.only(left: 4.0 + depth * 16, top: 1, bottom: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(depth == 0 ? '•  ' : '◦  ', style: body),
                Expanded(child: Text.rich(TextSpan(children: _spans(m.group(2)!, body, theme)), style: body)),
              ],
            ),
          ),
        );
        continue;
      }
      children.add(Text.rich(TextSpan(children: _spans(line.trim(), body, theme)), style: body));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }
}
