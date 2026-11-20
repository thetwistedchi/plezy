import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/youtube/youtube_categories.dart';
import '../../services/youtube/youtube_channel_groups.dart';
import '../../widgets/app_icon.dart';
import 'youtube_strings.dart';

/// Chips for the user's channel groups above the subscriptions feed. Picking
/// one shows only videos from its channels; right-click or long-press edits it.
class YouTubeChannelGroupsBar extends StatelessWidget {
  const YouTubeChannelGroupsBar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.channels,
    this.channelCategories = const {},
  });

  /// Name of the active group, or null for all channels.
  final String? selected;
  final ValueChanged<String?> onSelected;

  /// Channels to choose from when editing: id → title.
  final Map<String, String> channels;

  /// Each channel's most common YouTube category id (signed-in feeds only).
  final Map<String, String> channelCategories;

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
            ActionChip(
              avatar: const AppIcon(Symbols.auto_awesome_rounded, size: 18),
              label: Text(YtStrings.suggestGroups),
              onPressed: () => unawaited(_suggest(context)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, YouTubeChannelGroup? group) async {
    final result = await showDialog<_GroupEdit>(
      context: context,
      builder: (_) => _GroupDialog(group: group, channels: channels, categories: channelCategories),
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

extension on YouTubeChannelGroupsBar {
  /// Offers one group per category found among the feed's channels and
  /// creates (or extends) the ones picked.
  Future<void> _suggest(BuildContext context) async {
    final byCategory = <String, Set<String>>{};
    for (final entry in channelCategories.entries) {
      if (!channels.containsKey(entry.key)) continue;
      byCategory.putIfAbsent(entry.value, () => {}).add(entry.key);
    }
    final suggestions = byCategory.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    final picked = await showDialog<List<MapEntry<String, Set<String>>>>(
      context: context,
      builder: (_) => _SuggestDialog(suggestions: suggestions),
    );
    if (picked == null || picked.isEmpty) return;
    final store = YouTubeChannelGroups.instance;
    await store.load();
    for (final entry in picked) {
      final name = YouTubeCategories.name(entry.key) ?? entry.key;
      final existing = store.byName(name);
      await store.put(name, {...?existing?.channelIds, ...entry.value});
    }
  }
}

class _SuggestDialog extends StatefulWidget {
  const _SuggestDialog({required this.suggestions});
  final List<MapEntry<String, Set<String>>> suggestions;

  @override
  State<_SuggestDialog> createState() => _SuggestDialogState();
}

class _SuggestDialogState extends State<_SuggestDialog> {
  // Categories with a single channel start unticked: a group of one rarely helps.
  late final Set<String> _picked = {
    for (final s in widget.suggestions)
      if (s.value.length > 1) s.key,
  };

  @override
  Widget build(BuildContext context) {
    final empty = widget.suggestions.isEmpty;
    return AlertDialog(
      title: Text(YtStrings.suggestGroups),
      content: SizedBox(
        width: 420,
        child: empty
            ? Text(YtStrings.noCategoryData)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(YtStrings.suggestGroupsHint, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final s in widget.suggestions)
                          CheckboxListTile(
                            dense: true,
                            value: _picked.contains(s.key),
                            title: Text(YouTubeCategories.name(s.key) ?? s.key),
                            subtitle: Text(YtStrings.channelCount(s.value.length)),
                            onChanged: (on) => setState(() {
                              if (on == true) {
                                _picked.add(s.key);
                              } else {
                                _picked.remove(s.key);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(YtStrings.cancel)),
        if (!empty)
          FilledButton(
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.pop(context, [
                    for (final s in widget.suggestions)
                      if (_picked.contains(s.key)) s,
                  ]),
            child: Text(YtStrings.create),
          ),
      ],
    );
  }
}

class _GroupEdit {
  const _GroupEdit(this.name, this.channelIds, {this.delete = false});
  final String name;
  final Set<String> channelIds;
  final bool delete;
}

class _GroupDialog extends StatefulWidget {
  const _GroupDialog({required this.group, required this.channels, required this.categories});
  final YouTubeChannelGroup? group;
  final Map<String, String> channels;
  final Map<String, String> categories;

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
      // By category, then name, so related channels sit together.
      ..sort((a, b) {
        final ca = YouTubeCategories.name(widget.categories[a.key]) ?? '\uffff';
        final cb = YouTubeCategories.name(widget.categories[b.key]) ?? '\uffff';
        final byCategory = ca.compareTo(cb);
        return byCategory != 0 ? byCategory : a.value.toLowerCase().compareTo(b.value.toLowerCase());
      });
    final categoriesPresent = {
      for (final e in entries)
        ?widget.categories[e.key],
    }.toList()
      ..sort((a, b) => (YouTubeCategories.name(a) ?? a).compareTo(YouTubeCategories.name(b) ?? b));
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
            if (categoriesPresent.isNotEmpty) ...[
              const SizedBox(height: 6),
              // Ticks every channel of a category at once.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in categoriesPresent)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(YouTubeCategories.name(id) ?? id),
                      onPressed: () => setState(() {
                        _picked.addAll([
                          for (final e in entries)
                            if (widget.categories[e.key] == id) e.key,
                        ]);
                        if (_name.text.trim().isEmpty) _name.text = YouTubeCategories.name(id) ?? id;
                      }),
                    ),
                ],
              ),
            ],
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
                            subtitle: switch (YouTubeCategories.name(widget.categories[e.key])) {
                              final name? => Text(name),
                              null => null,
                            },
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
