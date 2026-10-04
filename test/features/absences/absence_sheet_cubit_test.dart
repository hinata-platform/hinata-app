import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/absence_request_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/features/absences/absence_sheet_cubit.dart';

import 'recording_repositories.dart';

void main() {
  late RecordingAbsences absences;
  late RecordingAvailability availability;
  late RecordingUsers users;
  late AbsenceSheetCubit cubit;

  final request = AbsenceRequest(
    id: 'r1',
    userId: 'u1',
    typeId: 't1',
    from: DateTime(2026, 7, 6),
    to: DateTime(2026, 7, 10),
    status: AbsenceRequestStatus.submitted,
  );

  setUp(() {
    absences = RecordingAbsences();
    availability = RecordingAvailability();
    users = RecordingUsers();
    cubit = AbsenceSheetCubit(
      absences: absences,
      availability: availability,
      users: users,
    );
  });

  tearDown(() => cubit.close());

  test('request reads the one behind the sheet', () async {
    absences.answer<AbsenceRequest>(#request, request);

    expect(await cubit.request('r1'), same(request));
    expectCall(absences.only, #request, positional: ['r1']);
  });

  test('people reads the stand-in by id', () async {
    const found = [DirectoryUser(id: 's1', username: 'sam', displayName: '')];
    users.answer<List<DirectoryUser>>(#usersByIds, found);

    expect(await cubit.people(['s1']), same(found));
    expectCall(
      users.only,
      #usersByIds,
      positional: [
        ['s1'],
      ],
    );
  });

  test('each step goes to its own route with its note', () async {
    absences
      ..answer<AbsenceRequest>(#withdraw, request)
      ..answer<AbsenceRequest>(#cancel, request)
      ..answer<AbsenceRequest>(#approve, request)
      ..answer<AbsenceRequest>(#reject, request);

    expect(await cubit.withdraw('r1'), same(request));
    expect(await cubit.cancel('r1', note: 'plans changed'), same(request));
    expect(await cubit.approve('r1'), same(request));
    expect(await cubit.reject('r1', note: 'busy week'), same(request));

    expectCall(absences.calls[0], #withdraw, positional: ['r1']);
    expectCall(
      absences.calls[1],
      #cancel,
      positional: ['r1'],
      named: {#note: 'plans changed'},
    );
    // An approval without a note still sends the parameter, as null.
    expectCall(
      absences.calls[2],
      #approve,
      positional: ['r1'],
      named: {#note: null},
    );
    expectCall(
      absences.calls[3],
      #reject,
      positional: ['r1'],
      named: {#note: 'busy week'},
    );
  });

  test('a refused step hands the failure back unchanged', () async {
    absences.fail<AbsenceRequest>(#approve, failure);

    await expectLater(cubit.approve('r1'), throwsA(same(failure)));
  });

  test('deleteEntered deletes the absence, not a request', () async {
    availability.answer<void>(#deleteTimeOff, null);

    await cubit.deleteEntered('a1');

    expectCall(availability.only, #deleteTimeOff, positional: ['a1']);
    expect(absences.calls, isEmpty);
  });
}
