import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';

void main() {
  group('isVersionBelow', () {
    test('detects older versions', () {
      expect(isVersionBelow('1.0.0', '1.0.1'), isTrue);
      expect(isVersionBelow('1.2.0', '2.0.0'), isTrue);
    });

    test('accepts equal and newer versions', () {
      expect(isVersionBelow('1.0.0', '1.0.0'), isFalse);
      expect(isVersionBelow('2.1.0', '1.9.9'), isFalse);
    });

    test('tolerates suffixes and short versions', () {
      expect(isVersionBelow('1.0', '1.0.0'), isFalse);
      expect(isVersionBelow('1.0.0-beta', '1.0.1'), isTrue);
    });
  });

  group('ServerMeta', () {
    test('parses json with defaults', () {
      final meta = ServerMeta.fromJson(const {
        'serverVersion': '1.0.0',
        'minAppVersion': '1.0.0',
        'setupCompleted': true,
        'featureFlags': {'gantt': true},
      });
      expect(meta.setupCompleted, isTrue);
      expect(meta.isFlagEnabled('gantt'), isTrue);
      expect(meta.isFlagEnabled('unknown'), isFalse);
    });

    group('shift planning (HIN-49)', () {
      test('is off when the server does not mention it', () {
        final meta = ServerMeta.fromJson(const {'serverVersion': '1.0.0'});
        expect(meta.shiftPlanning, isFalse);
      });

      test('reads the flag the server reports', () {
        final on = ServerMeta.fromJson(const {
          'featureFlags': {PlatformFlags.shiftPlanning: true},
        });
        final off = ServerMeta.fromJson(const {
          'featureFlags': {PlatformFlags.shiftPlanning: false},
        });
        expect(PlatformFlags.shiftPlanning, 'shift_planning');
        expect(on.shiftPlanning, isTrue);
        expect(off.shiftPlanning, isFalse);
      });

      test('a server that predates availability counts as available', () {
        final meta = ServerMeta.fromJson(const {'serverVersion': '1.0.0'});
        expect(meta.shiftPlanningAvailable, isTrue);
      });

      test('a server without a replica set says so', () {
        final meta = ServerMeta.fromJson(const {
          'featureFlags': {PlatformFlags.shiftPlanning: false},
          'shiftPlanningAvailable': false,
        });
        expect(meta.shiftPlanningAvailable, isFalse);
        expect(meta.shiftPlanning, isFalse);
      });

      test(
        'flipping the flag yields a different meta, so the shell rebuilds',
        () {
          final off = ServerMeta.fromJson(const {
            'featureFlags': {PlatformFlags.shiftPlanning: false},
          });
          final on = ServerMeta.fromJson(const {
            'featureFlags': {PlatformFlags.shiftPlanning: true},
          });
          final unavailable = ServerMeta.fromJson(const {
            'featureFlags': {PlatformFlags.shiftPlanning: false},
            'shiftPlanningAvailable': false,
          });
          expect(on, isNot(off));
          expect(unavailable, isNot(off));
        },
      );
    });
  });
}
