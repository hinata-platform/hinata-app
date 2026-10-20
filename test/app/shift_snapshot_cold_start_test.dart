import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/app.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/shifts/bloc/my_shifts_snapshot_cubit.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/shifts/shift_fakes.dart';
import '../support/timer_surface_fakes.dart';

/// A session that ends while the app is closed (revoked, expired, password
/// reset) leaves no offline shifts behind on the next start.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryStorage hydrated;

  setUp(() {
    hydrated = MemoryStorage();
    HydratedBloc.storage = hydrated;
  });

  Future<AppStorage> storage(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
  }

  test('the snapshot of the account that was signed in is deleted', () async {
    const id = 'shifts#https://a.test#u1';
    final kept = MyShiftsSnapshotCubit(storageId: id)
      ..recordRows([sampleMine()]);
    await Future<void>.delayed(Duration.zero);
    await kept.close();
    expect(hydrated.values, isNotEmpty);

    final store = await storage({'hinata.shiftSnapshotId': id});
    await forgetLeftoverShiftSnapshot(store);

    expect(hydrated.values.values.whereType<Map>(), isEmpty);
    expect(MyShiftsSnapshotCubit(storageId: id).state.isEmpty, isTrue);
    expect(store.shiftSnapshotId, isNull);
  });

  test('nothing happens when no account kept a snapshot', () async {
    final store = await storage({});
    await forgetLeftoverShiftSnapshot(store);

    expect(hydrated.values, isEmpty);
    expect(store.shiftSnapshotId, isNull);
  });
}
