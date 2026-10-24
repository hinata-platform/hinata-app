import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../sprint/modals/glass_modal.dart' show showGlassModal;
import '../shift_texts.dart';

/// What a planner is about to do to an occurrence of a series (HIN-161).
enum SeriesWrite {
  save,
  cancel,
  delete,
  move,
  addShift,
  editShift,
  deleteShift;

  /// The dialog's title.
  String get titleKey => 'shifts.series.ask.$name';

  /// What "Alle künftigen" does, in words, where it differs from a change.
  String get futureHintKey => switch (this) {
    SeriesWrite.cancel => 'shifts.series.scope.futureCancelHint',
    SeriesWrite.delete => 'shifts.series.scope.futureDeleteHint',
    _ => 'shifts.series.scope.futureHint',
  };

  bool get destructive =>
      this == SeriesWrite.cancel ||
      this == SeriesWrite.delete ||
      this == SeriesWrite.deleteShift;
}

/// Asks which occurrences a write to an occurrence on [day] applies to: "Nur
/// dieses" or "Alle künftigen", with Abbrechen. Neither is chosen in advance;
/// the dialog doubles as the confirmation, so a destructive write is asked
/// only once.
///
/// [singleLockedKey] or [futureLockedKey] take one choice away and say why
/// (a new rule always applies from here on; a shift put on several days only
/// ever belongs to this occurrence). Resolves to the scope, or null.
Future<ShiftScope?> askSeriesScope(
  BuildContext context, {
  required SeriesWrite write,
  required DateTime day,
  String? recurrenceLabel,
  String? note,
  String? singleLockedKey,
  String? futureLockedKey,
}) => showGlassModal<ShiftScope>(
  context,
  adaptive: false,
  width: 440,
  builder: (_) => SeriesScopeBody(
    write: write,
    day: day,
    recurrenceLabel: recurrenceLabel,
    note: note,
    singleLockedKey: singleLockedKey,
    futureLockedKey: futureLockedKey,
  ),
);

/// The dialog's content, on its own for tests.
class SeriesScopeBody extends StatelessWidget {
  const SeriesScopeBody({
    super.key,
    required this.write,
    required this.day,
    this.recurrenceLabel,
    this.note,
    this.singleLockedKey,
    this.futureLockedKey,
  });

  final SeriesWrite write;
  final DateTime day;
  final String? recurrenceLabel;

  /// One more sentence under the question, such as who is on the shift.
  final String? note;
  final String? singleLockedKey;
  final String? futureLockedKey;

  @override
  Widget build(BuildContext context) {
    final date = dayLabel(context, day);
    final label = recurrenceLabel;
    // From one and a half times the text size the tile gives its width to
    // the title, which would otherwise break inside its one long word.
    final large = context.largeText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 14, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!large) ...[
                ExcludeSemantics(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      LucideIcons.repeat,
                      size: 20,
                      color: AppColors.accentStrong,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    header: true,
                    child: Text(
                      context.t(write.titleKey),
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: AppType.title,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.t('common.cancel'),
                icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
          child: Text(
            [
              label == null
                  ? context.t('shifts.series.scope.message')
                  : context.t(
                      'shifts.series.scope.messageLabel',
                      variables: {'label': label},
                    ),
              ?note,
            ].join(' '),
            style: TextStyle(
              fontSize: AppType.label,
              height: 1.45,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScopeOption(
                  icon: LucideIcons.calendar,
                  title: context.t('shifts.series.scope.this'),
                  hint: context.t(
                    singleLockedKey ?? 'shifts.series.scope.thisHint',
                    variables: {'date': date},
                  ),
                  destructive: write.destructive,
                  onTap: singleLockedKey != null
                      ? null
                      : () => Navigator.of(context).pop(ShiftScope.single),
                ),
                const SizedBox(height: 10),
                _ScopeOption(
                  icon: LucideIcons.calendarRange,
                  title: context.t('shifts.series.scope.future'),
                  hint: context.t(
                    futureLockedKey ?? write.futureHintKey,
                    variables: {'date': date},
                  ),
                  destructive: write.destructive,
                  onTap: futureLockedKey != null
                      ? null
                      : () => Navigator.of(context).pop(ShiftScope.future),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(22, 10, 14, 14) +
              EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(context.t('common.cancel')),
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the two choices: equal weight, a rim, never filled in advance.
class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final ink = !enabled
        ? AppColors.inkSoft
        : destructive
        ? AppColors.dangerInk
        : AppColors.ink;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppColors.fieldRim),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: ExcludeSemantics(
                    child: Icon(
                      enabled ? icon : LucideIcons.lock,
                      size: 18,
                      color: ink,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: AppType.label,
                          height: 1.4,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
