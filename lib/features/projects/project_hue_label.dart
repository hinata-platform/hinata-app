import 'package:flutter/widgets.dart';

import '../../core/i18n/i18n.dart';

/// The translated name of one of the eight palette hues ([kProjectHues],
/// [kLabelHues]), for the swatch pickers' screen-reader labels and the
/// caption beside the project accent row. The team palette already names six
/// of them under `teams.color.*`; the project palette adds pink and amber.
String projectHueLabel(BuildContext context, int hue) =>
    context.t(switch (hue) {
      70 => 'teams.color.honey',
      250 => 'teams.color.indigo',
      300 => 'teams.color.violet',
      200 => 'teams.color.teal',
      155 => 'teams.color.green',
      20 => 'teams.color.coral',
      330 => 'teams.color.pink',
      45 => 'teams.color.amber',
      _ => 'teams.color.custom',
    });
