import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/util/dates.dart';
import '../report/report_reasons.dart' show reportCategoryTitle;
import '../widgets/case_look.dart';

/// The reports of a case (HIN-174): numbered, by kind of source, the reason
/// in quotes, the reporter covered until somebody uncovers them with a reason
/// (never for the safety of children), further ones a page at a time.
class CaseReports extends StatelessWidget {
  const CaseReports({
    super.key,
    required this.detail,
    required this.loadingMore,
    required this.onReveal,
    required this.onMore,
  });

  final CaseDetail detail;
  final bool loadingMore;

  /// Uncovers report [CaseReport]; null where nobody may.
  final void Function(CaseReport report)? onReveal;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final childSafety = detail.summary.childSafety;
    final covered = detail.reports.any(
      (report) =>
          report.reporter == null && report.source == ReportSource.member,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaseSectionLabel(
          context.t('moderation.case.reports'),
          trailing: '${detail.reportTotal}',
        ),
        for (final report in detail.reports)
          _ReportEntry(
            report: report,
            onReveal:
                onReveal == null ||
                    childSafety ||
                    report.reporter != null ||
                    report.source != ReportSource.member
                ? null
                : () => onReveal!(report),
          ),
        if (detail.reports.length < detail.reportTotal)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: loadingMore ? null : onMore,
              icon: const Icon(LucideIcons.chevronsDown, size: 16),
              label: Text(
                context.t(
                  'moderation.case.moreReports',
                  count: detail.reportTotal - detail.reports.length,
                ),
              ),
            ),
          ),
        if (covered)
          CaseInfoLine(
            icon: LucideIcons.eyeOff,
            text: context.t(
              childSafety
                  ? 'moderation.case.reportersStayCovered'
                  : 'moderation.case.reportersCovered',
            ),
          ),
      ],
    );
  }
}

class _ReportEntry extends StatelessWidget {
  const _ReportEntry({required this.report, this.onReveal});

  final CaseReport report;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final created = report.createdAt;
    final head = [
      context.t(
        'moderation.case.reportNumber',
        variables: {'n': '${report.number}'},
      ),
      context.t('moderation.source.${report.source.name}'),
      if (created != null) recentMoment(context, created),
    ].join(' · ');
    final reporter = report.reporter;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.recess,
              border: Border.all(color: AppColors.hairline),
            ),
            child: Icon(
              LucideIcons.userRound,
              size: 15,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  head,
                  style: TextStyle(
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  reportCategoryTitle(context, report.category),
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: AppColors.inkSoft,
                  ),
                ),
                if (report.explanation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.t(
                        'moderation.case.quoted',
                        variables: {'text': report.explanation!},
                      ),
                      style: TextStyle(
                        fontSize: AppType.label,
                        height: 1.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                if (reporter != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.t(
                        'moderation.case.reportedBy',
                        variables: {'name': reporter.displayName},
                      ),
                      style: TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                if (report.unfoundedChildSafetyBefore > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.t(
                        'moderation.case.unfoundedBefore',
                        count: report.unfoundedChildSafetyBefore,
                      ),
                      style: TextStyle(
                        fontSize: AppType.caption,
                        color: AppColors.warningInk,
                      ),
                    ),
                  ),
                if (onReveal != null)
                  TextButton(
                    onPressed: onReveal,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: Text(context.t('moderation.case.whoReported')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What happened to the case, oldest first, as quiet centred lines.
class CaseHistory extends StatelessWidget {
  const CaseHistory({super.key, required this.events, required this.names});

  final List<CaseEvent> events;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final event in events)
        if (event.kind != null) _HistoryLine(text: _line(context, event)),
    ],
  );

  String _line(BuildContext context, CaseEvent event) {
    final name = event.actorId == null
        ? context.t('moderation.case.someoneModerating')
        : names[event.actorId] ??
              context.t('moderation.case.someoneModerating');
    final detail = event.detail;
    final kind = event.kind!;
    final what = context.t(
      'moderation.history.${kind.name}',
      variables: {
        'name': name,
        'outcome': kind == CaseEventKind.decided
            ? decisionOutcomeWord(context, CaseOutcome.of(detail))
            : '',
        'length': kind == CaseEventKind.suspended
            ? suspensionWord(context, SuspensionLength.of(detail))
            : '',
      },
    );
    final reason =
        detail != null &&
            (kind == CaseEventKind.reporterRevealed ||
                kind == CaseEventKind.evidenceRequested ||
                kind == CaseEventKind.evidenceRevealed ||
                kind == CaseEventKind.confirmationRejected ||
                kind == CaseEventKind.held ||
                kind == CaseEventKind.suspensionLifted)
        ? ' ${context.t('moderation.case.quoted', variables: {'text': detail})}'
        : '';
    final at = event.at;
    return [
      if (at != null) recentMoment(context, at),
      '$what$reason',
    ].join(' · ');
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Divider(color: AppColors.hairline2, height: 1)),
        const SizedBox(width: 10),
        Flexible(
          flex: 6,
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.caption,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: AppColors.hairline2, height: 1)),
      ],
    ),
  );
}

/// How much of a content of [kind] a removal takes, in words: Der ganze
/// Kommentar, Titel und Beschreibung.
String removalScopeWord(
  BuildContext context,
  ContentKind kind,
  RemovalScope scope,
) => context.t('moderation.decision.scope.${kind.name}.${scope.name}');

/// An outcome in a word: Kein Verstoß, Offensichtlich unbegründet, Maßnahme.
String decisionOutcomeWord(BuildContext context, CaseOutcome? outcome) =>
    outcome == null
    ? ''
    : context.t('moderation.decision.outcome.${outcome.name}');

/// A suspension's length in words: 7 Tage, 30 Tage, Unbefristet.
String suspensionWord(BuildContext context, SuspensionLength? length) =>
    length == null
    ? ''
    : context.t('moderation.suspension.length.${length.name}');

/// What was decided, by whom and why: the facts, the rule or law, the message
/// to the person and the moderators' own note.
class DecisionSummary extends StatelessWidget {
  const DecisionSummary({
    super.key,
    required this.decision,
    required this.kind,
    required this.names,
  });

  final CaseDecision decision;

  /// What the case is about, for how much of it a removal took.
  final ContentKind kind;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final d = decision;
    final by = d.decidedBy == null ? null : names[d.decidedBy];
    final head = [
      decisionOutcomeWord(context, d.outcome),
      ?by,
      if (d.decidedAt != null) recentMoment(context, d.decidedAt!),
    ].join(' · ');
    final measures = [
      if (d.removal != null) removalScopeWord(context, kind, d.removal!),
      if (d.suspension != null)
        context.t(
          'moderation.decision.suspendedFor',
          variables: {'length': suspensionWord(context, d.suspension)},
        ),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaseSectionLabel(context.t('moderation.case.decision')),
        Text(
          head,
          style: TextStyle(
            fontSize: AppType.label,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        if (measures.isNotEmpty)
          _Pair(context.t('moderation.case.measure'), measures),
        if (d.facts != null)
          _Pair(context.t('moderation.decision.facts'), d.facts!),
        if (d.reference != null)
          _Pair(
            context.t(
              d.ground == DecisionGround.law
                  ? 'moderation.decision.law'
                  : 'moderation.decision.rule',
            ),
            d.reference!,
          ),
        if (d.messageToAuthor != null)
          _Pair(context.t('moderation.decision.message'), d.messageToAuthor!),
        if (d.internalNote != null)
          _Pair(context.t('moderation.decision.internalNote'), d.internalNote!),
        if (d.lawEnforcementNotified)
          CaseInfoLine(
            icon: LucideIcons.scale,
            text: context.t('moderation.case.lawEnforcementTold'),
          ),
        if (d.confirmedBy != null)
          CaseInfoLine(
            icon: LucideIcons.usersRound,
            text: context.t(
              'moderation.case.confirmedBy',
              variables: {
                'name':
                    names[d.confirmedBy] ??
                    context.t('moderation.case.someoneModerating'),
              },
            ),
          ),
      ],
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: AppType.label,
            height: 1.4,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

/// The appeal against a decision: its words and where they came from, and for
/// anybody but who decided, the two ways to answer it.
class AppealPanel extends StatelessWidget {
  const AppealPanel({
    super.key,
    required this.appeal,
    required this.names,
    required this.decidedByReader,
    required this.onUphold,
    required this.onReverse,
  });

  final CaseAppeal appeal;
  final Map<String, String> names;

  /// The reader decided the case: they read the appeal, somebody else answers.
  final bool decidedByReader;
  final VoidCallback? onUphold;
  final VoidCallback? onReverse;

  @override
  Widget build(BuildContext context) {
    final a = appeal;
    final head = [
      if (a.filedAt != null)
        context.t(
          'moderation.appealReview.filedOn',
          variables: {'date': recentDay(context, a.filedAt!)},
        ),
      context.t('moderation.appealReview.via.${a.via.name}'),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaseSectionLabel(context.t('moderation.appealReview.title')),
        Text(
          head,
          style: TextStyle(fontSize: AppType.caption, color: AppColors.inkSoft),
        ),
        if (a.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          SelectableText(
            context.t('moderation.case.quoted', variables: {'text': a.text}),
            style: TextStyle(
              fontSize: AppType.label,
              height: 1.45,
              color: AppColors.ink,
            ),
          ),
        ],
        if (a.pending && decidedByReader)
          CaseInfoLine(
            icon: LucideIcons.usersRound,
            text: context.t('moderation.appealReview.notYours'),
          )
        else if (a.pending)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 10,
              overflowSpacing: 8,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onReverse,
                  icon: const Icon(LucideIcons.rotateCcw, size: 16),
                  label: Text(context.t('moderation.appealReview.reverse')),
                ),
                FilledButton.icon(
                  onPressed: onUphold,
                  icon: const Icon(LucideIcons.check, size: 16),
                  label: Text(context.t('moderation.appealReview.uphold')),
                ),
              ],
            ),
          )
        else ...[
          CaseInfoLine(
            icon: a.state == AppealState.upheld
                ? LucideIcons.check
                : LucideIcons.rotateCcw,
            text: context.t(
              a.state == AppealState.upheld
                  ? 'moderation.appealReview.wasUpheld'
                  : 'moderation.appealReview.wasReversed',
              variables: {
                'name':
                    names[a.decidedBy] ??
                    context.t('moderation.case.someoneModerating'),
              },
            ),
          ),
          if (a.note != null)
            Text(
              context.t('moderation.case.quoted', variables: {'text': a.note!}),
              style: TextStyle(
                fontSize: AppType.label,
                height: 1.4,
                color: AppColors.ink,
              ),
            ),
        ],
      ],
    );
  }
}

/// Where else a removed image stood: places to look at as well (HIN-169).
class OtherUses extends StatelessWidget {
  const OtherUses({super.key, required this.uses, required this.onOpen});

  final List<OtherUse> uses;
  final void Function(OtherUse use) onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CaseSectionLabel(context.t('moderation.case.otherUses')),
      Text(
        context.t('moderation.case.otherUsesHint'),
        style: TextStyle(fontSize: AppType.caption, color: AppColors.inkSoft),
      ),
      for (final use in uses)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: use.location == null && use.kind != ContentKind.article
                ? null
                : () => onOpen(use),
            icon: const Icon(LucideIcons.arrowUpRight, size: 16),
            label: Text(
              [contentKindWord(context, use.kind), ?use.location].join(' · '),
            ),
          ),
        ),
    ],
  );
}
