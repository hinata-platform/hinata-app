import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The fixed grouping order of the palette: the client's commands first, then
/// the server's categories in the order of its `SearchCategory`.
enum SearchCat {
  commands,
  issues,
  comments,
  projects,
  teams,
  people,
  boards,
  docs,
  attachments,
  shifts,
  time,
  absences,
  billing,
}

/// Per-category icon + i18n label key (mirrors `GS_CAT`).
class SearchCatMeta {
  const SearchCatMeta(this.icon, this.labelKey);
  final IconData icon;
  final String labelKey;
}

const Map<SearchCat, SearchCatMeta> kSearchCatMeta = {
  SearchCat.commands: SearchCatMeta(LucideIcons.command, 'search.cat.commands'),
  SearchCat.issues: SearchCatMeta(LucideIcons.circleDot, 'search.cat.issues'),
  SearchCat.comments: SearchCatMeta(
    LucideIcons.messageSquare,
    'search.cat.comments',
  ),
  SearchCat.projects: SearchCatMeta(
    LucideIcons.squareKanban,
    'search.cat.projects',
  ),
  SearchCat.teams: SearchCatMeta(LucideIcons.usersRound, 'search.cat.teams'),
  SearchCat.people: SearchCatMeta(LucideIcons.users, 'search.cat.people'),
  SearchCat.boards: SearchCatMeta(LucideIcons.columns3, 'search.cat.boards'),
  SearchCat.docs: SearchCatMeta(LucideIcons.bookOpen, 'search.cat.docs'),
  SearchCat.attachments: SearchCatMeta(
    LucideIcons.paperclip,
    'search.cat.attachments',
  ),
  SearchCat.shifts: SearchCatMeta(
    LucideIcons.calendarClock,
    'search.cat.shifts',
  ),
  SearchCat.time: SearchCatMeta(LucideIcons.timer, 'search.cat.time'),
  SearchCat.absences: SearchCatMeta(
    LucideIcons.calendarOff,
    'search.cat.absences',
  ),
  SearchCat.billing: SearchCatMeta(LucideIcons.coins, 'search.cat.billing'),
};

/// The modules a server has switched on, as far as the palette cares.
///
/// A category or a command of a module that is off is not offered at all:
/// the server would answer nothing for it, and a scope chip that can only ever
/// be empty is a question nobody can get an answer to.
@immutable
class SearchModules {
  const SearchModules({
    this.advancedTime = false,
    this.absences = false,
    this.billing = false,
    this.shifts = false,
  });

  final bool advancedTime;
  final bool absences;
  final bool billing;
  final bool shifts;
}

/// The categories a reader can scope the palette to on this server, in order.
///
/// Time entries are searchable on every server, the module's timesheets only
/// with it on, so the time chip is always there. Budgets belong to the
/// extended module and rates to billing, which is only ever on with it.
List<SearchCat> availableSearchCats(SearchModules modules) => [
  for (final cat in SearchCat.values)
    if (switch (cat) {
      SearchCat.shifts => modules.shifts,
      SearchCat.absences => modules.absences,
      SearchCat.billing => modules.advancedTime || modules.billing,
      _ => true,
    })
      cat,
];

/// Parses a server category name (any case); null for one this app does not
/// know, which a newer server may well send.
SearchCat? searchCatFromName(String name) {
  final lower = name.toLowerCase();
  for (final cat in SearchCat.values) {
    if (cat.name == lower) return cat;
  }
  return null;
}

/// One row in the search index. Display data is precomputed off the real
/// models when the index is built; [onSelect] performs the navigation/command.
class SearchEntry {
  SearchEntry({
    required this.cat,
    required this.key,
    required this.title,
    required this.keys,
    required this.onSelect,
    this.closesOnSelect = true,
    this.subtitle,
    this.leadingIcon,
    this.issueType,
    this.statusColor,
    this.statusName,
    this.mono,
    this.avatarName,
    this.avatarUrl,
    this.memberNames,
    this.keyChipText,
    this.keyChipColor,
    this.hint,
    this.archived = false,
    this.leadingColor,
    this.muted = false,
  });

  final SearchCat cat;

  /// Stable identity for the row (used as the keyboard-selection key).
  final String key;

  final String title;

  /// Lowercased haystack: title + id + tags + assignee + type + state.
  final String keys;

  /// Runs the result/command. Receives a context that is still mounted under
  /// the app (the dialog is dismissed by the caller before/with navigation).
  final void Function(BuildContext context) onSelect;

  /// Whether activating this entry dismisses the palette. Commands that mutate
  /// in place (e.g. toggle appearance) keep it open, mirroring search.jsx.
  final bool closesOnSelect;

  // ---- per-category display data ----
  final String? subtitle;

  /// Leading tile glyph (docs / boards / commands).
  final IconData? leadingIcon;

  /// Issue type for the tinted [TypeGlyph] leading tile.
  final String? issueType;

  /// Issue status dot + name (issue subtitle).
  final Color? statusColor;
  final String? statusName;

  /// Monospace id shown in the issue subtitle (e.g. `HIV-241`).
  final String? mono;

  /// Trailing single avatar (issue assignee / person leading).
  final String? avatarName;
  final String? avatarUrl;

  /// Trailing avatar stack (project members).
  final List<String>? memberNames;

  /// Project hex key chip.
  final String? keyChipText;
  final Color? keyChipColor;

  /// Command keyboard hint (e.g. `C`).
  final String? hint;

  /// Archived (soft-deleted) issue / archived project — rendered with an
  /// "Archived" badge.
  final bool archived;

  /// Tint of the leading glyph, where the hit brings a colour of its own (a
  /// team, a space, an absence type).
  final Color? leadingColor;

  /// A hit that no longer applies (a cancelled shift): drawn quieter.
  final bool muted;
}
