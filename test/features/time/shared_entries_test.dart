import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_share_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/time/shares/share_entry_sheet.dart';
import 'package:hinata/features/time/shares/shared_entries_screen.dart';
import 'package:hinata/features/time/shares/shared_inbox_notice.dart';

/// Shared entries (HIN-95): the inbox empty and with an invitation, the two
/// answers, the notice above the list, and offering an entry to a colleague
/// through the project's people.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  final invitation = TimeEntryShare(
    id: 's1',
    status: TimeShareStatus.pending,
    from: const TimeSharePerson(id: 'u1', name: 'Ada'),
    to: const TimeSharePerson(id: 'me', name: 'Linus'),
    projectId: 'p1',
    projectName: 'Hinata',
    date: DateTime(2026, 9, 4),
    durationMinutes: 90,
    description: 'Pairing on the release',
    tags: const ['review'],
  );

  Future<_FakeShares> pumpScreen(
    WidgetTester tester,
    List<TimeEntryShare> inbox, {
    TimeShareBox box = TimeShareBox.inbox,
  }) async {
    final repository = _FakeShares(inbox: inbox);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<TimeRepository>.value(
        value: repository,
        child: MaterialApp(
          home: Scaffold(body: SharedEntriesScreen(box: box)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('an empty inbox says what will arrive there', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('time.share.empty.inbox.title'), findsOneWidget);
    expect(find.text('time.share.accept'), findsNothing);
  });

  testWidgets('an invitation shows the entry as offered and who offered it', (
    tester,
  ) async {
    await pumpScreen(tester, [invitation]);

    expect(find.text('Pairing on the release'), findsOneWidget);
    expect(find.text('time.share.from'), findsOneWidget);
    expect(find.textContaining('Hinata'), findsOneWidget);
    expect(find.text('#review'), findsOneWidget);
    expect(find.text('time.share.accept'), findsOneWidget);
    expect(find.text('time.share.decline'), findsOneWidget);
  });

  testWidgets(
    'accepting files the copy and takes the invitation off the list',
    (tester) async {
      final repository = await pumpScreen(tester, [invitation]);

      await tester.tap(find.text('time.share.accept'));
      await tester.pumpAndSettle();

      expect(repository.accepted, ['s1']);
      expect(find.text('Pairing on the release'), findsNothing);
    },
  );

  testWidgets('declining sends no reason and takes it off the list', (
    tester,
  ) async {
    final repository = await pumpScreen(tester, [invitation]);

    await tester.tap(find.text('time.share.decline'));
    await tester.pumpAndSettle();

    expect(repository.declined, ['s1']);
    expect(find.text('Pairing on the release'), findsNothing);
  });

  testWidgets('the sent list offers taking back only what is unanswered', (
    tester,
  ) async {
    final repository = _FakeShares(
      sent: const [
        TimeEntryShare(
          id: 'a',
          status: TimeShareStatus.pending,
          from: TimeSharePerson(id: 'me', name: 'Linus'),
          to: TimeSharePerson(id: 'u1', name: 'Ada'),
          entryId: 'w1',
        ),
        TimeEntryShare(
          id: 'b',
          status: TimeShareStatus.declined,
          from: TimeSharePerson(id: 'me', name: 'Linus'),
          to: TimeSharePerson(id: 'u2', name: 'Grace'),
          entryId: 'w1',
        ),
      ],
    );
    await tester.pumpWidget(
      RepositoryProvider<TimeRepository>.value(
        value: repository,
        child: const MaterialApp(
          home: Scaffold(body: SharedEntriesScreen(box: TimeShareBox.sent)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('time.share.status.pending'), findsOneWidget);
    expect(find.text('time.share.status.declined'), findsOneWidget);
    expect(find.text('time.share.revoke'), findsOneWidget);

    await tester.tap(find.text('time.share.revoke'));
    await tester.pumpAndSettle();
    expect(repository.revoked, [('w1', 'u1')]);
  });

  testWidgets('the notice above the list appears only while something waits', (
    tester,
  ) async {
    Future<void> pumpNotice(_FakeShares repository) async {
      final inbox = SharedInboxCubit(repository);
      addTearDown(inbox.close);
      await inbox.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: inbox,
              child: const SharedInboxNotice(),
            ),
          ),
        ),
      );
    }

    await pumpNotice(_FakeShares());
    expect(find.text('time.share.waiting'), findsNothing);

    await pumpNotice(_FakeShares(inbox: [invitation]));
    expect(find.text('time.share.waiting'), findsOneWidget);
  });

  testWidgets('sharing picks people of the project and sends their ids', (
    tester,
  ) async {
    final repository = _FakeShares(
      candidates: const [
        DirectoryUser(id: 'u2', username: 'grace', displayName: 'Grace'),
      ],
    );
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<TimeRepository>.value(
        value: repository,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShareEntrySheet(
                  context,
                  entry: const WorkItem(
                    id: 'w1',
                    projectId: 'p1',
                    userId: 'me',
                    durationMinutes: 30,
                    activityType: 'Development',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Nobody picked yet: nothing to send.
    final send = find.widgetWithText(FilledButton, 'time.share.send');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    await tester.tap(find.text('time.share.addPerson'));
    await tester.pumpAndSettle();
    expect(repository.candidateProjects, contains('p1'));
    await tester.tap(find.text('Grace').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Grace'), findsOneWidget);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(repository.shared, hasLength(1));
    expect(repository.shared.single.$1, 'w1');
    expect(repository.shared.single.$2, ['u2']);
  });

  testWidgets('somebody already asked is not offered again', (tester) async {
    final repository = _FakeShares(
      candidates: const [
        DirectoryUser(id: 'u2', username: 'grace', displayName: 'Grace'),
        DirectoryUser(id: 'u3', username: 'alan', displayName: 'Alan'),
      ],
      asked: const [
        TimeEntryShare(
          id: 'a',
          status: TimeShareStatus.declined,
          from: TimeSharePerson(id: 'me'),
          to: TimeSharePerson(id: 'u2', name: 'Grace'),
        ),
      ],
    );
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<TimeRepository>.value(
        value: repository,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShareEntrySheet(
                  context,
                  entry: const WorkItem(
                    id: 'w1',
                    projectId: 'p1',
                    userId: 'me',
                    durationMinutes: 30,
                    activityType: 'Development',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('time.share.addPerson'));
    await tester.pumpAndSettle();

    expect(find.text('Alan'), findsOneWidget);
    // Grace is listed once, under those already asked, and not in the picker.
    expect(find.text('Grace'), findsOneWidget);
  });
}

class _FakeShares implements TimeRepository {
  _FakeShares({
    List<TimeEntryShare> inbox = const [],
    this.sent = const [],
    this.candidates = const [],
    this.asked = const [],
  }) : inbox = [...inbox];

  final List<TimeEntryShare> asked;

  final List<TimeEntryShare> inbox;
  final List<TimeEntryShare> sent;
  final List<DirectoryUser> candidates;
  final List<String> accepted = [];
  final List<String> declined = [];
  final List<(String, String)> revoked = [];
  final List<(String, List<String>)> shared = [];
  final List<String> candidateProjects = [];

  @override
  Future<PageResult<TimeEntryShare>> shares(
    TimeShareBox box, {
    int page = 0,
    int size = 20,
  }) async {
    final rows = box == TimeShareBox.inbox ? inbox : sent;
    return (items: List.of(rows), total: rows.length);
  }

  @override
  Future<WorkItem> acceptShare(
    String id, {
    TimeShareAcceptance acceptance = const TimeShareAcceptance(),
  }) async {
    accepted.add(id);
    inbox.removeWhere((share) => share.id == id);
    return WorkItem(
      id: 'copy-$id',
      durationMinutes: 90,
      activityType: 'Development',
    );
  }

  @override
  Future<void> declineShare(String id) async {
    declined.add(id);
    inbox.removeWhere((share) => share.id == id);
  }

  @override
  Future<void> revokeShare(String entryId, String userId) async =>
      revoked.add((entryId, userId));

  @override
  Future<List<TimeEntryShare>> entryShares(String entryId) async => asked;

  @override
  Future<List<TimeEntryShare>> shareEntry(
    String entryId,
    List<String> userIds,
  ) async {
    shared.add((entryId, userIds));
    return const [];
  }

  @override
  Future<PageResult<DirectoryUser>> shareCandidates(
    String projectId, {
    String query = '',
    int page = 0,
    int size = 20,
  }) async {
    candidateProjects.add(projectId);
    return (items: candidates, total: candidates.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
