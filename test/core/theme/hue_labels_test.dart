import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/hue_labels.dart';

void main() {
  test('hueFamilyKey names the closest family for any degree', () {
    // OKLCH hues: sRGB red sits at 29, orange at 53, magenta at 328.
    expect(hueFamilyKey(29), 'common.hue.red');
    expect(hueFamilyKey(53), 'common.hue.orange');
    expect(hueFamilyKey(79), 'common.hue.honey');
    expect(hueFamilyKey(155), 'common.hue.green');
    expect(hueFamilyKey(250), 'common.hue.blue');
    expect(hueFamilyKey(0), 'common.hue.pink');
    expect(hueFamilyKey(350), 'common.hue.pink');
    for (var hue = 0; hue < 360; hue++) {
      expect(hueFamilyKey(hue), startsWith('common.hue.'));
      expect(hueFamilyKey(hue), isNot('common.hue.custom'));
    }
  });

  test('the bands match the server\'s table', () {
    // The one table both sides cut the circle with; the server's
    // TintHueNamesTest asserts the same literal. Change both or neither.
    const ends = [11, 37, 62, 74, 105, 170, 190, 235, 270, 290, 315, 359];
    const keys = [
      'pink',
      'red',
      'orange',
      'amber',
      'honey',
      'green',
      'teal',
      'cyan',
      'blue',
      'indigo',
      'violet',
      'pink',
    ];
    var start = 0;
    for (var i = 0; i < ends.length; i++) {
      for (var hue = start; hue <= ends[i]; hue++) {
        expect(hueFamilyKey(hue), 'common.hue.${keys[i]}', reason: 'hue $hue');
      }
      start = ends[i] + 1;
    }
    for (var hue = start; hue < 360; hue++) {
      expect(hueFamilyKey(hue), 'common.hue.red');
    }
  });
}
