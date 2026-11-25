import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/retrowave_colors.dart';
import '../../widgets/app_icon.dart';
import 'youtube_linkified_text.dart';
import 'youtube_strings.dart';

/// The video description beside the player, with clickable links and
/// timestamps that seek.
class YouTubeDescriptionPanel extends StatelessWidget {
  const YouTubeDescriptionPanel({
    super.key,
    required this.title,
    required this.description,
    required this.onSeek,
    required this.onClose,
  });

  final String title;
  final String? description;
  final ValueChanged<double> onSeek;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final chrome = PlayerChrome.of(context);
    final text = description?.trim() ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: chrome.panel,
        border: Border(left: BorderSide(color: chrome.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
            child: Row(
              children: [
                Text(
                  YtStrings.description,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: YtStrings.close,
                  onPressed: onClose,
                  icon: const AppIcon(Symbols.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: description == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      Text(
                        title,
                        style: TextStyle(color: chrome.text, fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
                      ),
                      const SizedBox(height: 12),
                      if (text.isEmpty)
                        Text(YtStrings.noDescription, style: const TextStyle(color: Colors.white54))
                      else
                        YouTubeLinkifiedText(
                          text,
                          style: TextStyle(color: chrome.text, fontSize: 14, height: 1.45),
                          onSeek: onSeek,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
