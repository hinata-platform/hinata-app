import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/issue_detail.dart';
import 'package:hinata/features/issues/participants/issue_participants_cubit.dart';

import '../../../support/recording_fake.dart';

void main() {
  const helen = IssueParticipant(id: 'u2', displayName: 'Helen');
  const omar = DirectoryUser(id: 'u3', username: 'omar', displayName: 'Omar');
  const member = DirectoryUser(
    id: 'u1',
    username: 'rebar',
    displayName: 'Rebar',
  );

  late FakeIssueRepository issues;

  setUp(() => issues = FakeIssueRepository());

  IssueParticipantsCubit build() => IssueParticipantsCubit(
    issues: issues,
    issueId: 'i1',
    meId: 'u1',
    members: const [member],
  );

  blocTest<IssueParticipantsCubit, IssueParticipantsState>(
    'loads the participants and keeps the members it was given',
    setUp: () => issues.answer(#participants, const [helen]),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [
      const IssueParticipantsState(members: [member], loading: true),
      const IssueParticipantsState(members: [member], participants: [helen]),
    ],
  );

  blocTest<IssueParticipantsCubit, IssueParticipantsState>(
    'adding shows the person at once and keeps what the server lists',
    setUp: () {
      issues.answer<void>(#addParticipant, null);
      issues.answer(#participants, const [
        helen,
        IssueParticipant(id: 'u3', displayName: 'Omar', addedById: 'u1'),
      ]);
    },
    build: build,
    seed: () =>
        const IssueParticipantsState(members: [member], participants: [helen]),
    act: (cubit) async => expect(await cubit.add(omar), AddOutcome.added),
    verify: (cubit) {
      expect(cubit.state.participants.map((p) => p.id), ['u2', 'u3']);
      expect(cubit.state.busy, isEmpty);
      expect(issues.calls.first.positionalArguments, ['i1', 'u3']);
    },
  );

  blocTest<IssueParticipantsCubit, IssueParticipantsState>(
    'adding somebody the server does not list means they are a member',
    setUp: () {
      issues.answer<void>(#addParticipant, null);
      issues.answer(#participants, const [helen]);
    },
    build: build,
    seed: () =>
        const IssueParticipantsState(members: [member], participants: [helen]),
    act: (cubit) async =>
        expect(await cubit.add(omar), AddOutcome.alreadyMember),
    verify: (cubit) =>
        expect(cubit.state.participants.map((p) => p.id), ['u2']),
  );

  blocTest<IssueParticipantsCubit, IssueParticipantsState>(
    'a failed add rolls back and names the error',
    setUp: () => issues.fail(
      #addParticipant,
      ApiFailure('error.issue.participantsFull', statusCode: 400),
    ),
    build: build,
    seed: () => const IssueParticipantsState(participants: [helen]),
    act: (cubit) async => expect(await cubit.add(omar), AddOutcome.failed),
    verify: (cubit) {
      expect(cubit.state.participants, [helen]);
      expect(cubit.state.errorKey, 'error.issue.participantsFull');
    },
  );

  blocTest<IssueParticipantsCubit, IssueParticipantsState>(
    'removing is immediate and a failure puts the row back in place',
    setUp: () => issues.fail(#removeParticipant, ApiFailure('error.x')),
    build: build,
    seed: () => const IssueParticipantsState(
      participants: [
        helen,
        IssueParticipant(id: 'u3', displayName: 'Omar'),
      ],
    ),
    act: (cubit) async => expect(await cubit.remove('u2'), isFalse),
    expect: () => [
      const IssueParticipantsState(
        participants: [IssueParticipant(id: 'u3', displayName: 'Omar')],
        busy: {'u2'},
      ),
      const IssueParticipantsState(
        participants: [
          helen,
          IssueParticipant(id: 'u3', displayName: 'Omar'),
        ],
        errorKey: 'error.x',
      ),
    ],
  );

  test('twenty-five participants leave no room', () {
    final full = IssueParticipantsState(
      participants: [
        for (var i = 0; i < IssueParticipantsCubit.maxParticipants; i++)
          IssueParticipant(id: 'u$i', displayName: 'P$i'),
      ],
    );

    expect(full.isFull, isTrue);
    expect(const IssueParticipantsState().isFull, isFalse);
  });

  test('a person already shared with is not added twice', () async {
    final cubit = build();
    cubit.emit(const IssueParticipantsState(participants: [helen]));

    expect(
      await cubit.add(
        const DirectoryUser(id: 'u2', username: 'helen', displayName: 'Helen'),
      ),
      AddOutcome.alreadyShared,
    );
    expect(issues.calls, isEmpty);
    await cubit.close();
  });

  test('a member picked from the directory is not sent', () async {
    final cubit = build();

    expect(await cubit.add(member), AddOutcome.alreadyMember);
    expect(issues.calls, isEmpty);
    await cubit.close();
  });

  test('leaving removes the caller', () async {
    final done = Completer<void>();
    issues.answerWith(#removeParticipant, (_) {
      done.complete();
      return Future<void>.value();
    });
    final cubit = build();

    expect(await cubit.leave(), isTrue);
    await done.future;
    expect(issues.only.positionalArguments, ['i1', 'u1']);
    await cubit.close();
  });
}
