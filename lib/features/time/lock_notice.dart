import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_approval_models.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassModalHeader, GlassToastKind, showGlassModal, showGlassToast;

/// Why an entry is frozen, who can lift it, and what to do about it — one
/// component for every reason there is.
///
/// After HIN-88 an entry can be immutable for two reasons, and HIN-96 adds a
/// third (an issued invoice). The component exists because the alternative is
/// what it was written to prevent: three mechanisms each inventing their own
/// sentence, so the person on the other end gets three ways of being told "no",
/// three vocabularies and three places to look for the way out. Here there is one
/// shape — reason, who, and the way back — and the reason only picks which
/// sentences fill it.
///
/// Three sentences rather than one, and none of them is decoration. "Why" without
/// "who" leaves somebody guessing which colleague to ask, and both without a
/// remedy is a dead end — which for working time is not merely unhelpful: Art. 16
/// DSGVO gives a right to have inaccurate personal data corrected without undue
/// delay, so every freeze has to name an act somebody can actually perform.
class LockNotice extends StatelessWidget {
  const LockNotice({
    super.key,
    required this.lock,
    this.compact = false,
    this.onRequested,
  });

  final TimeLockInfo lock;

  /// Drops the "who" line. For a bottom sheet where vertical space is the
  /// scarcest thing on screen and the remedy already names the person.
  final bool compact;

  /// Called after a correction request has been accepted, so the caller can
  /// close or refresh. Absent when there is no entry to ask about.
  final VoidCallback? onRequested;

  @override
  Widget build(BuildContext context) {
    final action = lock.entryId == null
        ? null
        : GhostButton(
            icon: LucideIcons.messageSquareWarning,
            label: context.t('time.lock.request'),
            onPressed: () => _ask(context),
          );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.lock, size: 17, color: AppColors.inkSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reasonOf(context, lock),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.t(lock.holderKey),
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      context.t(lock.remedyKey),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 10),
            Align(alignment: AlignmentDirectional.centerStart, child: action),
          ],
        ],
      ),
    );
  }

  /// The "why" line, with the dates the reason happens to carry filled in.
  ///
  /// A function rather than a getter on the model: formatting a date needs the
  /// reader's locale, and a model that reached for a `BuildContext` would be a
  /// model that cannot be unit-tested.
  static String reasonOf(BuildContext context, TimeLockInfo lock) {
    final localizations = MaterialLocalizations.of(context);
    if (lock.isLockDate && lock.lockDate != null) {
      return context.t(
        lock.reasonKey,
        variables: {'date': localizations.formatMediumDate(lock.lockDate!)},
      );
    }
    if (lock.isApproval && lock.periodStart != null && lock.periodEnd != null) {
      return context.t(
        lock.reasonKey,
        variables: {
          'from': localizations.formatMediumDate(lock.periodStart!),
          'to': localizations.formatMediumDate(lock.periodEnd!),
        },
      );
    }
    // A reason with no dates to fill in, or one this build has never heard of —
    // a server newer than the app. The honest answer is still "frozen", not
    // "fine", and never a raw key.
    return context.t(lock.reasonKey);
  }

  Future<void> _ask(BuildContext context) async {
    // Read before the await: the repository comes from the tree, the way every
    // other caller in the module gets it. It used to be built from
    // `ApiClient.instance`, which made this widget depend on a global the app
    // happens to set in `main` — untestable, and wrong the moment somebody
    // renders it under a second server.
    final repository = context.read<TimeRepository>();
    final note = await showGlassNoteDialog(
      context,
      titleKey: 'time.lock.requestTitle',
      hintKey: 'time.lock.requestHint',
      confirmKey: 'time.lock.requestSend',
      required: true,
    );
    if (note == null || !context.mounted) return;
    try {
      await repository.requestCorrection(lock.entryId!, note);
      if (!context.mounted) return;
      showGlassToast(
        context,
        context.t('time.lock.requestSent'),
        kind: GlassToastKind.success,
      );
      onRequested?.call();
    } on ApiFailure catch (failure) {
      if (!context.mounted) return;
      // Through context.t, because an ApiFailure carries the server's i18n
      // *key* and printing it raw leaks "error.time.entryNotLocked" at somebody.
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
    }
  }
}

/// The lock as one chip, for a row in a list or a cell in a grid.
///
/// The same vocabulary compressed to a glyph and a word, with the whole sentence
/// on the tooltip — a list of forty entries cannot carry three lines each, and
/// "Locked" with no reason was exactly the thing this stage set out to fix.
class LockChip extends StatelessWidget {
  const LockChip({super.key, required this.lock});

  final TimeLockInfo lock;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: LockNotice.reasonOf(context, lock),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 11, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              context.t(lock.chipKey),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a sentence, in the one shape every reason-carrying action uses.
///
/// Four of them need it — rejecting, reopening, adding a lock exception, asking
/// for a correction — and all four are refused by the server without one. A
/// dialog per caller would be four places for the "required" to drift out of step
/// with that.
Future<String?> showGlassNoteDialog(
  BuildContext context, {
  required String titleKey,
  required String hintKey,
  required String confirmKey,
  bool required = true,
  String? initial,
}) => showGlassModal<String>(
  context,
  width: 460,
  builder: (modalContext) => _NoteDialog(
    titleKey: titleKey,
    hintKey: hintKey,
    confirmKey: confirmKey,
    required: required,
    initial: initial,
  ),
);

/// The body of [showGlassNoteDialog].
///
/// A widget of its own rather than a closure over a controller, and the reason is
/// lifecycle: a controller disposed when the modal's *future* completes is still
/// being rebuilt by the route's exit animation — "A TextEditingController was
/// used after being disposed", one frame after the tap. A State disposes its own
/// controller when its element goes, which is the only moment that is safe.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.titleKey,
    required this.hintKey,
    required this.confirmKey,
    required this.required,
    this.initial,
  });

  final String titleKey;
  final String hintKey;
  final String confirmKey;
  final bool required;
  final String? initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _note = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Whether there is something to send.
  ///
  /// The server refuses a blank reason on every one of the four actions that asks
  /// for one, so the button refuses it first: one that answered 400 would teach
  /// people to distrust the button rather than the rule.
  ///
  /// Held as a field rather than derived from the controller, and that is the
  /// whole of the bug this replaced: `onChanged` fires *after* the controller has
  /// the new text, so a getter that read the controller compared the new answer
  /// with itself, found them equal, and never rebuilt — leaving the confirm
  /// greyed out however much was typed.
  late bool _canSend =
      !widget.required || (widget.initial ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassModalHeader(
        icon: LucideIcons.messageSquareWarning,
        title: context.t(widget.titleKey),
        subtitle: context.t(widget.hintKey),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _note,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: TimeLockInfo.noteMaxLength,
              textInputAction: TextInputAction.newline,
              // Only the empty/non-empty flip matters to the button, so the
              // dialog is rebuilt when that changes and not once per keystroke.
              // Only the empty/non-empty flip matters to the button, so the
              // dialog is rebuilt when that changes and not once per keystroke.
              onChanged: widget.required
                  ? (text) {
                      final canSend = text.trim().isNotEmpty;
                      if (canSend != _canSend) {
                        setState(() => _canSend = canSend);
                      }
                    }
                  : null,
              decoration: InputDecoration(
                hintText: context.t(widget.hintKey),
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            // Wrap, not Row: two buttons whose labels come from a bundle can be
            // wider than the dialog in a language nobody tested, and a row that
            // overflows is a yellow-striped band where the confirm used to be.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                GhostButton(
                  label: context.t('common.cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                PrimaryButton(
                  label: context.t(widget.confirmKey),
                  onPressed: _canSend
                      ? () => Navigator.of(context).pop(_note.text.trim())
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

/// "1 Mar – 31 Mar 2026", in the reader's locale.
///
/// The label of a period is the two dates, never a week number and never the word
/// "week": how often timesheets are handed in is the operator's decision, and a
/// label that assumed a rhythm would be wrong on most instances. The type is named
/// separately where there is room for it.
///
/// Two things it deliberately is not. It carries **no weekday**, which
/// `MaterialLocalizations.formatMediumDate` would add: "Tue, 1 Sep – Wed, 30 Sep"
/// answers which day of the week a month happens to begin on, twice, in the one
/// place nobody asked — a period is bounded by dates, and the noise is worst in
/// exactly the narrow switcher where the room is scarcest. And it carries the
/// **year once**, on the end, which the old shape carried not at all: an approval
/// list pages back through years, and "1 Jul – 31 Jul" in a history line is a
/// different month depending on how far down it sits.
String formatPeriod(BuildContext context, DateTime start, DateTime end) {
  final locale = Localizations.localeOf(context).toString();
  final full = DateFormat.yMMMd(locale);
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return full.format(start);
  }
  // Same year: the start drops it, because repeating it reads as two years.
  final from = start.year == end.year ? DateFormat.MMMd(locale) : full;
  return '${from.format(start)} – ${full.format(end)}';
}
