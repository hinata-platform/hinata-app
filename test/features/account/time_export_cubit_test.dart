import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/account/time_export_cubit.dart';

import '../recording_fake.dart';

class _FakeTime with RecordingFake implements TimeRepository {}

/// The copy of the reader's own entries is asked for whole: no window travels.
void main() {
  late _FakeTime time;
  late TimeExportCubit cubit;

  setUp(() {
    time = _FakeTime();
    cubit = TimeExportCubit(time);
  });
  tearDown(() => cubit.close());

  test('the bytes are every entry, unbounded', () async {
    final file = (bytes: Uint8List(3), truncated: true);
    time.answers[#exportCsv] = () =>
        Future<({Uint8List bytes, bool truncated})>.value(file);

    expect(await cubit.csv(), file);
    expect(time.only.namedArguments, {#from: null, #to: null});
  });

  test('the file is written to the path it was given', () async {
    time.answers[#exportCsvTo] = () => Future<bool>.value(false);

    expect(await cubit.csvTo('/tmp/time.csv'), isFalse);
    expect(time.only.positionalArguments, ['/tmp/time.csv']);
    expect(time.only.namedArguments, {#from: null, #to: null});
  });

  test('a refused export comes back as the same failure', () async {
    time.answers[#exportCsvTo] = () => Future<bool>.error(failure);

    await expectLater(cubit.csvTo('/tmp/time.csv'), throwsA(same(failure)));
  });
}
