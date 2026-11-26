import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/retro_strings.dart';
import '../../services/browser/page_extract.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';

/// Fork: reader view. Shows an article's text without the page around it,
/// with a larger or smaller font on demand.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.url});

  final String url;

  static Future<void> open(BuildContext context, String url) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(url: url)));

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  ({String title, List<({String kind, String text})> blocks})? _article;
  Object? _error;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final html = await PageExtract.fetchHtml(widget.url);
      final article = PageExtract.extractArticle(html);
      if (mounted) setState(() => _article = article);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = tokens(context);
    final article = _article;
    final body = theme.textTheme.bodyLarge!.copyWith(fontSize: 18 * _scale, height: 1.6);
    return Scaffold(
      appBar: AppBar(
        title: Text(RetroStrings.readerView),
        actions: [
          IconButton(
            tooltip: RetroStrings.smallerText,
            icon: const AppIcon(Symbols.text_decrease_rounded),
            onPressed: () => setState(() => _scale = (_scale - 0.1).clamp(0.7, 2.0)),
          ),
          IconButton(
            tooltip: RetroStrings.largerText,
            icon: const AppIcon(Symbols.text_increase_rounded),
            onPressed: () => setState(() => _scale = (_scale + 0.1).clamp(0.7, 2.0)),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(RetroStrings.readerFailed, style: TextStyle(color: mono.textMuted)))
          : article == null
          ? const Center(child: CircularProgressIndicator())
          : article.blocks.isEmpty
          ? Center(child: Text(RetroStrings.readerEmpty, style: TextStyle(color: mono.textMuted)))
          : Scrollbar(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              article.title,
                              style: theme.textTheme.headlineMedium!.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 30 * _scale,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(Uri.tryParse(widget.url)?.host ?? '', style: TextStyle(color: mono.textMuted)),
                            const SizedBox(height: 24),
                            for (final b in article.blocks)
                              Padding(
                                padding: EdgeInsets.only(bottom: b.kind.startsWith('h') ? 10 : 16, top: b.kind.startsWith('h') ? 12 : 0),
                                child: switch (b.kind) {
                                  'h2' || 'h3' => Text(
                                    b.text,
                                    style: body.copyWith(fontWeight: FontWeight.w700, fontSize: (b.kind == 'h2' ? 24 : 21) * _scale),
                                  ),
                                  'li' => Text('•  ${b.text}', style: body),
                                  'blockquote' => Container(
                                    padding: const EdgeInsets.only(left: 14),
                                    decoration: BoxDecoration(
                                      border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
                                    ),
                                    child: Text(b.text, style: body.copyWith(fontStyle: FontStyle.italic)),
                                  ),
                                  'pre' => Text(b.text, style: body.copyWith(fontFamily: 'monospace', fontSize: 15 * _scale)),
                                  _ => Text(b.text, style: body),
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
