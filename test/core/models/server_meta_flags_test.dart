import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';

/// [ServerMeta] is what the whole app reads its platform flags from, and it is
/// compared by value: blocs only emit, and `context.watch` only rebuilds, when
/// the new object is *unequal* to the old one.
///
/// `featureFlags` used to be left out of `props`, which made two metas with
/// opposite flags compare equal — so an admin switching a module on changed
/// nothing on screen until the app was restarted. These tests pin that down.
void main() {
  ServerMeta meta({Map<String, bool> flags = const {}, UploadLimits? limits}) =>
      ServerMeta(
        serverVersion: '1.0.0',
        minAppVersion: '1.0.0',
        setupCompleted: true,
        featureFlags: flags,
        uploadLimits: limits ?? const UploadLimits(),
      );

  group('equality', () {
    test('two metas differing only in a feature flag are not equal', () {
      expect(
        meta(flags: const {PlatformFlags.advancedTimeTracking: true}),
        isNot(equals(meta(flags: const {}))),
      );
    });

    test('a flag flipping from on to off is a change', () {
      expect(
        meta(flags: const {PlatformFlags.advancedTimeTracking: true}),
        isNot(
          equals(meta(flags: const {PlatformFlags.advancedTimeTracking: false})),
        ),
      );
    });

    test('the same flags still compare equal', () {
      expect(
        meta(flags: const {PlatformFlags.advancedTimeTracking: true}),
        equals(meta(flags: const {PlatformFlags.advancedTimeTracking: true})),
      );
    });

    test('changed upload limits are a change too', () {
      expect(
        meta(limits: const UploadLimits(maxFileMb: 25)),
        isNot(equals(meta(limits: const UploadLimits(maxFileMb: 50)))),
      );
    });
  });

  group('advancedTimeTracking', () {
    test('defaults to off when the server says nothing', () {
      expect(meta().advancedTimeTracking, isFalse);
    });

    test('reads the snake_case wire key', () {
      final parsed = ServerMeta.fromJson(const {
        'serverVersion': '1.0.0',
        'minAppVersion': '1.0.0',
        'setupCompleted': true,
        'featureFlags': {'advanced_time_tracking': true},
      });
      expect(parsed.advancedTimeTracking, isTrue);
      expect(PlatformFlags.advancedTimeTracking, 'advanced_time_tracking');
    });

    test('an explicit false stays false', () {
      expect(
        meta(
          flags: const {PlatformFlags.advancedTimeTracking: false},
        ).advancedTimeTracking,
        isFalse,
      );
    });
  });
}
