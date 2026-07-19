import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../sprint_format.dart';
import 'glass_modal.dart';

class StartSprintData {
  const StartSprintData({required this.goal, required this.endDate});

  final String? goal;
  final DateTime endDate;
}

/// Liquid-Glass "Start sprint" modal. Locks scope, confirms goal + run dates.
Future<StartSprintData?> showStartSprintDialog(
  BuildContext context, {
  required String sprintName,
  required String? initialGoal,
  required DateTime start,
  required int issueCount,
  required int committedPoints,
  int? capacityPoints,
}) {
  return showGlassModal<StartSprintData>(
    context,
    builder: (_) => _StartSprintBody(
      sprintName: sprintName,
      initialGoal: initialGoal,
      start: start,
      issueCount: issueCount,
      committedPoints: committedPoints,
      capacityPoints: capacityPoints,
    ),
  );
}

class _StartSprintBody extends StatefulWidget {
  const _StartSprintBody({
    required this.sprintName,
    required this.initialGoal,
    required this.start,
    required this.issueCount,
    required this.committedPoints,
    required this.capacityPoints,
  });

  final String sprintName;
  final String? initialGoal;
  final DateTime start;
  final int issueCount;
  final int committedPoints;
  final int? capacityPoints;

  @override
  State<_StartSprintBody> createState() => _StartSprintBodyState();
}

class _StartSprintBodyState extends State<_StartSprintBody> {
  late final TextEditingController _goal = TextEditingController(
    text: widget.initialGoal ?? '',
  );
  int _weeks = 2;

  DateTime get _end => autoEndDate(widget.start, _weeks);

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final over =
        widget.capacityPoints != null &&
        widget.committedPoints > widget.capacityPoints!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.play,
          title: context.t(
            'sprint.start.title',
            variables: {'name': widget.sprintName},
          ),
          subtitle: context.t('sprint.start.sub'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassInfoLine(
                  icon: LucideIcons.layers,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.inkSoft,
                            ),
                            children: [
                              _b('${widget.issueCount}'),
                              TextSpan(
                                text: ' ${context.t('sprint.issuesWord')} · ',
                              ),
                              _b('${widget.committedPoints}'),
                              TextSpan(
                                text: ' ${context.t('sprint.pointsCommitted')}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (over)
                        Text(
                          context.t(
                            'sprint.overCapacity',
                            variables: {'capacity': '${widget.capacityPoints}'},
                          ),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('sprint.goal'),
                  child: TextField(
                    controller: _goal,
                    autofocus: true,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 2,
                    maxLines: 4,
                    decoration: glassInputDecoration(
                      hint: context.t('sprint.goalHint'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('sprint.duration'),
                  child: GlassSegmented(
                    labels: [
                      for (var w = 1; w <= 4; w++)
                        w == 1
                            ? context.t('sprint.week')
                            : context.t(
                                'sprint.weeksN',
                                variables: {'count': '$w'},
                              ),
                    ],
                    selected: _weeks - 1,
                    onChanged: (i) => setState(() => _weeks = i + 1),
                  ),
                ),
                const SizedBox(height: 16),
                GlassInfoLine(
                  icon: LucideIcons.calendarDays,
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkSoft,
                      ),
                      children: [
                        TextSpan(text: '${context.t('sprint.runs')} '),
                        _b(prettyDate(widget.start)),
                        const TextSpan(text: ' → '),
                        _b(prettyDate(_end)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('sprint.start.cta'),
          confirmIcon: LucideIcons.play,
          onConfirm: () => Navigator.of(context).pop(
            StartSprintData(
              goal: _goal.text.trim().isEmpty ? null : _goal.text.trim(),
              endDate: _end,
            ),
          ),
        ),
      ],
    );
  }

  TextSpan _b(String text) => TextSpan(
    text: text,
    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
  );
}
