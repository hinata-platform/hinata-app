// import 'package:flutter_test/flutter_test.dart';
// import 'package:hivora/core/models/core_models.dart';

// void main() {
//   group('isVersionBelow', () {
//     test('detects older versions', () {
//       expect(isVersionBelow('1.0.0', '1.0.1'), isTrue);
//       expect(isVersionBelow('1.2.0', '2.0.0'), isTrue);
//     });

//     test('accepts equal and newer versions', () {
//       expect(isVersionBelow('1.0.0', '1.0.0'), isFalse);
//       expect(isVersionBelow('2.1.0', '1.9.9'), isFalse);
//     });

//     test('tolerates suffixes and short versions', () {
//       expect(isVersionBelow('1.0', '1.0.0'), isFalse);
//       expect(isVersionBelow('1.0.0-beta', '1.0.1'), isTrue);
//     });
//   });

//   group('ServerMeta', () {
//     test('parses json with defaults', () {
//       final meta = ServerMeta.fromJson(const {
//         'serverVersion': '1.0.0',
//         'minAppVersion': '1.0.0',
//         'setupCompleted': true,
//         'featureFlags': {'gantt': true},
//       });
//       expect(meta.setupCompleted, isTrue);
//       expect(meta.isFlagEnabled('gantt'), isTrue);
//       expect(meta.isFlagEnabled('unknown'), isFalse);
//     });
//   });
// }
