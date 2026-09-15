import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/hive_widgets.dart' show forwardArrow;
import '../admin_form_helpers.dart';

/// Admin → Time tracking → Holidays (HIN-91): the way to the holiday calendars.
///
/// A card that leads to a page of its own, because calendars, their feeds and a
/// year of days each do not fit a card in a form that saves as a whole.
class AdminHolidaysCard extends StatelessWidget {
  const AdminHolidaysCard({super.key});

  @override
  Widget build(BuildContext context) => AdminSectionCard(
    icon: LucideIcons.calendarHeart,
    title: context.t('availability.admin.cardTitle'),
    subtitle: context.t('availability.admin.cardHint'),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: () => context.go('/admin/holidays'),
            icon: Icon(forwardArrow(context), size: 16),
            label: Text(context.t('availability.admin.open')),
          ),
        ),
      ),
    ],
  );
}
