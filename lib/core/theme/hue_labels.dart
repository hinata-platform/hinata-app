import 'package:flutter/widgets.dart';

import '../i18n/i18n.dart';

/// The translated name of a stored oklch hue, for the swatch pickers'
/// screen-reader labels and the captions beside a chosen colour.
///
/// Covers the shared palette (`kLabelHues`, which the projects, labels,
/// knowledge spaces and teams pick from) and the absence-type swatches. A
/// `null` hue is the "no colour of its own" swatch; any hue outside both
/// palettes reads as custom.
String hueLabel(BuildContext context, int? hue) => context.t(switch (hue) {
  null => 'common.hue.default',
  5 => 'common.hue.red',
  20 => 'common.hue.coral',
  30 => 'common.hue.orange',
  45 => 'common.hue.amber',
  70 => 'common.hue.honey',
  95 || 155 => 'common.hue.green',
  160 || 200 => 'common.hue.teal',
  195 => 'common.hue.cyan',
  225 => 'common.hue.blue',
  250 => 'common.hue.indigo',
  265 || 300 => 'common.hue.violet',
  320 || 330 => 'common.hue.pink',
  _ => 'common.hue.custom',
});
