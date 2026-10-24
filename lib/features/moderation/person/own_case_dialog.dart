import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/models/moderation_models.dart';
import '../../sprint/modals/glass_modal.dart';
import '../case/case_dialogs.dart' show noteCounter;
import '../report/report_reasons.dart';

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
  void dispose() {
    _facts.dispose();
    super.dispose();
  }

  /// The reasons as a report lists them, beside the field on a wide window,
  /// as a card on a phone: this dialog may be a sheet already.
  Future<void> _pickCategory(Rect? anchor) async {
    final view = View.of(context);
    final wide =
        view.physicalSize.width / view.devicePixelRatio >=
        kGlassPopoverBreakpoint;
    Widget reasons(BuildContext context) => SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: ReportReasons(
        focused: _category,
        onChoose: (category) => Navigator.of(context).pop(category),
      ),
    );
    final picked = wide && anchor != null
        ? await showGlassAnchoredPopover<ReportCategory>(
            context,
            anchorRect: anchor,
            width: 400,
            maxHeight: 560,
            builder: reasons,
          )
        : await showGlassModal<ReportCategory>(
            context,
            width: 460,
            adaptive: false,
            builder: reasons,
          );
    if (picked != null && mounted) setState(() => _category = picked);
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
                child: GlassChoiceField(
                  label: context.t('moderation.suspension.ownCategory'),
                  value: reportCategoryTitle(context, _category),
                  onOpen: (anchor) => unawaited(_pickCategory(anchor)),
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
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _facts,
        builder: (context, value, _) => GlassModalFooter(
          confirmLabel: context.t('moderation.suspension.ownNext'),
          confirmIcon: LucideIcons.arrowRight,
          onConfirm: value.text.trim().length < caseNoteMin
              ? null
              : () => Navigator.of(
                  context,
                ).pop((category: _category, facts: value.text.trim())),
        ),
      ),
    ],
  );
}
