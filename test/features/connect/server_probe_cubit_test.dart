import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart' show ServerProbe;
import 'package:hinata/features/connect/server_probe_cubit.dart';

import '../../support/recording_fake.dart';

/// The server manager pings saved servers and tests a new one through this
/// cubit; an unreachable server answers null, never an error.
void main() {
  late FakeMetaRepository meta;
  late ServerProbeCubit cubit;

  setUp(() {
    meta = FakeMetaRepository();
    cubit = ServerProbeCubit(meta);
  });
  tearDown(() => cubit.close());

  test('a reachable server answers its probe', () async {
    const probe = ServerProbe(
      ms: 42,
      version: '1.0.0',
      tls: true,
      setupCompleted: true,
    );
    meta.answer<ServerProbe?>(#probeServer, probe);

    expect(await cubit.probe('https://a.example'), same(probe));
    expect(meta.only.positionalArguments, ['https://a.example']);
  });

  test('an unreachable one answers null', () async {
    meta.answer<ServerProbe?>(#probeServer, null);

    expect(await cubit.probe('https://b.example'), isNull);
  });
}
