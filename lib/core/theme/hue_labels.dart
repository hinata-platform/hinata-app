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
  70 || 79 => 'common.hue.honey',
  95 || 155 => 'common.hue.green',
  160 || 200 => 'common.hue.teal',
  195 => 'common.hue.cyan',
  225 => 'common.hue.blue',
  250 => 'common.hue.indigo',
  265 || 300 => 'common.hue.violet',
  320 || 330 => 'common.hue.pink',
  _ => 'common.hue.custom',
});

/// The family a hue belongs to, for any degree on the circle: the slider's
/// spoken value and the caption of a hue between the named ones. A lookup in
/// fixed bands, one per family, in the order of the circle from red; the
/// server's `TintHueNames` cuts the same bands so the Art. 15 report agrees
/// (`hue_labels_test.dart` and `TintHueNamesTest` pin the same table).
String hueFamilyKey(int hue) {
  final degrees = hue % 360;
  for (var i = 0; i < _bandEnds.length; i++) {
    if (degrees <= _bandEnds[i]) return _bandKeys[i];
  }
  return _bandKeys.first;
}

/// [hueFamilyKey], translated.
String hueFamilyLabel(BuildContext context, int hue) =>
    context.t(hueFamilyKey(hue));

const _bandEnds = [12, 25, 37, 60, 90, 157, 185, 205, 237, 262, 310, 347];
const _bandKeys = [
  'common.hue.red',
  'common.hue.coral',
  'common.hue.orange',
  'common.hue.amber',
  'common.hue.honey',
  'common.hue.green',
  'common.hue.teal',
  'common.hue.cyan',
  'common.hue.blue',
  'common.hue.indigo',
  'common.hue.violet',
  'common.hue.pink',
];
