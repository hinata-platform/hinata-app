import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/models/moderation_models.dart';
import '../../sprint/modals/glass_modal.dart';
import '../case/case_dialogs.dart' show noteCounter;
import '../report/report_reasons.dart' show reportCategoryTitle;

/// Why moderation opens a case of its own on a person: the category and what
/// was found, at least twenty characters.
typedef OwnCase = ({ReportCategory category, String facts});

/// Asks for it before a suspension is decided from [name]'s profile.
Future<OwnCase?> askOwnCase(BuildContext context, String name) =>
    showGlassModal<OwnCase>(
      context,
      width: 540,
      adaptive: !insideGlassSheet(context),
      builder: (_) => _OwnCaseDialog(name: name),
    );

class _OwnCaseDialog extends StatefulWidget {
  const _OwnCaseDialog({required this.name});

  final String name;

  @override
  State<_OwnCaseDialog> createState() => _OwnCaseDialogState();
}

class _OwnCaseDialogState extends State<_OwnCaseDialog> {
  final _facts = TextEditingController();
  ReportCategory _category = ReportCategory.harassment;

  @override
  void initState() {
    super.initState();
    _facts.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _facts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlassModalHeader(
        icon: LucideIcons.userX,
        title: context.t(
          'moderation.suspension.ownTitle',
          variables: {'name': widget.name},
        ),
        subtitle: context.t('moderation.suspension.ownSubtitle'),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassField(
                label: context.t('moderation.suspension.ownCategory'),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in ReportCategory.values)
                      ChoiceChip(
                        label: Text(reportCategoryTitle(context, category)),
                        selected: category == _category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              GlassField(
                wrapCaption: true,
                label: context.t(
                  'moderation.case.noteLabel',
                  variables: {
                    'label': context.t('moderation.decision.facts'),
                    'min': '$caseNoteMin',
                  },
                ),
                child: TextField(
                  controller: _facts,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: caseNoteMax,
                  buildCounter: noteCounter,
                  decoration: glassInputDecoration(
                    hint: context.t('moderation.decision.factsHint'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t('moderation.suspension.ownNext'),
        confirmIcon: LucideIcons.arrowRight,
        onConfirm: _facts.text.trim().length < caseNoteMin
            ? null
            : () => Navigator.of(
                context,
              ).pop((category: _category, facts: _facts.text.trim())),
      ),
    ],
  );
}
