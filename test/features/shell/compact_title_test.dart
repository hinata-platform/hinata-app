import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/shell/app_shell.dart';

/// Where the compact app bar writes its title.
///
/// The bar centres a title in what the wider of its two sides leaves on both,
/// so a page with buttons on the right pays for them twice: the admin pages
/// read "Zeiterfass…" under three circles while half the bar stood empty.
void main() {
  test('a page with buttons writes its title on the leading edge', () {
    expect(compactTitleLeads(asked: false, hasActions: true), isTrue);
  });

  test('a page that asked for one gets one, buttons or not', () {
    expect(compactTitleLeads(asked: true, hasActions: false), isTrue);
    expect(compactTitleLeads(asked: true, hasActions: true), isTrue);
  });

  test('a bare page keeps its title in the middle', () {
    // Nothing on the right but the bell and the settings, which every page
    // carries: the title has the whole bar and centred is where it belongs.
    expect(compactTitleLeads(asked: false, hasActions: false), isFalse);
  });
}
