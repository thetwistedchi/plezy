import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/youtube/youtube_channel_groups.dart';
import '../../widgets/app_icon.dart';
import 'youtube_strings.dart';

/// Chips for the user's channel groups above the subscriptions feed. Picking
/// one shows only videos from its channels; right-click or long-press edits it.
class YouTubeChannelGroupsBar extends StatelessWidget {
  const YouTubeChannelGroupsBar({super.key, required this.selected, required this.onSelected, required this.channels});

  /// Name of the active group, or null for all channels.
  final String? selected;
  final ValueChanged<String?> onSelected;

  /// Channels to choose from when editing: id → title.
  final Map<String, String> channels;

  @override
  Widget build(BuildContext context) {
    final store = YouTubeChannelGroups.instance;
    unawaited(store.load());
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final groups = store.groups;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(YtStrings.allChannels),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
            for (final group in groups)
              GestureDetector(
                onSecondaryTap: () => unawaited(_edit(context, group)),
                onLongPress: () => unawaited(_edit(context, group)),
                child: ChoiceChip(
                  label: Text('${group.name} (${group.channelIds.length})'),
                  selected: selected == group.name,
                  onSelected: (on) => onSelected(on ? group.name : null),
                ),
              ),
            ActionChip(
              avatar: const AppIcon(Symbols.add_rounded, size: 18),
              label: Text(YtStrings.newGroup),
              onPressed: () => unawaited(_edit(context, null)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, YouTubeChannelGroup? group) async {
    final result = await showDialog<_GroupEdit>(
      context: context,
      builder: (_) => _GroupDialog(group: group, channels: channels),
    );
    if (result == null) return;
    final store = YouTubeChannelGroups.instance;
    if (result.delete) {
      await store.remove(group!.name);
      if (selected == group.name) onSelected(null);
      return;
    }
    await store.put(result.name, result.channelIds, previousName: group?.name);
    if (group != null && selected == group.name && result.name != group.name) onSelected(result.name);
  }
}

class _GroupEdit {
  const _GroupEdit(this.name, this.channelIds, {this.delete = false});
  final String name;
  final Set<String> channelIds;
  final bool delete;
}

class _GroupDialog extends StatefulWidget {
  const _GroupDialog({required this.group, required this.channels});
  final YouTubeChannelGroup? group;
  final Map<String, String> channels;

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.group?.name ?? '');
  late final Set<String> _picked = {...?widget.group?.channelIds};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Channels of the group that have no videos in the feed keep their place.
    final entries = {
      ...widget.channels,
      for (final id in _picked)
        if (!widget.channels.containsKey(id)) id: id,
    }.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    final canSave = _name.text.trim().isNotEmpty && _picked.isNotEmpty;
    return AlertDialog(
      title: Text(widget.group == null ? YtStrings.newGroup : YtStrings.editGroup),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.group == null,
              decoration: InputDecoration(labelText: YtStrings.groupName),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(YtStrings.groupChannels, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(YtStrings.noChannelsYet, textAlign: TextAlign.center))
                  : ListView(
                      children: [
                        for (final e in entries)
                          CheckboxListTile(
                            dense: true,
                            value: _picked.contains(e.key),
                            title: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onChanged: (on) => setState(() => on == true ? _picked.add(e.key) : _picked.remove(e.key)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.group != null)
          TextButton(
            onPressed: () => Navigator.pop(context, _GroupEdit(widget.group!.name, const {}, delete: true)),
            child: Text(YtStrings.delete),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(YtStrings.cancel)),
        FilledButton(
          onPressed: canSave ? () => Navigator.pop(context, _GroupEdit(_name.text.trim(), {..._picked})) : null,
          child: Text(YtStrings.save),
        ),
      ],
    );
  }
}
