import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/team_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/hive_widgets.dart' show hiveEase;
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;
import 'team_widgets.dart';

/// Picks one team out of [teams], with a search above the list.
///
/// A popover on a wide window, a sheet on a phone, like the person picker. The
/// list is built lazily, so an organization with hundreds of teams opens it as
/// fast as one with three.
Future<Team?> showTeamPicker(
  BuildContext context, {
  required List<Team> teams,
  required String titleKey,
  Rect? anchorRect,
}) {
  Widget panel(bool sheet) =>
      _TeamPickerPanel(teams: teams, titleKey: sheet ? titleKey : null);
  if (anchorRect != null &&
      MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
    return showGlassAnchoredPopover<Team>(
      context,
      anchorRect: anchorRect,
      width: 340,
      minHeight: 200,
      maxHeight: 420,
      builder: (_) => panel(false),
    );
  }
  return showGlassBottomSheet<Team>(
    context,
    builder: (_) => AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: hiveEase,
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: panel(true),
      ),
    ),
  );
}

class _TeamPickerPanel extends StatefulWidget {
  const _TeamPickerPanel({required this.teams, this.titleKey});

  final List<Team> teams;

  /// Shown above the search in the sheet; the popover hangs off its field.
  final String? titleKey;

  @override
  State<_TeamPickerPanel> createState() => _TeamPickerPanelState();
}

class _TeamPickerPanelState extends State<_TeamPickerPanel> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Team> get _shown {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.teams;
    return [
      for (final team in widget.teams)
        if (team.name.toLowerCase().contains(query) ||
            team.key.toLowerCase().contains(query))
          team,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.titleKey != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Text(
              context.t(widget.titleKey!),
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontWeight: FontWeight.w700,
                fontSize: AppType.body,
                color: AppColors.ink,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Semantics(
            label: context.t('teams.searchHint'),
            textField: true,
            child: TextField(
              controller: _search,
              autofocus: widget.titleKey == null,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: AppType.label),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(LucideIcons.search, size: 16),
                hintText: context.t('teams.searchHint'),
              ),
            ),
          ),
        ),
        Flexible(
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  child: Text(
                    context.t('common.empty'),
                    style: TextStyle(
                      fontSize: AppType.label,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final team = shown[index];
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(team),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            TeamGlyph(team: team, size: 26, radius: 8),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                team.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppType.label,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
