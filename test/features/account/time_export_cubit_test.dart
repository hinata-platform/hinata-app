import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/account/time_export_cubit.dart';

import '../../support/recording_fake.dart';

/// The copy of the reader's own entries is asked for whole: no window travels.
void main() {
  late FakeTimeRepository time;
  late TimeExportCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    cubit = TimeExportCubit(time);
  });
  tearDown(() => cubit.close());

  test('the bytes are every entry, unbounded', () async {
    final file = (bytes: Uint8List(3), truncated: true);
    time.answer<({Uint8List bytes, bool truncated})>(#exportCsv, file);

    expect(await cubit.csv(), file);
    expect(time.only.namedArguments, {#from: null, #to: null});
  });

  test('the file is written to the path it was given', () async {
    time.answer<bool>(#exportCsvTo, false);

    expect(await cubit.csvTo('/tmp/time.csv'), isFalse);
    expect(time.only.positionalArguments, ['/tmp/time.csv']);
    expect(time.only.namedArguments, {#from: null, #to: null});
  });

  test('a refused export comes back as the same failure', () async {
    time.fail(#exportCsvTo, failure);

    await expectLater(cubit.csvTo('/tmp/time.csv'), throwsA(same(failure)));
  });
}
