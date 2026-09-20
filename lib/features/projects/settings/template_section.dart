import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_widgets.dart';
import 'settings_common.dart';

/// Templates and the project's event date: the marker that decides where the
/// project is listed, the date its relative deadlines hang off, and the way to
/// copy the whole thing.
///
/// A card of its own rather than three more rows under General. General is what
/// the project *is* — its name, its key, its colour — and these three are what
/// it is *for*: a plan somebody reuses, a date that plan is built around, and
/// the copy that turns one into the other.
///
/// Only rendered while `project_templates` is on; without it none of this
/// exists.
class TemplateSection extends StatelessWidget {
  const TemplateSection({
    super.key,
    required this.isTemplate,
    required this.onTemplateChanged,
    required this.eventDate,
    required this.onPickEventDate,
    required this.onClearEventDate,
    required this.onCopy,
    this.busy = false,
  });

  /// Whether the project is offered as a template. Part of the settings draft,
  /// so it is saved with everything else on the page.
  final bool isTemplate;
  final ValueChanged<bool> onTemplateChanged;

  /// The date the project's relative deadlines are counted from.
  ///
  /// Not part of the draft: moving it moves deadlines, so it is written through
  /// its own confirmed step rather than with the rest of the form.
  final DateTime? eventDate;
  final VoidCallback onPickEventDate;
  final VoidCallback onClearEventDate;

  final VoidCallback onCopy;

  /// True while the event date is being written, so the row cannot be opened
  /// twice over one decision.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('projectSettings.templates.title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(text: context.t('projectSettings.templates.eventDate')),
          _EventDateRow(
            date: eventDate,
            busy: busy,
            onTap: onPickEventDate,
            onClear: onClearEventDate,
          ),
          const SizedBox(height: 6),
          Text(
            context.t('projectSettings.templates.eventDateHint'),
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('projectSettings.templates.markTitle'),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t('projectSettings.templates.markHint'),
                      style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              HiveSwitch(value: isTemplate, onChanged: onTemplateChanged),
            ],
          ),
          const SizedBox(height: 18),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(LucideIcons.copy, size: 15),
              label: Text(context.t('projectSettings.templates.copy')),
            ),
          ),
        ],
      ),
    );
  }
}

/// The event date as a tappable row, with a way to take it away again.
class _EventDateRow extends StatelessWidget {
  const _EventDateRow({
    required this.date,
    required this.busy,
    required this.onTap,
    required this.onClear,
  });

  final DateTime? date;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final label = date == null
        ? context.t('projectSettings.templates.noEventDate')
        : MaterialLocalizations.of(context).formatMediumDate(date!);
    // Named, and a node of its own. An InkWell around an icon and a Text is a
    // button with no name to a screen reader, and the clear × inside it had no
    // name either — so the row reached assistive technology as "button" twice.
    // `container: true` is what makes it a node rather than an annotation the
    // card above merges into itself.
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: busy ? null : onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.calendarDays,
                size: 15,
                color: AppColors.inkSoft,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: date == null ? AppColors.inkFaint : AppColors.ink,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              else if (date != null)
                Semantics(
                  container: true,
                  button: true,
                  label: context.t('common.clear'),
                  onTap: onClear,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: onClear,
                    child: Icon(
                      LucideIcons.x,
                      size: 15,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
