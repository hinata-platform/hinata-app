import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_policy_models.dart';

/// The billable switch of an edited entry shows what the server will store: a
/// flag that was the old project's default follows the entry to the new one,
/// any other flag stays — and until both defaults are read, the entry's own.
void main() {
  const instanceOff = TimePolicySnapshot();
  const instanceOn = TimePolicySnapshot(defaultBillable: true);

  bool after(
    TimePolicySnapshot policy, {
    bool entryBillable = false,
    String? from,
    String? to,
    ({bool? value})? fromDefault,
    ({bool? value})? toDefault,
  }) => policy.billableAfterMove(
    entryBillable: entryBillable,
    fromProjectId: from,
    toProjectId: to,
    fromDefault: fromDefault,
    toDefault: toDefault,
  );

  test('an entry that does not move keeps its own flag', () {
    expect(after(instanceOff, entryBillable: true, from: 'a', to: 'a'), isTrue);
  });

  test(
    'an unfiled entry at the instance default follows a billing project',
    () {
      expect(after(instanceOff, to: 'b', toDefault: (value: true)), isTrue);
    },
  );

  test('a flag that differs from the old default was a choice and stays', () {
    expect(
      after(
        instanceOff,
        entryBillable: true,
        to: 'b',
        toDefault: (value: false),
      ),
      isTrue,
    );
  });

  test('a project that follows the instance gives the instance default', () {
    expect(
      after(
        instanceOn,
        entryBillable: true,
        from: 'a',
        to: 'b',
        fromDefault: (value: null),
        toDefault: (value: false),
      ),
      isFalse,
    );
  });

  test('taking the project off falls back to the instance default', () {
    expect(
      after(
        instanceOff,
        entryBillable: true,
        from: 'a',
        fromDefault: (value: true),
      ),
      isFalse,
    );
  });

  test('while the old default is unread the entry keeps its flag', () {
    expect(after(instanceOff, entryBillable: true, from: 'a', to: 'b'), isTrue);
  });

  test('while the new default is unread the entry keeps its flag', () {
    expect(after(instanceOff, to: 'b'), isFalse);
    expect(after(instanceOn, entryBillable: true, to: 'b'), isTrue);
  });
}
