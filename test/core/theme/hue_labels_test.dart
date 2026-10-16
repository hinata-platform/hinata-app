import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/hue_labels.dart';

void main() {
  test('nearestHueKey names the closest family for any degree', () {
    expect(nearestHueKey(79), 'common.hue.honey');
    expect(nearestHueKey(155), 'common.hue.green');
    expect(nearestHueKey(230), 'common.hue.blue');
    expect(nearestHueKey(0), 'common.hue.red');
    expect(nearestHueKey(359), 'common.hue.red');
    for (var hue = 0; hue < 360; hue++) {
      expect(nearestHueKey(hue), startsWith('common.hue.'));
      expect(nearestHueKey(hue), isNot('common.hue.custom'));
    }
  });
}
