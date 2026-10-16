import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/account_models.dart';

void main() {
  test('round-trips through json', () {
    const prefs = TintPreferences(style: TintStyle.tinted, hue: 0, level: 0);
    expect(TintPreferences.fromJson(prefs.toJson()), prefs);
    expect(prefs.toJson(), {'style': 'TINTED', 'hue': 0, 'level': 0});
  });

  test('unknown or missing values fall back to the standard', () {
    expect(TintPreferences.fromJson(const {}), TintPreferences.standard);
    expect(
      TintPreferences.fromJson(const {
        'style': 'GLASS',
        'hue': 500,
        'level': -3,
      }),
      const TintPreferences(style: TintStyle.defaultStyle, hue: 359, level: 0),
    );
    expect(TintPreferences.standard.style, TintStyle.defaultStyle);
    expect(TintPreferences.standard.hue, 79);
    expect(TintPreferences.standard.level, 100);
  });

  test('Me carries the tint and defaults it when absent', () {
    final me = Me.fromJson(const {
      'id': 'u',
      'displayName': 'A',
      'username': 'a',
      'email': 'a@b.c',
      'emailVerified': true,
      'origin': 'LOCAL',
      'roles': <String>[],
      'active': true,
      'tint': {'style': 'TINTED', 'hue': 120, 'level': 40},
    });
    expect(
      me.tint,
      const TintPreferences(style: TintStyle.tinted, hue: 120, level: 40),
    );
    expect(
      Me.fromJson(const {
        'id': 'u',
        'displayName': 'A',
        'username': 'a',
        'email': 'a@b.c',
        'emailVerified': true,
        'origin': 'LOCAL',
        'roles': <String>[],
        'active': true,
      }).tint,
      TintPreferences.standard,
    );
  });
}
