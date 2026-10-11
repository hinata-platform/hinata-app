import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/timer_surfaces/time_deep_link.dart';

void main() {
  test('opens the focus screen', () {
    expect(timeDeepLinkRoute(Uri.parse('hinata://time/focus')), '/time/focus');
  });

  test('a query never turns into an action', () {
    expect(
      timeDeepLinkRoute(Uri.parse('hinata://time/focus?action=stop')),
      '/time/focus',
    );
  });

  test('anything else under time opens the module, other hosts nothing', () {
    expect(timeDeepLinkRoute(Uri.parse('hinata://time/whatever/x')), '/time');
    expect(timeDeepLinkRoute(Uri.parse('hinata://time')), '/time');
    expect(timeDeepLinkRoute(Uri.parse('hinata://invite/focus')), isNull);
    expect(timeDeepLinkRoute(Uri.parse('https://time/focus')), isNull);
  });
}
