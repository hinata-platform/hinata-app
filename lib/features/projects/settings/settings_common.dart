import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/hue_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../../core/widgets/soft_card.dart';
import '../../search/search_tokens.dart';
import '../../sprint/modals/glass_modal.dart';

/// One settings card: a [SoftCard] with a [SectionHeader] and body, spaced like
/// the design's `.ps-block`.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.child,
    this.note,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String? note;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionHeader(
                  title: title,
                  actionLabel: actionLabel,
                  onAction: onAction,
                ),
              ),
              ?trailing,
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.inkSoft,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Field label with an optional "required" pill, mirroring `.ps-field label`.
class FieldLabel extends StatelessWidget {
  const FieldLabel({super.key, required this.text, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          if (required) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                context.t('projectSettings.required'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.accentStrong,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small color dot that, when tapped, opens a Liquid Glass hue popover
/// anchored exactly at the dot (like a popup-menu button). Picking a hue calls
/// [onPick].
class GlassHuePicker extends StatelessWidget {
  const GlassHuePicker({
    super.key,
    required this.hue,
    required this.onPick,
    this.hues = kLabelHues,
    this.size = 14,
  });

  final int hue;
  final ValueChanged<int> onPick;
  final List<int> hues;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Builder gives a context whose RenderObject is this dot, so the popover can
    // be positioned precisely at the tap point.
    return Builder(
      builder: (dotContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final box = dotContext.findRenderObject() as RenderBox?;
          if (box == null) return;
          final picked = await _showGlassColorPopover(
            dotContext,
            anchor: box,
            current: hue,
            hues: hues,
          );
          if (picked != null) onPick(picked);
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: hueColor(hue),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 1,
                spreadRadius: 0.3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a Liquid Glass color popover anchored at [anchor]'s global rect
/// (clamped to the screen). Returns the chosen hue, or null on dismiss.
Future<int?> _showGlassColorPopover(
  BuildContext context, {
  required RenderBox anchor,
  required int current,
  required List<int> hues,
}) {
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
  final dotTopLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final dotSize = anchor.size;
  final screen = overlay.size;

  const w = 220.0;
  const estH = 168.0;
  const pad = 12.0;
  const gap = 8.0;

  double left = (dotTopLeft.dx - 6).clamp(pad, screen.width - w - pad);
  double top = dotTopLeft.dy + dotSize.height + gap;
  if (top + estH > screen.height - pad) {
    top = (dotTopLeft.dy - estH - gap).clamp(pad, screen.height - estH - pad);
  }

  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'color',
    barrierColor: Colors.transparent,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, _, _) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: _GlassColorCard(current: current, hues: hues, width: w),
        ),
      ],
    ),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.9, end: 1.0).animate(curved),
          alignment: Alignment.topLeft,
          child: child,
        ),
      );
    },
  );
}

class _GlassColorCard extends StatelessWidget {
  const _GlassColorCard({
    required this.current,
    required this.hues,
    required this.width,
  });

  final int current;
  final List<int> hues;
  final double width;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    return GlassPanelShadow(
      radius: BorderRadius.circular(20),
      shadows: tokens.panelShadow,
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        settings:
            liquidGlassPanelSettings(glassFill: tokens.glassFill, dark: dark),
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('projectSettings.chooseColor'),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: tokens.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final h in hues)
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(h),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: hueColor(h),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: h == current
                                    ? tokens.ink
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: h == current
                                ? const Icon(
                                    LucideIcons.check,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : null,
                          ),
                        ),
                    ],
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

/// Multi-select people picker for adding project members, presented in the
/// app's Liquid Glass modal (same material as the sprint/team modals). Returns
/// the chosen user ids, or null on cancel.
Future<List<String>?> showMemberPicker(
  BuildContext context, {
  required List<DirectoryUser> candidates,
  required String projectName,
}) {
  return showGlassModal<List<String>>(
    context,
    width: 520,
    builder: (modalContext) =>
        _MemberPicker(candidates: candidates, projectName: projectName),
  );
}

class _MemberPicker extends StatefulWidget {
  const _MemberPicker({required this.candidates, required this.projectName});

  final List<DirectoryUser> candidates;
  final String projectName;

  @override
  State<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<_MemberPicker> {
  final _selected = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.candidates.where((u) {
      final q = _query.toLowerCase();
      return q.isEmpty ||
          u.displayName.toLowerCase().contains(q) ||
          (u.title ?? '').toLowerCase().contains(q);
    }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.userPlus,
          title: context.t('projectSettings.addMembers'),
          subtitle: context.t(
            'projectSettings.addMembersSub',
            variables: {'name': widget.projectName},
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: glassInputDecoration(
              hint: context.t('projectSettings.searchPeople'),
            ).copyWith(
              prefixIcon: Icon(
                LucideIcons.search,
                size: 18,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      context.t('projectSettings.everyoneMember'),
                      style: TextStyle(color: AppColors.inkSoft),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final u = filtered[i];
                    return _MemberRow(
                      user: u,
                      selected: _selected.contains(u.id),
                      onTap: () => setState(
                        () => _selected.contains(u.id)
                            ? _selected.remove(u.id)
                            : _selected.add(u.id),
                      ),
                    );
                  },
                ),
        ),
        GlassModalFooter(
          confirmLabel: _selected.isEmpty
              ? context.t('projectSettings.add')
              : context.t(
                  'projectSettings.addN',
                  variables: {'count': '${_selected.length}'},
                ),
          confirmIcon: LucideIcons.userPlus,
          onConfirm: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
        ),
      ],
    );
  }
}

/// One selectable person row on the glass material — avatar, name, role and a
/// rounded check box (filled when selected), matching the design.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  final DirectoryUser user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: selected ? AppColors.accentLine : AppColors.hairline,
              ),
            ),
            child: Row(
              children: [
                HiveAvatar(
                  name: user.displayName,
                  imageUrl: user.avatarUrl,
                  size: 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (user.title != null)
                        Text(
                          user.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
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
        color: on ? AppColors.accent : AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: on ? AppColors.accent : AppColors.hairline2),
      ),
      child: on
          ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// Brief toast feedback (mirrors the reference's `H.toast`).
void settingsToast(
  BuildContext context,
  String message, {
  GlassToastKind kind = GlassToastKind.info,
}) {
  showGlassToast(context, message, kind: kind);
}

/// Shared input decoration matching `.ps-input`.
InputDecoration settingsInput(
  BuildContext context, {
  String? hint,
  bool error = false,
  Widget? suffix,
}) {
  return InputDecoration(
    isDense: true,
    hintText: hint,
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      borderSide: BorderSide(
        color: error ? AppColors.danger : AppColors.hairline,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      borderSide: BorderSide(
        color: error ? AppColors.danger : AppColors.accent,
        width: 1.6,
      ),
    ),
  );
}

/// Liquid Glass dialog shown when the user tries to delete a workflow state
/// that still has issues. Forces them to pick a target state to migrate the
/// issues into; returns the chosen target state id, or null on cancel.
Future<String?> showStateMigrationDialog(
  BuildContext context, {
  required String stateName,
  required int issueCount,
  required List<WorkflowState> targets,
}) {
  return showGlassModal<String>(
    context,
    width: 520,
    builder: (modalContext) => _StateMigrationDialog(
      stateName: stateName,
      issueCount: issueCount,
      targets: targets,
    ),
  );
}

class _StateMigrationDialog extends StatefulWidget {
  const _StateMigrationDialog({
    required this.stateName,
    required this.issueCount,
    required this.targets,
  });

  final String stateName;
  final int issueCount;
  final List<WorkflowState> targets;

  @override
  State<_StateMigrationDialog> createState() => _StateMigrationDialogState();
}

class _StateMigrationDialogState extends State<_StateMigrationDialog> {
  String? _targetId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.arrowRightLeft,
          title: context.t('projectSettings.migrateTitle'),
          subtitle: context.t(
            'projectSettings.migrateSubtitle',
            variables: {'count': '${widget.issueCount}'},
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t(
                    'projectSettings.migrateBody',
                    variables: {'name': widget.stateName},
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 14),
                FieldLabel(text: context.t('projectSettings.migrateTarget')),
                for (final s in widget.targets)
                  _TargetRow(
                    state: s,
                    selected: _targetId == s.id,
                    onTap: () => setState(() => _targetId = s.id),
                  ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.info, size: 14, color: AppColors.inkFaint),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        context.t('projectSettings.migrateManualHint'),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('projectSettings.migrateConfirm'),
          confirmIcon: LucideIcons.trash2,
          onConfirm: _targetId == null
              ? null
              : () => Navigator.of(context).pop(_targetId),
        ),
      ],
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.state,
    required this.selected,
    required this.onTap,
  });

  final WorkflowState state;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppColors.accentSoft
            : AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: selected ? AppColors.accentLine : AppColors.hairline,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: hueColor(state.hue),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    state.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? LucideIcons.circleCheckBig
                      : LucideIcons.circle,
                  size: 18,
                  color: selected ? AppColors.accentStrong : AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
