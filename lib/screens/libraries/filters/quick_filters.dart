import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/library_filter_selection.dart';
import '../../../media/library_query.dart';
import '../../../media/media_filter.dart';
import '../../../services/storage_service.dart';
import '../../../utils/app_logger.dart';

/// Texts for the fork's library filter additions, English and German. Kept
/// out of the slang files so the fork stays easy to rebase onto upstream.
class FilterStrings {
  FilterStrings._();

  static bool get _de => LocaleSettings.currentLocale == AppLocale.de;
  static String _t(String en, String de) => _de ? de : en;

  static String get unwatched => _t('Unwatched', 'Ungesehen');
  static String get uhd => '4K';
  static String get hdr => 'HDR';
  static String audio(String code) => _t('Audio: $code', 'Ton: $code');
  static String get audioAny => _t('Audio', 'Ton');
  static String get anyLanguage => _t('Any language', 'Alle Sprachen');
  static String get recent => _t('Added recently', 'Neu hinzugefügt');
  static String get saved => _t('Saved', 'Gespeichert');
  static String get saveCurrent => _t('Save current filters…', 'Aktuelle Filter speichern…');
  static String get deleteSaved => _t('Delete a saved set…', 'Gespeichertes Set löschen…');
  static String deleteNamed(String name) => _t('Delete "$name"', '"$name" löschen');
  static String get nameTitle => _t('Save filter set', 'Filter-Set speichern');
  static String get nameLabel => _t('Name', 'Name');
  static String get noSaved =>
      _t('No saved sets yet. Pick filters, then save them here.', 'Noch keine Sets. Filter wählen und hier speichern.');
  static String get nothingToSave => _t('Choose a filter or sort first.', 'Erst einen Filter oder eine Sortierung wählen.');
  static String savedAs(String name) => _t('Saved "$name"', '"$name" gespeichert');
  static String get surprise => _t('Surprise me', 'Überrasch mich');
  static String get surpriseEmpty => _t('Nothing matches these filters.', 'Nichts passt zu diesen Filtern.');
  static String removeFilter(String label) => _t('Remove $label', '$label entfernen');
}

enum QuickFilterKind { unwatched, uhd, hdr, audio, recent }

/// One toggle in the quick filter row, resolved against the fields this
/// library's server actually offers. It always maps to a plain clause the
/// regular filter editor can show and edit too.
class QuickFilter {
  final QuickFilterKind kind;
  final MediaFilter field;
  final LibraryFilterOperator op;
  final String value;

  /// Display name of [value] for value-list fields, so the filter summary
  /// can name it instead of counting it.
  final String? valueTitle;
  final String label;

  /// For the audio chooser: every language the library has (value id and
  /// title), the app's language first. Empty for plain toggles.
  final List<({String id, String title})> choices;

  const QuickFilter({
    required this.kind,
    required this.field,
    required this.op,
    required this.value,
    required this.label,
    this.valueTitle,
    this.choices = const [],
  });

  bool get isChooser => choices.isNotEmpty;

  /// The chooser's selected value id, if this field has exactly one.
  String? selectedChoice(List<LibraryFilter> selected) {
    final own = selected.clausesFor(field.filter);
    if (own.length != 1 || own.first.op != LibraryFilterOperator.is_ || own.first.values.length != 1) return null;
    return own.first.values.first;
  }

  /// Chip label: the chosen language, or plain "Audio".
  String labelFor(List<LibraryFilter> selected) {
    if (!isChooser) return label;
    final id = selectedChoice(selected);
    if (id == null) return selected.clausesFor(field.filter).isEmpty ? FilterStrings.audioAny : label;
    final title = choices.where((c) => c.id == id).firstOrNull?.title ?? id;
    return FilterStrings.audio(title);
  }

  /// [selected] with the chooser set to [id] (null clears the field).
  List<LibraryFilter> choose(List<LibraryFilter> selected, String? id) => selected.withField(
    field.filter,
    id == null ? const [] : [LibraryFilter(field: field.filter, op: LibraryFilterOperator.is_, values: [id])],
  );

  IconData get icon => switch (kind) {
    QuickFilterKind.unwatched => Symbols.visibility_off_rounded,
    QuickFilterKind.uhd => Symbols.four_k_rounded,
    QuickFilterKind.hdr => Symbols.hdr_on_rounded,
    QuickFilterKind.audio => Symbols.translate_rounded,
    QuickFilterKind.recent => Symbols.new_releases_rounded,
  };

  bool isActive(List<LibraryFilter> selected) => isChooser
      ? selected.any((c) => c.field == field.filter)
      : selected.any((c) => c.field == field.filter && c.op == op && c.values.contains(value));

  /// [selected] with this toggle flipped. Turning it on replaces whatever
  /// else was set on the same field, since two clauses on one field AND and
  /// would usually match nothing.
  List<LibraryFilter> toggle(List<LibraryFilter> selected) {
    if (!isActive(selected)) {
      return selected.withField(field.filter, [LibraryFilter(field: field.filter, op: op, values: [value])]);
    }
    final remaining = <LibraryFilter>[];
    for (final clause in selected.clausesFor(field.filter)) {
      if (clause.op != op || !clause.values.contains(value)) {
        remaining.add(clause);
        continue;
      }
      final values = clause.values.where((v) => v != value).toList();
      if (values.isNotEmpty) remaining.add(clause.copyWith(values: values));
    }
    return selected.withField(field.filter, remaining);
  }
}

String _bareField(MediaFilter f) => f.filter.split('.').last;

/// First field whose name matches one of [names], preferring fields of the
/// browsed type over cross-type ones (`episode.resolution`).
MediaFilter? _findField(List<MediaFilter> filters, List<String> names, {bool Function(MediaFilter)? where}) {
  MediaFilter? qualified;
  for (final f in filters) {
    if (!names.contains(_bareField(f))) continue;
    if (where != null && !where(f)) continue;
    if (!f.filter.contains('.')) return f;
    qualified ??= f;
  }
  return qualified;
}

/// ISO codes and names a server may use for the app's language.
const Map<String, List<String>> _languageAliases = {
  'de': ['de', 'deu', 'ger', 'german', 'deutsch'],
  'en': ['en', 'eng', 'english'],
  'fr': ['fr', 'fra', 'fre', 'french', 'français', 'francais'],
  'es': ['es', 'spa', 'spanish', 'español', 'espanol'],
  'it': ['it', 'ita', 'italian', 'italiano'],
  'nl': ['nl', 'nld', 'dut', 'dutch', 'nederlands'],
  'pl': ['pl', 'pol', 'polish', 'polski'],
  'pt': ['pt', 'por', 'portuguese', 'português', 'portugues'],
  'ru': ['ru', 'rus', 'russian', 'русский'],
  'sv': ['sv', 'swe', 'swedish', 'svenska'],
  'da': ['da', 'dan', 'danish', 'dansk'],
  'nb': ['nb', 'no', 'nor', 'nob', 'norwegian', 'norsk'],
  'tr': ['tr', 'tur', 'turkish', 'türkçe'],
  'hu': ['hu', 'hun', 'hungarian', 'magyar'],
  'bg': ['bg', 'bul', 'bulgarian'],
  'ja': ['ja', 'jpn', 'japanese', '日本語'],
  'ko': ['ko', 'kor', 'korean', '한국어'],
  'zh': ['zh', 'zho', 'chi', 'chinese', '中文'],
};

/// Builds the quick filters this library supports. Value-list fields need
/// their values to know whether a match exists, so those are fetched through
/// [valuesOf]; a chip whose field or value is missing is left out.
/// Resolved quick filters per library for this session, so reopening a
/// library does not fetch the resolution and language lists again.
final Map<String, List<QuickFilter>> _quickFiltersByLibrary = {};

Future<List<QuickFilter>> resolveQuickFilters(
  List<MediaFilter> filters,
  Future<List<MediaFilterValue>> Function(MediaFilter field) valuesOf, {
  String? cacheKey,
}) async {
  final lang = LocaleSettings.currentLocale.languageCode;
  final key = cacheKey == null ? null : '$cacheKey:$lang:${filters.length}';
  final cached = key == null ? null : _quickFiltersByLibrary[key];
  if (cached != null) return cached;
  final result = await _resolveQuickFilters(filters, valuesOf, lang);
  if (key != null) {
    if (_quickFiltersByLibrary.length > 50) _quickFiltersByLibrary.clear();
    _quickFiltersByLibrary[key] = result;
  }
  return result;
}

Future<List<QuickFilter>> _resolveQuickFilters(
  List<MediaFilter> filters,
  Future<List<MediaFilterValue>> Function(MediaFilter field) valuesOf,
  String lang,
) async {
  final result = <QuickFilter>[];

  final unwatched = _findField(filters, const ['unwatched', 'unwatchedLeaves'], where: (f) => f.isBoolean);
  if (unwatched != null) {
    result.add(
      QuickFilter(
        kind: QuickFilterKind.unwatched,
        field: unwatched,
        op: LibraryFilterOperator.is_,
        value: '1',
        label: FilterStrings.unwatched,
      ),
    );
  }

  Future<MediaFilterValue?> matchValue(MediaFilter field, bool Function(String id, String title) test) async {
    try {
      for (final v in await valuesOf(field)) {
        final id = libraryFilterValueId(v.key, _bareField(field)).toLowerCase();
        if (test(id, v.title.toLowerCase().trim())) return v;
      }
    } catch (e) {
      appLogger.d('Quick filter values for ${field.filter} unavailable', error: e);
    }
    return null;
  }

  final resolution = _findField(filters, const ['resolution'], where: (f) => f.hasValueList);
  if (resolution != null) {
    final v = await matchValue(resolution, (id, title) => id == '4k' || title == '4k' || title.startsWith('4k '));
    if (v != null) {
      result.add(
        QuickFilter(
          kind: QuickFilterKind.uhd,
          field: resolution,
          op: LibraryFilterOperator.is_,
          value: libraryFilterValueId(v.key, _bareField(resolution)),
          valueTitle: v.title,
          label: FilterStrings.uhd,
        ),
      );
    }
  }

  final hdr = _findField(filters, const ['hdr'], where: (f) => f.isBoolean);
  if (hdr != null) {
    result.add(
      QuickFilter(kind: QuickFilterKind.hdr, field: hdr, op: LibraryFilterOperator.is_, value: '1', label: FilterStrings.hdr),
    );
  }

  // Audio: a chooser of every language the library has, the app's language
  // listed first.
  final aliases = _languageAliases[lang] ?? [lang];
  final audio = _findField(filters, const ['audioLanguage'], where: (f) => f.hasValueList);
  if (audio != null) {
    List<MediaFilterValue> values = const [];
    try {
      values = await valuesOf(audio);
    } catch (e) {
      appLogger.d('Quick filter values for ${audio.filter} unavailable', error: e);
    }
    final choices = [
      for (final v in values)
        if (v.title.trim().isNotEmpty) (id: libraryFilterValueId(v.key, _bareField(audio)), title: v.title.trim()),
    ];
    bool isAppLanguage(({String id, String title}) c) =>
        aliases.contains(c.id.toLowerCase()) || aliases.contains(c.title.toLowerCase());
    choices.sort((a, b) {
      final pa = isAppLanguage(a) ? 0 : 1;
      final pb = isAppLanguage(b) ? 0 : 1;
      return pa != pb ? pa - pb : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    if (choices.isNotEmpty) {
      result.add(
        QuickFilter(
          kind: QuickFilterKind.audio,
          field: audio,
          op: LibraryFilterOperator.is_,
          value: choices.first.id,
          label: FilterStrings.audioAny,
          choices: choices,
        ),
      );
    }
  }

  final added = _findField(
    filters,
    const ['addedAt'],
    where: (f) => f.editorKind == FilterEditorKind.date && f.operators.contains(LibraryFilterOperator.atLeast),
  );
  if (added != null) {
    result.add(
      QuickFilter(
        kind: QuickFilterKind.recent,
        field: added,
        op: LibraryFilterOperator.atLeast,
        value: '-30d',
        label: FilterStrings.recent,
      ),
    );
  }

  return result;
}

/// A named filter selection plus sort, saved per library.
class SavedFilterSet {
  final String name;
  final List<LibraryFilter> filters;
  final String? sortKey;
  final bool descending;

  const SavedFilterSet({required this.name, required this.filters, this.sortKey, this.descending = false});

  Map<String, Object?> toJson() => {
    'name': name,
    'filters': encodeLibraryFilterSelection(filters),
    'sort': ?sortKey,
    'desc': descending,
  };

  static SavedFilterSet? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.isEmpty) return null;
    final filters = raw['filters'];
    return SavedFilterSet(
      name: name,
      filters: filters is String ? decodeLibraryFilterSelection(filters) : const [],
      sortKey: raw['sort'] as String?,
      descending: raw['desc'] == true,
    );
  }
}

/// Saved filter sets, one list per library.
abstract final class SavedFilterSets {
  static String _key(String libraryKey) => 'retro_saved_filter_sets_$libraryKey';

  static Future<List<SavedFilterSet>> load(String libraryKey) async {
    final storage = await StorageService.getInstance();
    final raw = storage.prefs.getString(_key(libraryKey));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      return decoded.map(SavedFilterSet.fromJson).whereType<SavedFilterSet>().toList();
    } catch (e) {
      appLogger.w('Saved filter sets unreadable for $libraryKey', error: e);
      return const [];
    }
  }

  static Future<void> save(String libraryKey, List<SavedFilterSet> sets) async {
    final storage = await StorageService.getInstance();
    if (sets.isEmpty) {
      await storage.prefs.remove(_key(libraryKey));
      return;
    }
    await storage.prefs.setString(_key(libraryKey), json.encode(sets.map((s) => s.toJson()).toList()));
  }

  /// Adds [set], replacing one with the same name (case-insensitive).
  static Future<void> upsert(String libraryKey, SavedFilterSet set) async {
    final sets = [...await load(libraryKey)];
    sets.removeWhere((s) => s.name.toLowerCase() == set.name.toLowerCase());
    sets.add(set);
    await save(libraryKey, sets);
  }

  static Future<void> remove(String libraryKey, String name) async {
    final sets = [...await load(libraryKey)]..removeWhere((s) => s.name == name);
    await save(libraryKey, sets);
  }
}
