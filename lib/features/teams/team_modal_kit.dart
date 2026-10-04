import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/team_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass_chrome.dart' show kOnAmber;
import '../sprint/modals/glass_modal.dart' show showGlassModal;
import 'team_widgets.dart';

// ════════════════════════════════════════════════════════════════════════
//  Shared building blocks for the Teams modals. Every modal is presented on
//  the app's signature Liquid-Glass material (via [showGlassModal]), which is
//  a blurred, tinted card on a wide screen and a bottom sheet on a phone. The
//  shell pins the header & footer and scrolls the body so it never overflows;
//  controls use translucent fills so the glass reads through.
// ════════════════════════════════════════════════════════════════════════

/// Translucent control fill so the Liquid-Glass panel shows through.
Color get _fill => AppColors.surface.withValues(alpha: 0.7);
Color get _fillSoft => AppColors.surface.withValues(alpha: 0.5);

/// Presents [pageChild] on the shared Liquid-Glass modal material. Returns the
/// value the body pops with.
Future<T?> showTeamModal<T>(
  BuildContext context,
  Widget pageChild, {
  double width = 560,
}) {
  return showGlassModal<T>(context, width: width, builder: (_) => pageChild);
}

/// Header (icon · title/subtitle · close) + scrolling body + pinned footer.
class ModalShell extends StatelessWidget {
  const ModalShell({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.footer,
    this.subtitle,
    this.iconColor,
    this.iconBg,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget footer;
  final Color? iconColor;
  final Color? iconBg;

  @override
  Widget build(BuildContext context) {
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.86).clamp(
      0.0,
      760.0,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBg ?? AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? AppColors.accentStrong,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppTheme.fontBrand,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.t('common.close'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.hairline2),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: body,
            ),
          ),
          Divider(height: 1, color: AppColors.hairline2),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SafeArea(top: false, child: footer),
          ),
        ],
      ),
    );
  }
}

/// "Cancel" + a primary action, right-aligned, wrapping on narrow widths.
class ModalFooter extends StatelessWidget {
  const ModalFooter({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryIcon,
    this.leadingIcon,
    this.leadingLabel,
    this.onLeading,
    this.leadingDanger = false,
    this.danger = false,
    this.busy = false,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final IconData? primaryIcon;

  /// Optional left-aligned secondary action (e.g. Back / Remove). Rendered as
  /// an icon + label when there's room, and collapses to an icon-only button
  /// on narrow (mobile) footers so the label never wraps.
  final IconData? leadingIcon;
  final String? leadingLabel;
  final VoidCallback? onLeading;
  final bool leadingDanger;

  final bool danger;
  final bool busy;

  Widget? _buildLeading(BuildContext context, {required bool compact}) {
    if (onLeading == null || leadingIcon == null) return null;
    final color = leadingDanger ? AppColors.danger : AppColors.inkSoft;
    final onPressed = busy ? null : onLeading;
    if (compact) {
      return IconButton(
        onPressed: onPressed,
        tooltip: leadingLabel,
        visualDensity: VisualDensity.compact,
        icon: Icon(leadingIcon, size: 18, color: color),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(leadingIcon, size: 16, color: color),
      label: Text(
        leadingLabel ?? '',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Below this the leading label would wrap against Cancel + primary, so
        // collapse it to an icon. Desktop modals (560px) stay labelled.
        final compact = c.maxWidth < 420;
        final leading = _buildLeading(context, compact: compact);
        return Row(
          children: [
            // A single expander between the (optional) leading action and the
            // trailing buttons guarantees Cancel + primary sit flush against
            // the right gutter (two competing flex widgets left a gap).
            if (leading != null)
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: leading,
                ),
              )
            else
              const Spacer(),
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).maybePop(),
              child: Text(
                context.t('common.cancel'),
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: busy ? null : onPrimary,
              style: FilledButton.styleFrom(
                backgroundColor: danger ? AppColors.danger : AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(primaryIcon ?? LucideIcons.check, size: 16),
              label: Text(primaryLabel, overflow: TextOverflow.ellipsis),
            ),
          ],
        );
      },
    );
  }
}

/// A field label above its control.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key, this.optional = false});
  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: 6),
            Text(
              '· ${context.t('teams.optional')}',
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}

/// Member / Team-Admin segmented control used in member modals.
class RoleSegmented extends StatelessWidget {
  const RoleSegmented({
    super.key,
    required this.role,
    required this.onChanged,
    this.adminDisabled = false,
  });

  final TeamRole role;
  final ValueChanged<TeamRole> onChanged;
  final bool adminDisabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          _seg(
            context,
            TeamRole.member,
            LucideIcons.user,
            context.t('teams.role.member'),
            false,
          ),
          const SizedBox(width: 6),
          _seg(
            context,
            TeamRole.admin,
            LucideIcons.shieldCheck,
            context.t('teams.role.admin'),
            adminDisabled,
          ),
        ],
      ),
    );
  }

  Widget _seg(
    BuildContext context,
    TeamRole value,
    IconData icon,
    String label,
    bool disabled,
  ) {
    final on = role == value;
    // The disabled fade is baked into each colour rather than laid over the
    // segment with an Opacity, which would composite it in a layer of its own.
    Color fade(Color c) => disabled ? c.withValues(alpha: c.a * 0.4) : c;
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        enabled: !disabled,
        child: Material(
          color: on ? fade(AppColors.surface) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: disabled ? null : () => onChanged(value),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: on
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: disabled ? 0.06 * 0.4 : 0.06,
                          ),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    )
                  : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: fade(on ? AppColors.ink : AppColors.inkSoft),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: fade(on ? AppColors.ink : AppColors.inkSoft),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Color swatch row.
class ColorPicker extends StatelessWidget {
  const ColorPicker({super.key, required this.hue, required this.onChanged});

  final int hue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // 30×30 targets 8 points apart: above the 24-point floor of WCAG 2.5.8.
    // A 48-point ring would spread the row.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in teamSwatches)
          Semantics(
            button: true,
            selected: hue == s.hue,
            label: context.t(s.nameKey),
            // The fill sits under its own transparent Material so the press
            // ripple shows on top of the colour rather than under it.
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: teamHueColor(s.hue),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: hue == s.hue ? AppColors.ink : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => onChanged(s.hue),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Icon picker grid (wraps; never overflows).
class IconPicker extends StatelessWidget {
  const IconPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final name in teamIconNames)
          () {
            final on = selected == name;
            // 34×34 targets 6 points apart: above the 24-point floor of WCAG
            // 2.5.8; 48 would turn the grid into a much taller block.
            return Semantics(
              button: true,
              selected: on,
              label: context.t(teamIconLabelKey(name)),
              child: Material(
                color: on ? AppColors.accentSoft : _fill,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  onTap: () => onChanged(name),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: on ? AppColors.accent : AppColors.hairline,
                      ),
                    ),
                    child: Icon(
                      teamIcon(name),
                      size: 17,
                      color: on ? AppColors.accentStrong : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

/// Generic selectable row used for people & project checklists.
class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    this.subtitle,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    // A checklist row: the title inside names it, this says it is a check
    // box and whether it is ticked.
    return Semantics(
      checked: selected,
      child: Material(
        color: selected ? AppColors.accentSoft : _fill,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: selected ? AppColors.accentLine : AppColors.hairline,
              ),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkSoft,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _CheckBox(on: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: on ? AppColors.accent : AppColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: on ? AppColors.accent : AppColors.hairline),
      ),
      child: on
          ? const Icon(LucideIcons.check, size: 14, color: kOnAmber)
          : null,
    );
  }
}

/// Three-way access option (All / Specific / None) — radio-style rows + an
/// inline project checklist when "Specific" is chosen.
class AccessPicker extends StatelessWidget {
  const AccessPicker({
    super.key,
    required this.team,
    required this.projects,
    required this.scope,
    required this.pickedIds,
    required this.onScope,
    required this.onTogglePick,
    required this.projectName,
    required this.projectKey,
    required this.projectColor,
    this.projectAvatar,
  });

  final Team team;
  final List<String> projects; // project ids owned by the team
  final AccessScope scope;
  final List<String> pickedIds;
  final ValueChanged<AccessScope> onScope;
  final ValueChanged<String> onTogglePick;
  final String Function(String id) projectName;
  final String Function(String id) projectKey;
  final Color Function(String id) projectColor;

  /// The project's picture URL, when the caller can resolve one. Optional so a
  /// caller that only knows keys and colours still compiles.
  final String? Function(String id)? projectAvatar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _option(
          context,
          AccessScope.all,
          LucideIcons.layers,
          context.t('teams.access.all'),
          context.t(
            'teams.access.allHint',
            variables: {'count': '${projects.length}'},
          ),
        ),
        const SizedBox(height: 7),
        _option(
          context,
          AccessScope.some,
          LucideIcons.folderOpen,
          context.t('teams.access.some'),
          context.t('teams.access.someHint'),
        ),
        const SizedBox(height: 7),
        _option(
          context,
          AccessScope.none,
          LucideIcons.lock,
          context.t('teams.access.none'),
          context.t('teams.access.noneHint'),
        ),
        if (scope == AccessScope.some) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _fillSoft,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: projects.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      context.t('teams.noProjectsYet'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < projects.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        CheckRow(
                          selected: pickedIds.contains(projects[i]),
                          onTap: () => onTogglePick(projects[i]),
                          leading: ProjectKeyGlyph(
                            label: projectKey(projects[i]),
                            color: projectColor(projects[i]),
                            avatarUrl: projectAvatar?.call(projects[i]),
                            size: 30,
                            radius: 8,
                            fontSize: 11,
                          ),
                          title: projectName(projects[i]),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _option(
    BuildContext context,
    AccessScope value,
    IconData icon,
    String title,
    String hint,
  ) => _ScopeOption(
    on: scope == value,
    icon: icon,
    title: title,
    hint: hint,
    onTap: () => onScope(value),
  );
}

/// One radio-style scope row shared by the project and knowledge pickers:
/// icon tile, title and hint, radio. A null [onTap] shows it disabled.
class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.on,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final bool on;
  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      child: Opacity(
        opacity: disabled ? 0.55 : 1,
        child: Material(
          color: on ? AppColors.accentSoft : _fill,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(
                  color: on ? AppColors.accent : AppColors.hairline,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: on ? AppColors.surface : _fillSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: 17,
                      color: on ? AppColors.accentStrong : AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          hint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Radio(on: on),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Knowledge-base access for a membership: none (the default), every page of
/// the team, or selected pages — the last one as a one-line field that opens
/// the page picker, never an inline list.
///
/// Team-Admins read every page of their team whatever is stored here, so with
/// [adminReadsAll] the rows are disabled and a note says why.
class KnowledgeAccessPicker extends StatelessWidget {
  const KnowledgeAccessPicker({
    super.key,
    required this.scope,
    required this.pickedCount,
    required this.onScope,
    required this.onPickPages,
    this.adminReadsAll = false,
  });

  final AccessScope scope;
  final int pickedCount;
  final ValueChanged<AccessScope> onScope;

  /// Opens the page picker anchored to the field's global rect.
  final void Function(Rect anchorRect) onPickPages;
  final bool adminReadsAll;

  @override
  Widget build(BuildContext context) {
    final enabled = !adminReadsAll;
    VoidCallback? pick(AccessScope s) => enabled ? () => onScope(s) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (adminReadsAll) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 14, color: AppColors.inkFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.t('teams.knowledge.adminReadsAll'),
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
        ],
        _ScopeOption(
          on: enabled && scope == AccessScope.none,
          icon: LucideIcons.lock,
          title: context.t('teams.knowledge.none'),
          hint: context.t('teams.knowledge.noneHint'),
          onTap: pick(AccessScope.none),
        ),
        const SizedBox(height: 7),
        _ScopeOption(
          on: !enabled || scope == AccessScope.all,
          icon: LucideIcons.bookOpen,
          title: context.t('teams.knowledge.all'),
          hint: context.t('teams.knowledge.allHint'),
          onTap: pick(AccessScope.all),
        ),
        const SizedBox(height: 7),
        _ScopeOption(
          on: enabled && scope == AccessScope.some,
          icon: LucideIcons.files,
          title: context.t('teams.knowledge.some'),
          hint: context.t('teams.knowledge.someHint'),
          onTap: pick(AccessScope.some),
        ),
        if (enabled && scope == AccessScope.some) ...[
          const SizedBox(height: 10),
          _PagesField(count: pickedCount, onTap: onPickPages),
        ],
      ],
    );
  }
}

/// "3 pages selected ›" — the one-line field in front of the page picker.
class _PagesField extends StatelessWidget {
  const _PagesField({required this.count, required this.onTap});

  final int count;
  final void Function(Rect anchorRect) onTap;

  @override
  Widget build(BuildContext context) {
    final label = count == 0
        ? context.t('teams.knowledge.choosePages')
        : context.t(
            'teams.knowledge.pagesPicked',
            variables: {'count': '$count'},
            count: count,
          );
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        onTap: () {
          final box = context.findRenderObject() as RenderBox?;
          onTap(
            (box != null && box.hasSize)
                ? box.localToGlobal(Offset.zero) & box.size
                : Rect.zero,
          );
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: _fillSoft,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.files, size: 16, color: AppColors.inkSoft),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: count == 0 ? AppColors.inkSoft : AppColors.ink,
                  ),
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline chip for the member list: "Knowledge: all / 3 pages / none".
class KnowledgeAccessChip extends StatelessWidget {
  const KnowledgeAccessChip({super.key, required this.membership});

  final TeamMembership membership;

  @override
  Widget build(BuildContext context) {
    final k = membership.knowledge;
    final (IconData icon, Color color, String value) = membership.isAdmin
        ? (
            LucideIcons.bookOpen,
            AppColors.stDone,
            context.t('teams.knowledge.chipAll'),
          )
        : switch (k.scope) {
            AccessScope.all => (
              LucideIcons.bookOpen,
              AppColors.stDone,
              context.t('teams.knowledge.chipAll'),
            ),
            AccessScope.some => (
              LucideIcons.files,
              AppColors.accentStrong,
              context.t(
                'teams.knowledge.chipSome',
                // The count, not the ids: those reach only the team's admins.
                variables: {'count': '${k.count}'},
                count: k.count,
              ),
            ),
            AccessScope.none => (
              LucideIcons.bookLock,
              AppColors.inkSoft,
              context.t('teams.knowledge.chipNone'),
            ),
          };
    final label = context.t(
      'teams.knowledge.chip',
      variables: {'value': value},
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: on ? AppColors.accent : AppColors.hairline,
          width: 2,
        ),
      ),
      child: on
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

/// The text field style shared by the team modals.
InputDecoration teamFieldDecoration(BuildContext context, {String? hint}) =>
    InputDecoration(
      isDense: true,
      hintText: hint,
      filled: true,
      fillColor: _fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        borderSide: BorderSide(color: AppColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        borderSide: BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    );
