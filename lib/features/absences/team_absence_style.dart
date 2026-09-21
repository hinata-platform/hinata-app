/// What the team absence calendar looks like wherever it is drawn (HIN-118):
/// the band on a wide window, the weekly agenda on a phone, the dashboard's
/// list of who is away today. One place, so the three say the same thing about
/// the same absence.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/team_absence_models.dart';
import '../../core/theme/app_colors.dart';
import 'absence_labels.dart';

/// How close to the end of a list the next page is asked for.
const double kTeamAbsenceNearEnd = 300;

/// What an entry is called on the band: the type the reader may see, or
/// "away" when they may only know that.
String teamAbsenceLabel(BuildContext context, TeamAbsenceEntry entry) {
  final own = entry.typeName?.trim() ?? '';
  if (own.isNotEmpty) return own;
  final system = entry.typeSystemKey;
  if (entry.typed && system != null) return context.t('absence.type.$system');
  if (entry.typed && entry.typeKey != null) return entry.typeKey!;
  return context.t('absence.team.away');
}

/// A rounded bar: a pale wash of the type's colour with a hairline of it for
/// an absence, the same outline with a hatch and no wash for a request. The
/// word and the icon on top carry the meaning; the colour only groups.
class TeamAbsenceBarPainter extends CustomPainter {
  TeamAbsenceBarPainter({
    required this.color,
    this.hatched = false,
    this.outline,
  });

  final Color color;
  final bool hatched;

  /// The edge of a request, in the text colour of its type: without a wash it
  /// is the only thing that outlines the bar, so it has to clear 3:1.
  final Color? outline;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(math.min(7, size.height / 2)),
    );
    if (hatched) {
      canvas.save();
      canvas.clipRRect(shape);
      final lines = Path();
      const step = 6.0;
      for (var x = -size.height; x < size.width; x += step) {
        lines
          ..moveTo(x, size.height)
          ..lineTo(x + size.height, 0);
      }
      canvas.drawPath(
        lines,
        Paint()
          ..color = color.withValues(alpha: 0.30)
          ..strokeWidth = 1.1
          ..style = PaintingStyle.stroke,
      );
      canvas.restore();
    } else {
      canvas.drawRRect(shape, Paint()..color = color.withValues(alpha: 0.20));
    }
    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..color = outline ?? color.withValues(alpha: 0.45)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant TeamAbsenceBarPainter old) =>
      old.color != color || old.hatched != hatched || old.outline != outline;
}

/// [teamAbsenceLabel], and "requested" beside it for an open request: the hatch
/// alone would leave the state to colour and texture.
String teamAbsenceLabelWithState(BuildContext context, TeamAbsenceEntry entry) {
  final label = teamAbsenceLabel(context, entry);
  return entry.requested
      ? '$label · ${context.t('absence.team.legend.requested')}'
      : label;
}

/// The colour, the ink on it and the icon of one entry.
class TeamAbsenceVisuals {
  const TeamAbsenceVisuals({
    required this.tint,
    required this.ink,
    required this.icon,
  });

  factory TeamAbsenceVisuals.of(BuildContext context, TeamAbsenceEntry entry) =>
      TeamAbsenceVisuals(
        tint: entry.typed
            ? absenceColor(context, entry.hue)
            : AppColors.inkSoft,
        ink: entry.typed ? absenceInk(context, entry.hue) : AppColors.ink,
        icon: entry.requested
            ? LucideIcons.hourglass
            : entry.typed
            ? absenceIcon(entry.icon)
            : LucideIcons.calendarOff,
      );

  final Color tint;
  final Color ink;
  final IconData icon;

  /// The bar behind a label: a wash for an absence, an outline and a hatch in
  /// the ink for a request.
  TeamAbsenceBarPainter painter(TeamAbsenceEntry entry) =>
      TeamAbsenceBarPainter(
        color: tint,
        hatched: entry.requested,
        outline: entry.requested ? ink : null,
      );
}

/// Minutes as hours in the reader's locale, one decimal only where needed.
String formatAbsenceHours(BuildContext context, int minutes) =>
    NumberFormat.decimalPatternDigits(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: minutes % 60 == 0 ? 0 : 1,
    ).format(minutes / 60);
