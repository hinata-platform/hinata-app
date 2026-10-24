import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/auth_bloc.dart';
import '../../../core/docs/docs_links.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../issues/attachments/attachment_kind.dart' show kindFromName;
import '../../issues/attachments/attachment_viewer.dart';
import '../../people/person_profile_screen.dart' show personLocation;
import '../../sprint/modals/glass_modal.dart';
import '../decision/decision_dialog.dart';
import '../report/report_reasons.dart' show reportCategoryTitle;
import '../widgets/case_look.dart';
import 'case_content.dart';
import 'case_detail_cubit.dart';
import 'case_dialogs.dart';
import 'case_sections.dart';

/// One case on the moderation page (HIN-174); dumb, it renders
/// [CaseDetailCubit] and hands every step to it.
class CaseDetailView extends StatelessWidget {
  const CaseDetailView({super.key, this.padding = EdgeInsets.zero});

  /// Around the scrolling content: the page's padding on a phone, the
  /// panel's on a wide window.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<CaseDetailCubit, CaseDetailState>(
        listenWhen: (previous, current) =>
            current.notice != null || current.errorKey != null,
        listener: (context, state) {
          final notice = state.notice;
          final error = state.errorKey;
          if (notice != null) {
            showGlassToast(
              context,
              context.t(notice.key),
              kind: notice.moved ? GlassToastKind.info : GlassToastKind.success,
            );
          } else if (error != null) {
            showGlassToast(
              context,
              context.t(error),
              kind: GlassToastKind.error,
            );
          }
        },
        builder: (context, state) {
          final detail = state.detail;
          return switch (state.load) {
            CaseLoad.loading when detail == null => const Center(
              child: HiveLoader(),
            ),
            CaseLoad.gone => HiveEmptyState(
              title: context.t('moderation.case.goneTitle'),
              message: context.t('moderation.case.goneMessage'),
            ),
            CaseLoad.failure when detail == null => HiveEmptyState(
              title: context.t('moderation.case.failedTitle'),
              message: context.t('moderation.queue.failedMessage'),
              action: OutlinedButton(
                onPressed: () =>
                    unawaited(context.read<CaseDetailCubit>().load()),
                child: Text(context.t('common.retry')),
              ),
            ),
            _ when detail == null => const SizedBox.shrink(),
            _ => _CaseBody(detail: detail, state: state, padding: padding),
          };
        },
      );
}

class _CaseBody extends StatelessWidget {
  const _CaseBody({
    required this.detail,
    required this.state,
    required this.padding,
  });

  final CaseDetail detail;
  final CaseDetailState state;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final me = context.select<AuthBloc, String?>((bloc) => bloc.state.user?.id);
    final cubit = context.read<CaseDetailCubit>();
    final summary = detail.summary;
    final evidence = detail.evidence;
    final decision = detail.decision;
    final appeal = detail.appeal;
    final names = state.names;
    return ListView(
      padding: padding,
      children: [
        _Head(detail: detail, names: names),
        const SizedBox(height: 16),
        if (summary.state == CaseState.pendingConfirmation)
          _PendingConfirmation(detail: detail, me: me),
        if (detail.evidenceWithheld)
          _Withheld(detail: detail, me: me, busy: state.busy)
        else if (evidence != null) ...[
          CaseSectionLabel(
            context.t('moderation.case.reported'),
            trailing: context.t('moderation.case.asReported'),
          ),
          ReportedContent(
            content: evidence,
            names: names,
            files: evidence.media.isEmpty
                ? null
                : CaseFiles(
                    media: evidence.media,
                    childSafety: summary.childSafety,
                    onOpen: (index) => unawaited(_openFile(context, index)),
                    onProcedure: () =>
                        unawaited(openDocs(context, DocsPage.moderation)),
                  ),
          ),
          const SizedBox(height: 6),
          _SinceReport(detail: detail),
        ] else if (!summary.state.undecided)
          CaseInfoLine(
            icon: LucideIcons.fileX,
            text: context.t('moderation.case.noCopyKept'),
          ),
        if (detail.removalIncomplete)
          CaseInfoLine(
            icon: LucideIcons.hourglass,
            text: context.t('moderation.case.removalIncomplete'),
          ),
        if (detail.otherUses.isNotEmpty) ...[
          const SizedBox(height: 10),
          OtherUses(
            uses: detail.otherUses,
            onOpen: (use) => _openOtherUse(context, use),
          ),
        ],
        if (decision != null) ...[
          const SizedBox(height: 14),
          DecisionSummary(decision: decision, kind: summary.kind, names: names),
        ],
        if (detail.restoration case final restoration?)
          CaseInfoLine(
            icon: LucideIcons.undo2,
            text: context.t(
              'moderation.case.restoredBy.${(restoration.outcome ?? RestoreOutcome.restored).name}',
              variables: {
                'name':
                    names[restoration.by] ??
                    context.t('moderation.case.someoneModerating'),
              },
            ),
          ),
        if (appeal != null) ...[
          const SizedBox(height: 14),
          AppealPanel(
            appeal: appeal,
            names: names,
            decidedByReader: me != null && decision?.decidedBy == me,
            onUphold: state.busy
                ? null
                : () => unawaited(_decideAppeal(context, AppealResult.uphold)),
            onReverse: state.busy
                ? null
                : () => unawaited(_decideAppeal(context, AppealResult.reverse)),
          ),
        ],
        const SizedBox(height: 14),
        CaseReports(
          detail: detail,
          loadingMore: state.loadingReports,
          onReveal: summary.state.undecided && !state.busy
              ? (report) => unawaited(_revealReporter(context, report))
              : null,
          onMore: () => unawaited(cubit.moreReports()),
        ),
        const SizedBox(height: 10),
        CaseHistory(events: detail.history, names: names),
        const SizedBox(height: 16),
        _Actions(detail: detail, me: me, busy: state.busy),
      ],
    );
  }

  Future<void> _openFile(BuildContext context, int index) async {
    final summary = detail.summary;
    if (summary.categories.contains(ReportCategory.sexual)) {
      final go = await showGlassConfirm(
        context,
        icon: LucideIcons.eyeOff,
        title: context.t('moderation.case.disturbingTitle'),
        message: context.t('moderation.case.disturbingMessage'),
        confirmLabel: context.t('moderation.case.viewFile'),
        confirmIcon: LucideIcons.eye,
      );
      if (go != true || !context.mounted) return;
    }
    final media = detail.evidence!.media;
    final cubit = context.read<CaseDetailCubit>();
    String nameOf(int i) =>
        media[i].fileName ??
        context.t('moderation.case.fileNumber', variables: {'n': '${i + 1}'});
    await showAttachmentViewer(
      context,
      items: [
        for (var i = 0; i < media.length; i++)
          ViewerItem(
            id: '${detail.id}-$i',
            name: nameOf(i),
            kind: kindFromName(nameOf(i), media[i].contentType),
            mime: media[i].contentType,
            size: media[i].size,
            // Through the server on every look, which its audit log records,
            // never by a link that could be passed on; held in memory only,
            // and not past the viewer.
            load: () => cubit.file(i),
          ),
      ],
      initialIndex: index,
      // Looked at, never saved.
      onDownload: null,
    );
  }

  void _openOtherUse(BuildContext context, OtherUse use) {
    final location = use.location;
    if (use.kind == ContentKind.article && use.id != null) {
      context.go('/knowledge/${Uri.encodeComponent(use.id!)}');
    } else if (location != null) {
      context.go('/issues/${Uri.encodeComponent(location)}');
    }
  }

  Future<void> _revealReporter(BuildContext context, CaseReport report) async {
    final reason = await askRevealReason(
      context,
      title: context.t('moderation.case.revealReporterTitle'),
      subtitle: context.t('moderation.case.revealReporterSubtitle'),
      confirmLabel: context.t('moderation.case.reveal'),
    );
    if (reason == null || !context.mounted) return;
    await context.read<CaseDetailCubit>().revealReporter(report.id, reason);
  }

  Future<void> _decideAppeal(BuildContext context, AppealResult result) async {
    final uphold = result == AppealResult.uphold;
    final note = await askCaseNote(
      context,
      icon: uphold ? LucideIcons.check : LucideIcons.rotateCcw,
      title: context.t(
        uphold
            ? 'moderation.appealReview.upholdTitle'
            : 'moderation.appealReview.reverseTitle',
      ),
      subtitle: context.t(
        uphold
            ? 'moderation.appealReview.upholdSubtitle'
            : 'moderation.appealReview.reverseSubtitle',
      ),
      label: context.t('moderation.appealReview.note'),
      confirmLabel: context.t(
        uphold
            ? 'moderation.appealReview.uphold'
            : 'moderation.appealReview.reverse',
      ),
    );
    if (note == null || !context.mounted) return;
    await context.read<CaseDetailCubit>().decideAppeal(result, note);
  }
}

/// The cell, the category, what it is and where, and how long it waited.
class _Head extends StatelessWidget {
  const _Head({required this.detail, required this.names});

  final CaseDetail detail;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final responsible = detail.evidence?.suggestedResponsible;
    final author = responsible == null ? null : names[responsible];
    final kind = contentKindWord(context, summary.kind);
    final subtitle = [
      if (author != null)
        context.t(
          'moderation.case.kindBy',
          variables: {'kind': kind, 'name': author},
        )
      else
        kind,
      ?summary.location,
      if (summary.assignee != null && summary.state == CaseState.inReview)
        context.t(
          'moderation.case.withPerson',
          variables: {'name': summary.assignee!.displayName},
        ),
    ].join(' · ');
    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            reportCategoryTitle(context, summary.category),
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: AppType.heading,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
        ),
      ],
    );
    final age = summary.state.undecided
        ? CaseAgeChip(summary: summary, now: DateTime.now())
        : null;
    // Large text in a narrow column: the cell goes above the title, so the
    // title keeps the width and never breaks inside a word.
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 420 &&
            MediaQuery.textScalerOf(context).scale(10) > 15;
        final hex = CaseHex(summary: summary, size: 36, words: false);
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              hex,
              const SizedBox(height: 10),
              titles,
              if (age != null) ...[const SizedBox(height: 8), age],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            hex,
            const SizedBox(width: 12),
            Expanded(child: titles),
            if (age != null) ...[const SizedBox(width: 8), age],
          ],
        );
      },
    );
  }
}

/// Unchanged, changed or deleted since it was reported, and what the
/// moderator sees of it.
class _SinceReport extends StatelessWidget {
  const _SinceReport({required this.detail});

  final CaseDetail detail;

  @override
  Widget build(BuildContext context) {
    final since = detail.sinceReport;
    final scope = context.t(
      'moderation.case.scope.${detail.summary.kind.name}',
    );
    if (since == null) {
      return CaseInfoLine(icon: LucideIcons.scanEye, text: scope);
    }
    final (icon, key) = switch (since) {
      SinceReport.unchanged => (LucideIcons.fileCheck, 'unchanged'),
      SinceReport.changed => (LucideIcons.filePen, 'changed'),
      SinceReport.deleted => (LucideIcons.fileX, 'deleted'),
    };
    return CaseInfoLine(
      icon: icon,
      text: '${context.t('moderation.case.since.$key')} $scope',
    );
  }
}

/// Reported without an account on internal content: closed until a second
/// person opens it, each step with a reason.
class _Withheld extends StatelessWidget {
  const _Withheld({required this.detail, required this.me, required this.busy});

  final CaseDetail detail;
  final String? me;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final asked = detail.evidenceReveal?.requestedBy;
    final askedByMe = asked != null && asked == me;
    final label = asked == null
        ? 'moderation.case.askToOpen'
        : askedByMe
        ? null
        : 'moderation.case.open';
    return CaseInfoLine(
      icon: LucideIcons.fileLock,
      text: context.t(
        askedByMe ? 'moderation.case.askedToOpen' : 'moderation.case.withheld',
      ),
      action: label == null
          ? null
          : OutlinedButton.icon(
              onPressed: busy ? null : () => unawaited(_reveal(context, label)),
              icon: const Icon(LucideIcons.lockOpen, size: 16),
              label: Text(context.t(label)),
            ),
    );
  }

  Future<void> _reveal(BuildContext context, String label) async {
    final reason = await askRevealReason(
      context,
      title: context.t('${label}Title'),
      subtitle: context.t('${label}Subtitle'),
      confirmLabel: context.t(label),
    );
    if (reason == null || !context.mounted) return;
    await context.read<CaseDetailCubit>().revealEvidence(reason);
  }
}

/// A suspension of somebody with a role, waiting for a second person.
class _PendingConfirmation extends StatelessWidget {
  const _PendingConfirmation({required this.detail, required this.me});

  final CaseDetail detail;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final requestedBy = detail.confirmationRequestedBy;
    final mine = requestedBy != null && requestedBy == me;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CaseInfoLine(
        icon: LucideIcons.usersRound,
        text: context.t(
          mine
              ? 'moderation.case.pendingMine'
              : 'moderation.case.pendingOthers',
        ),
      ),
    );
  }
}

/// The one main step, beside it taking or giving back, and the rest in ⋯.
class _Actions extends StatelessWidget {
  const _Actions({required this.detail, required this.me, required this.busy});

  final CaseDetail detail;
  final String? me;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final cubit = context.read<CaseDetailCubit>();
    final assignee = summary.assignee?.id;
    final mine = assignee != null && assignee == me;
    final open =
        summary.state == CaseState.open ||
        summary.state == CaseState.urgent ||
        summary.state == CaseState.inReview;
    final free = assignee == null || mine;
    final requestedBy = detail.confirmationRequestedBy;
    final secondPerson = requestedBy != null && requestedBy != me;
    final menu = _menuItems(context);
    final buttons = <Widget>[
      if (menu.isNotEmpty)
        GlassPopupMenu<String>(
          value: '',
          width: 260,
          items: menu,
          onSelected: (key) => unawaited(_onMenu(context, key)),
          child: const _MoreButton(),
        ),
      if (open && mine)
        OutlinedButton(
          onPressed: busy ? null : () => unawaited(cubit.release()),
          child: Text(context.t('moderation.case.release')),
        )
      else if (open && (assignee == null || detail.takeOverAllowed))
        OutlinedButton(
          onPressed: busy
              ? null
              : () => unawaited(cubit.claim(takeOver: assignee != null)),
          child: Text(
            context.t(
              assignee == null
                  ? 'moderation.case.claim'
                  : 'moderation.case.takeOver',
            ),
          ),
        ),
      if (secondPerson) ...[
        OutlinedButton(
          onPressed: busy ? null : () => unawaited(_reject(context)),
          child: Text(context.t('moderation.case.reject')),
        ),
        FilledButton.icon(
          onPressed: busy ? null : () => unawaited(cubit.confirm()),
          icon: const Icon(LucideIcons.check, size: 16),
          label: Text(context.t('moderation.case.confirm')),
        ),
      ],
      if (open && free)
        FilledButton.icon(
          onPressed: busy ? null : () => unawaited(_decide(context)),
          icon: const Icon(LucideIcons.gavel, size: 16),
          label: Text(context.t('moderation.case.decide')),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return OverflowBar(
      alignment: MainAxisAlignment.end,
      spacing: 10,
      overflowSpacing: 8,
      overflowAlignment: OverflowBarAlignment.end,
      children: buttons,
    );
  }

  List<GlassMenuEntry<String>> _menuItems(BuildContext context) {
    final summary = detail.summary;
    final decision = detail.decision;
    final acted =
        summary.state == CaseState.acted &&
        decision?.outcome == CaseOutcome.action;
    final appealPending = detail.appeal?.pending ?? false;
    return [
      if (detail.personConcerned != null)
        GlassMenuItem(
          value: 'profile',
          leading: const Icon(LucideIcons.userRound, size: 16),
          label: context.t('moderation.case.viewProfile'),
        ),
      if (acted && summary.removed && !appealPending)
        GlassMenuItem(
          value: 'restore',
          leading: const Icon(LucideIcons.undo2, size: 16),
          label: context.t('moderation.case.restore'),
        ),
      if (summary.suspended)
        GlassMenuItem(
          value: 'lift',
          leading: const Icon(LucideIcons.userCheck, size: 16),
          label: context.t('moderation.suspension.lift'),
        ),
      if (acted && detail.appeal == null && detail.restoration == null)
        GlassMenuItem(
          value: 'appeal',
          leading: const Icon(LucideIcons.mailOpen, size: 16),
          label: context.t('moderation.appealReview.recordAction'),
        ),
      if (!summary.state.undecided)
        GlassMenuItem(
          value: 'hold',
          leading: const Icon(LucideIcons.archive, size: 16),
          label: context.t('moderation.case.holdAction'),
        ),
    ];
  }

  Future<void> _onMenu(BuildContext context, String key) async {
    final cubit = context.read<CaseDetailCubit>();
    switch (key) {
      case 'profile':
        final person = detail.personConcerned;
        if (person != null) context.go(personLocation(person));
      case 'restore':
        final note = await askCaseNote(
          context,
          icon: LucideIcons.undo2,
          title: context.t('moderation.case.restoreTitle'),
          subtitle: context.t('moderation.case.restoreSubtitle'),
          label: context.t('moderation.case.why'),
          confirmLabel: context.t('moderation.case.restoreConfirm'),
        );
        if (note != null) await cubit.restore(note);
      case 'lift':
        final note = await askCaseNote(
          context,
          icon: LucideIcons.userCheck,
          title: context.t('moderation.suspension.liftTitle'),
          subtitle: context.t('moderation.suspension.liftSubtitle'),
          label: context.t('moderation.case.why'),
          confirmLabel: context.t('moderation.suspension.liftConfirm'),
        );
        if (note != null) await cubit.liftSuspension(note);
      case 'appeal':
        final appeal = await askRecordedAppeal(context);
        if (appeal != null) {
          await cubit.recordAppeal(appeal.text, appeal.receivedAt);
        }
      case 'hold':
        final hold = await askLegalHold(context);
        if (hold != null) {
          await cubit.legalHold(
            until: hold.until,
            indefinite: hold.indefinite,
            reason: hold.reason,
          );
        }
    }
  }

  Future<void> _reject(BuildContext context) async {
    final note = await askCaseNote(
      context,
      icon: LucideIcons.x,
      title: context.t('moderation.case.rejectTitle'),
      subtitle: context.t('moderation.case.rejectSubtitle'),
      label: context.t('moderation.case.why'),
      confirmLabel: context.t('moderation.case.reject'),
      destructive: true,
    );
    if (note == null || !context.mounted) return;
    await context.read<CaseDetailCubit>().reject(note);
  }

  Future<void> _decide(BuildContext context) async {
    final cubit = context.read<CaseDetailCubit>();
    final notice = await showDecisionDialog(context, detail);
    if (notice != null) await cubit.afterDecision(notice);
  }
}

/// The ⋯ beside the case's buttons, as large as they are.
class _MoreButton extends StatelessWidget {
  const _MoreButton();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: context.t('moderation.case.more'),
    child: Semantics(
      button: true,
      label: context.t('moderation.case.more'),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Icon(LucideIcons.ellipsis, size: 18, color: AppColors.ink),
      ),
    ),
  );
}
