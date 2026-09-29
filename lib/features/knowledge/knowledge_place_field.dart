import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/project_picker.dart';
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_tree.dart' show KbPlaceGlyph;

/// Where a page should live: a project, a team, or (both null) only its
/// author.
typedef KbPlaceChoice = ({String? projectId, String? teamId});

/// "Visible to" for a knowledge page: one line with the current place, and a
/// glass menu to move a top-level page into a project, one of the person's
/// teams, or back to "only me".
///
/// A subpage lives wherever its parent lives, so with [followsParent] the field
/// is read-only and says so instead of offering a choice the server would turn
/// down.
///
/// Names and teams come from [repo], which loads them once for the whole
/// knowledge base ([KnowledgeRepository.loadPlaces]) instead of each field
/// asking the server about its own page.
class KnowledgePlaceField extends StatefulWidget {
  const KnowledgePlaceField({
    super.key,
    required this.repo,
    required this.projectId,
    required this.teamId,
    required this.onChanged,
    this.followsParent = false,
    this.allowPrivate = true,
    this.canChange,
    this.busy = false,
  });

  /// Where the place names and the person's teams are kept.
  final KnowledgeRepository repo;

  final String? projectId;
  final String? teamId;

  /// Receives the new place. Not called when the same place is picked again.
  final ValueChanged<KbPlaceChoice> onChanged;

  /// A subpage: show "same as the page above" and offer nothing.
  final bool followsParent;

  /// Only the author may make a page private; for anyone else the row is
  /// shown disabled with the reason.
  final bool allowPrivate;

  /// Whether the person may move this page at all. Asked on every build, so
  /// the answer can follow the names and teams as they arrive. Null: always.
  /// Without the right the field shows the place and offers nothing, since
  /// the server would refuse the move.
  final bool Function()? canChange;

  /// A place change is in flight — the field shows it and takes no taps.
  final bool busy;

  @override
  State<KnowledgePlaceField> createState() => _KnowledgePlaceFieldState();
}

class _KnowledgePlaceFieldState extends State<KnowledgePlaceField> {
  static const _private = 'private';
  static const _project = 'project';
  static const _teamPrefix = 'team:';

  bool _opening = false;

  KbPlace get _place => placeOf(widget.projectId, widget.teamId);

  @override
  void initState() {
    super.initState();
    _loadPlaces();
  }

  /// Asks the repository for the names once; every field after the first
  /// shares the same answer.
  Future<void> _loadPlaces() async {
    await widget.repo.loadPlaces();
    if (mounted) setState(() {});
  }

  Future<void> _open(Rect anchor) async {
    if (_opening || widget.busy) return;
    setState(() => _opening = true);
    try {
      await widget.repo.loadPlaces();
      if (!mounted) return;
      final teams = widget.repo.myTeams;
      final current = switch (_place) {
        KbPlace.private => _private,
        KbPlace.team => '$_teamPrefix${widget.teamId}',
        KbPlace.project => _project,
      };
      final picked = await showGlassMenu<String>(
        context: context,
        anchorRect: anchor,
        value: current,
        width: 280,
        items: [
          GlassMenuItem(
            value: _private,
            label: context.t('knowledge.place.private'),
            enabled: widget.allowPrivate,
            disabledReason: widget.allowPrivate
                ? null
                : context.t('knowledge.place.privateAuthorOnly'),
            leading: Icon(LucideIcons.lock, size: 16, color: AppColors.inkSoft),
          ),
          for (final (i, t) in teams.indexed)
            GlassMenuItem(
              value: '$_teamPrefix${t.id}',
              label: t.name,
              dividerAbove: i == 0,
              leading: Icon(
                LucideIcons.users,
                size: 16,
                color: AppColors.inkSoft,
              ),
            ),
          GlassMenuItem(
            value: _project,
            label: widget.projectId == null
                ? context.t('knowledge.place.pickProject')
                : context.t(
                    'knowledge.place.otherProject',
                    variables: {'name': _label(context)},
                  ),
            dividerAbove: true,
            leading: Icon(
              LucideIcons.folder,
              size: 16,
              color: AppColors.inkSoft,
            ),
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 15,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      );
      if (!mounted || picked == null) return;
      if (picked == _private) {
        if (_place != KbPlace.private) {
          widget.onChanged((projectId: null, teamId: null));
        }
      } else if (picked.startsWith(_teamPrefix)) {
        final teamId = picked.substring(_teamPrefix.length);
        if (teamId != widget.teamId) {
          widget.onChanged((projectId: null, teamId: teamId));
        }
      } else if (picked == _project) {
        final projects = await showProjectPicker(
          context,
          anchorRect: anchor,
          selected: {?widget.projectId},
          titleKey: 'knowledge.place.pickProject',
          multi: false,
        );
        final project = projects?.firstOrNull;
        if (!mounted || project == null) return;
        widget.repo.rememberProject(project);
        if (project.id != widget.projectId) {
          widget.onChanged((projectId: project.id, teamId: null));
        }
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  String _label(BuildContext context) => switch (_place) {
    KbPlace.private => context.t('knowledge.place.private'),
    KbPlace.team =>
      widget.repo.placeName(widget.teamId) ?? context.t('knowledge.place.team'),
    KbPlace.project =>
      widget.repo.placeName(widget.projectId) ??
          context.t('knowledge.place.project'),
  };

  @override
  Widget build(BuildContext context) {
    final caption = context.t('knowledge.place.label');
    if (widget.followsParent) {
      return _row(
        caption: caption,
        icon: LucideIcons.cornerLeftUp,
        value: context.t('knowledge.place.followsParent'),
        interactive: false,
      );
    }
    return _row(
      caption: caption,
      icon: KbPlaceGlyph.iconFor(_place),
      value: _label(context),
      interactive: widget.canChange?.call() ?? true,
    );
  }

  Widget _row({
    required String caption,
    required IconData icon,
    required String value,
    required bool interactive,
  }) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: interactive ? AppColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: interactive ? AppColors.hairline : AppColors.hairline2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.inkSoft),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          if (interactive) ...[
            const SizedBox(width: 4),
            if (widget.busy || _opening)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            else
              Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: AppColors.inkFaint,
              ),
          ],
        ],
      ),
    );

    final content = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          caption,
          style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
        ),
        pill,
      ],
    );

    if (!interactive) {
      return Semantics(
        container: true,
        label: '$caption: $value',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: content,
          ),
        ),
      );
    }
    return Builder(
      builder: (anchorContext) => Semantics(
        button: true,
        label: '$caption: $value',
        excludeSemantics: true,
        onTap: () => _open(_rectOf(anchorContext)),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          onTap: widget.busy ? null : () => _open(_rectOf(anchorContext)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 1,
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Rect _rectOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    return (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;
  }
}
