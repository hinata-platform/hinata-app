import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/project_template_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart' show forwardChevron;
import '../sprint/modals/glass_modal.dart';

/// How many moved deadlines the sheet names before it only counts the rest.
///
/// Enough to recognise the shape of what is about to happen — the first few
/// rows are the ones with the earliest dates — and few enough that the sheet
/// stays a decision rather than a report. The server is asked for exactly this
/// many, so a project with four hundred deadlines costs the same request as one
/// with four.
const int kScheduleMovesShown = 6;

/// Shows what moving the project's date would do, and returns true when
/// somebody went through with it.
///
/// A date field that silently rewrote twelve deadlines would be a page doing
/// something other than what it says, on a screen somebody opened to change a
/// colour. So the writing waits behind a sheet that says which deadlines move,
/// by how much, and how many stay where somebody put them by hand.
Future<bool> showScheduleMoveSheet(
  BuildContext context, {
  required SchedulePreview preview,
  required DateTime? newEventDate,
}) async {
  final confirmed = await showGlassModal<bool>(
    context,
    width: 520,
    builder: (_) =>
        _ScheduleMoveBody(preview: preview, newEventDate: newEventDate),
  );
  return confirmed ?? false;
}

class _ScheduleMoveBody extends StatelessWidget {
  const _ScheduleMoveBody({required this.preview, required this.newEventDate});

  final SchedulePreview preview;
  final DateTime? newEventDate;

  @override
  Widget build(BuildContext context) {
    final formats = MaterialLocalizations.of(context);
    final shift = preview.shiftDays;
    final rest = preview.moved - preview.moves.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.calendarSync,
          title: context.t('projects.schedule.title'),
          subtitle: context.t('projects.schedule.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DateChange(
                  from: preview.eventDate,
                  to: newEventDate,
                  shiftDays: shift,
                ),
                const SizedBox(height: 16),
                Text(
                  context.t(
                    'projects.schedule.moving',
                    variables: {'count': '${preview.moved}'},
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final move in preview.moves)
                  _MoveRow(move: move, formats: formats),
                if (rest > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      context.t(
                        'projects.schedule.andMore',
                        variables: {'count': '$rest'},
                      ),
                      style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                    ),
                  ),
                if (preview.manual > 0) ...[
                  const SizedBox(height: 14),
                  _Note(
                    icon: LucideIcons.pin,
                    // Named rather than left as the difference between two
                    // numbers: a deadline somebody typed is a decision, and the
                    // sheet says out loud that it is not being overruled.
                    text: context.t(
                      'projects.schedule.staying',
                      variables: {'count': '${preview.manual}'},
                    ),
                  ),
                ],
                if (preview.pending > 0) ...[
                  const SizedBox(height: 10),
                  _Note(
                    icon: LucideIcons.calendarOff,
                    text: context.t(
                      'projects.schedule.pending',
                      variables: {'count': '${preview.pending}'},
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('projects.schedule.confirm'),
          confirmIcon: LucideIcons.check,
          onConfirm: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// The date on its way from one day to another, with the distance spelled out.
class _DateChange extends StatelessWidget {
  const _DateChange({
    required this.from,
    required this.to,
    required this.shiftDays,
  });

  final DateTime? from;
  final DateTime? to;
  final int? shiftDays;

  @override
  Widget build(BuildContext context) {
    final formats = MaterialLocalizations.of(context);
    String day(DateTime? date) => date == null
        ? context.t('projects.schedule.noDate')
        : formats.formatMediumDate(date);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline2),
      ),
      // A Wrap, because three dates and a delta do not fit one phone line in
      // every language — and a date that breaks mid-word is worse than one on
      // a second line.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            day(from),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 13,
              color: AppColors.inkSoft,
            ),
          ),
          Icon(forwardChevron(context), size: 14, color: AppColors.inkFaint),
          Text(
            day(to),
            style: const TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (shiftDays != null && shiftDays != 0)
            Text(
              context.t(
                shiftDays! > 0
                    ? 'projects.schedule.later'
                    : 'projects.schedule.earlier',
                variables: {'count': '${shiftDays!.abs()}'},
              ),
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
        ],
      ),
    );
  }
}

/// One deadline on its way from one day to another.
class _MoveRow extends StatelessWidget {
  const _MoveRow({required this.move, required this.formats});

  final ScheduleMove move;
  final MaterialLocalizations formats;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              move.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            move.from == null ? '·' : formats.formatShortDate(move.from!),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 11.5,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(width: 6),
          Icon(forwardChevron(context), size: 12, color: AppColors.inkFaint),
          const SizedBox(width: 6),
          Text(
            move.to == null ? '·' : formats.formatShortDate(move.to!),
            style: const TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A short line about something the move is deliberately not doing.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.inkSoft),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }
}
