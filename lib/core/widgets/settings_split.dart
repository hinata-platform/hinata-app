import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, LiquidRoundedSuperellipse;

import '../../features/search/search_tokens.dart';
import '../responsive/responsive.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_type.dart';
import 'glass_panel.dart';

/// One section of a settings page, as the wide layout's rail lists it.
class SettingsNavEntry<T> {
  const SettingsNavEntry({
    required this.id,
    required this.icon,
    required this.label,
    this.group,
    this.trailing,
  });

  final T id;
  final IconData icon;

  /// Already translated.
  final String label;

  /// The heading the entry is listed under, already translated; entries with
  /// the same group sit together, in the order they are given.
  final String? group;

  /// A glyph after the label, e.g. for an entry that leaves the page.
  final IconData? trailing;
}

/// A settings page on a wide window: the sections in a glass rail on the
/// left, the one that is open on the right (HIN-110).
///
/// The rule it carries out is progressive disclosure. A settings page shows
/// what the reader came for and keeps the rest one labelled step away; a wall
/// of every card at once, as account, organization and project settings were
/// on a desktop, makes the reader scan a dozen sections to find one switch.
/// The admin area used this layout first; the others share it, so every
/// settings page in the app works the same way.
///
/// On a phone each page keeps its own list-then-section navigation; this is
/// only the wide form.
class SettingsSplitLayout<T> extends StatelessWidget {
  const SettingsSplitLayout({
    super.key,
    required this.header,
    required this.entries,
    required this.selected,
    required this.onSelect,
    required this.body,
    this.bodyScrolls = true,
    this.bodyMaxWidth = 980,
  });

  /// The rail's head: the page's name and, optionally, a mark beside it.
  final Widget header;
  final List<SettingsNavEntry<T>> entries;
  final T selected;
  final ValueChanged<T> onSelect;

  /// The open section.
  final Widget body;

  /// False when [body] scrolls itself (a paged list); it then gets the whole
  /// pane.
  final bool bodyScrolls;

  /// How wide a section may grow: forms and switches read badly across a
  /// 2000-point window.
  final double bodyMaxWidth;

  @override
  Widget build(BuildContext context) {
    final top = context.topGutter + 14;
    final bottom = context.bottomGutter + 14;
    final pane = Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: bodyMaxWidth),
        child: body,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(0, top, 18, bottom),
            child: SizedBox(
              // Wide enough for a long German compound
              // ("Abwesenheitsmanagement") on one line beside its icon.
              width: 272,
              child: SettingsNavRail<T>(
                header: header,
                entries: entries,
                selected: selected,
                onSelect: onSelect,
              ),
            ),
          ),
          Expanded(
            child: bodyScrolls
                // The iOS numeric keypad has no Done key: tap-outside and
                // drag both put the keyboard away.
                ? GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(0, top, 0, bottom + 14),
                      child: pane,
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.only(top: top),
                    child: pane,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Ambient shadow for the docked rail, kept inside the page gutter so its
/// soft edge is never cut into a hard line by the content clip.
const List<BoxShadow> _kRailShadowLight = [
  BoxShadow(
    color: Color.fromRGBO(20, 18, 45, 0.13),
    offset: Offset(0, 12),
    blurRadius: 30,
    spreadRadius: -10,
  ),
  BoxShadow(
    color: Color.fromRGBO(20, 18, 45, 0.07),
    offset: Offset(0, 2),
    blurRadius: 8,
    spreadRadius: -3,
  ),
];

const List<BoxShadow> _kRailShadowDark = [
  BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.40),
    offset: Offset(0, 14),
    blurRadius: 34,
    spreadRadius: -14,
  ),
  BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.28),
    offset: Offset(0, 2),
    blurRadius: 8,
    spreadRadius: -4,
  ),
];

/// The rail of a [SettingsSplitLayout]: a floating glass panel with a head
/// and the grouped sections, the open one washed amber.
class SettingsNavRail<T> extends StatelessWidget {
  const SettingsNavRail({
    super.key,
    required this.header,
    required this.entries,
    required this.selected,
    required this.onSelect,
  });

  final Widget header;
  final List<SettingsNavEntry<T>> entries;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    final groups = <String?, List<SettingsNavEntry<T>>>{};
    for (final e in entries) {
      groups.putIfAbsent(e.group, () => []).add(e);
    }
    return GlassPanelShadow(
      radius: BorderRadius.circular(24),
      shadows: dark ? _kRailShadowDark : _kRailShadowLight,
      child: GlassContainer(
        useOwnLayer: true,
        quality: kPanelGlassQuality,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: 24),
        settings: liquidGlassPanelSettings(
          glassFill: tokens.glassFill,
          dark: dark,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 16, 15),
                child: header,
              ),
              Divider(height: 1, color: tokens.hairline),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
                  children: [
                    for (final group in groups.entries) ...[
                      if (group.key != null)
                        _NavGroup(label: group.key!, color: tokens.inkFaint),
                      for (final entry in group.value)
                        _NavItem<T>(
                          entry: entry,
                          active: entry.id == selected,
                          onTap: () => onSelect(entry.id),
                          tokens: tokens,
                        ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The head most settings rails use: the page's name and a line under it.
class SettingsRailHeader extends StatelessWidget {
  const SettingsRailHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 11)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: tokens.ink,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.caption,
                    height: 1.25,
                    color: tokens.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NavGroup extends StatelessWidget {
  const _NavGroup({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: Semantics(
      header: true,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: AppType.caption,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 1.2,
        ),
      ),
    ),
  );
}

class _NavItem<T> extends StatelessWidget {
  const _NavItem({
    required this.entry,
    required this.active,
    required this.onTap,
    required this.tokens,
  });

  final SettingsNavEntry<T> entry;
  final bool active;
  final VoidCallback onTap;
  final SearchTokens tokens;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: Semantics(
          button: true,
          selected: active,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.fromLTRB(9, 9, 12, 9),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.accent.withValues(alpha: dark ? 0.22 : 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  // A short amber bar flags the open section, so it never
                  // rests on the wash's colour alone.
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.accentStrong
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    entry.icon,
                    size: 17,
                    color: active ? AppColors.accentInk : tokens.inkSoft,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      entry.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.label,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: active ? AppColors.accentInk : tokens.ink,
                      ),
                    ),
                  ),
                  if (entry.trailing != null)
                    Icon(entry.trailing, size: 12, color: tokens.inkFaint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
