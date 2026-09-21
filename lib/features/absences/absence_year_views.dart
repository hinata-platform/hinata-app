import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/absence_report_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/soft_card.dart';
import 'absence_labels.dart';

/// The turn of the leave year as widgets that draw what they are given
/// (HIN-119): the person's card that says what lapses when, the notices they
/// received, and the keeper's cards for the yearly run, the people nobody told
/// and the proposals after a long illness.

/// "Your vacation lapses on 31 March 2027: 3 days." The person sees the same
/// deadline the notice named, and how much is still there.
class AbsenceExpiryCard extends StatelessWidget {
  const AbsenceExpiryCard({
    super.key,
    required this.typeName,
    required this.milliDays,
    required this.on,
  });

  final String typeName;
  final int milliDays;
  final DateTime on;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.accent : AppColors.accentText;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(LucideIcons.hourglass, size: 18, color: ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(
                      'absence.expiry.title',
                      variables: {
                        'type': typeName,
                        'date': dayMonthLabel(context, on),
                      },
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.t(
                      'absence.expiry.body',
                      variables: {'days': daysLabel(context, milliDays)},
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final Map<String, DateFormat> _sentFormats = {};

String _sentLabel(BuildContext context, DateTime at) {
  final tag = Localizations.localeOf(context).toLanguageTag();
  return _sentFormats
      .putIfAbsent(tag, () => DateFormat.yMMMd(tag).add_Hm())
      .format(at);
}

/// One notice the person received: when, about which type and year, how much,
/// and the deadline it named.
class AbsenceNoticeTile extends StatelessWidget {
  const AbsenceNoticeTile({
    super.key,
    required this.notice,
    required this.typeName,
  });

  final AbsenceNotice notice;
  final String typeName;

  @override
  Widget build(BuildContext context) {
    final sent = notice.sentAt;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.mailCheck, size: 16, color: AppColors.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(
                      'absence.notices.line',
                      variables: {
                        'type': typeName,
                        'year': '${notice.year}',
                        'days': daysLabel(context, notice.remainingMilliDays),
                      },
                    ),
                    style: TextStyle(fontSize: 13.5, color: AppColors.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (sent != null) _sentLabel(context, sent),
                      if (notice.expiresOn != null)
                        context.t(
                          'absence.notices.until',
                          variables: {
                            'date': dayMonthLabel(context, notice.expiresOn!),
                          },
                        ),
                      context.t('absence.notices.kind.${notice.kind}'),
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the yearly run did on its last night, as four counts and a sentence.
class AbsenceYearRunCard extends StatelessWidget {
  const AbsenceYearRunCard({super.key, required this.run});

  final AbsenceYearRun run;

  @override
  Widget build(BuildContext context) {
    final day = run.day;
    Widget count(String key, int value, Color rail) => MergeSemantics(
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: rail,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.t(key),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$value',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                run.failed
                    ? LucideIcons.triangleAlert
                    : LucideIcons.calendarClock,
                size: 18,
                color: run.failed ? AppColors.dangerInk : AppColors.inkSoft,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  day == null
                      ? context.t('absence.yearRun.never')
                      : context.t(
                          run.failed
                              ? 'absence.yearRun.lastFailed'
                              : 'absence.yearRun.last',
                          variables: {'date': dayMonthLabel(context, day)},
                        ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.t('absence.yearRun.explain'),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.inkSoft,
            ),
          ),
          if (day != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                count('absence.yearRun.carried', run.carried, AppColors.stTodo),
                count(
                  'absence.yearRun.expired',
                  run.expired,
                  AppColors.brandInk,
                ),
                count('absence.yearRun.held', run.held, AppColors.accent),
                count('absence.yearRun.accrued', run.accrued, AppColors.stDone),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Somebody nobody told yet: whose days, how many, by when, and the button that
/// sends the notice now.
class AbsenceMissingRow extends StatelessWidget {
  const AbsenceMissingRow({
    super.key,
    required this.missing,
    required this.typeName,
    required this.onSend,
    this.sending = false,
  });

  final AbsenceMissingNotice missing;
  final String typeName;
  final VoidCallback? onSend;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final deadline = missing.deadline;
    final chipInk = missing.overdue ? AppColors.dangerInk : AppColors.inkSoft;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    missing.name ?? '—',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.t(
                      'absence.yearRun.missingLine',
                      variables: {
                        'type': typeName,
                        'year': '${missing.year}',
                        'days': daysLabel(context, missing.milliDays),
                      },
                    ),
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                  if (deadline != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          missing.overdue
                              ? LucideIcons.circleAlert
                              : LucideIcons.hourglass,
                          size: 13,
                          color: chipInk,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            context.t(
                              missing.overdue
                                  ? 'absence.yearRun.overdue'
                                  : 'absence.yearRun.dueBy',
                              variables: {
                                'date': dayMonthLabel(context, deadline),
                              },
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: chipInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: sending ? null : onSend,
            icon: const Icon(LucideIcons.send, size: 16),
            label: Text(context.t('absence.yearRun.sendNow')),
          ),
        ],
      ),
    );
  }
}

/// A proposed lapse after a long illness, with the two decisions a keeper has.
class AbsenceProposalRow extends StatelessWidget {
  const AbsenceProposalRow({
    super.key,
    required this.proposal,
    required this.typeName,
    required this.onConfirm,
    required this.onDismiss,
  });

  final AbsenceProposal proposal;
  final String typeName;

  /// Open the decision with its reason; null while one is being saved.
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final from = proposal.windowFrom;
    final to = proposal.windowTo;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    proposal.name ?? '—',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.t(
                      'absence.yearRun.proposalLine',
                      variables: {
                        'type': typeName,
                        'year': '${proposal.year}',
                        'days': daysLabel(context, proposal.milliDays),
                      },
                    ),
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                  if (from != null && to != null && proposal.sickDays != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        context.t(
                          'absence.yearRun.proposalSick',
                          variables: {
                            'count': '${proposal.sickDays}',
                            'span': spanLabel(context, from, to),
                          },
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onDismiss,
                child: Text(context.t('absence.yearRun.dismiss')),
              ),
              FilledButton.tonalIcon(
                onPressed: onConfirm,
                icon: const Icon(LucideIcons.gavel, size: 16),
                label: Text(context.t('absence.yearRun.confirm')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
