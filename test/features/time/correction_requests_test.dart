import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/correction_requests.dart';

/// The requests an administrator or a lead answers (HIN-89).
///
/// Two things are worth asserting here. Opening the days is offered only where
/// the server says this reader can do it, because a button the server refuses
/// teaches people to distrust the button. And an answer lands on the card it
/// answers, without reading the whole list again.
void main() {
  final span = TimeCorrectionRequest(
    id: 'r1',
    kind: TimeCorrectionRequest.kindSpan,
    from: DateTime(2025, 6, 2),
    to: DateTime(2025, 6, 6),
    reason: 'MAX_DAYS_BACK',
    note: 'Nachtrag nach dem Urlaub',
    requesterLabel: 'Ada',
    at: DateTime.utc(2026, 9, 12, 8),
    grantable: true,
  );
  final approval = TimeCorrectionRequest(
    id: 'r2',
    entryId: 'w1',
    date: DateTime(2026, 8, 20),
    projectId: 'p1',
    reason: 'APPROVAL',
    note: 'Es waren 90 Minuten',
    requesterLabel: 'Linus',
    at: DateTime.utc(2026, 9, 12, 9),
  );

  Future<_FakeTimeRepository> show(WidgetTester tester) async {
    final repository = _FakeTimeRepository([span, approval]);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<TimeRepository>.value(value: repository),
          RepositoryProvider<ProjectRepository>.value(
            value: const _FakeProjectRepository(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CorrectionRequestsList(embedded: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('only a request the server lets this reader grant offers it', (
    tester,
  ) async {
    await show(tester);

    expect(find.text('time.correction.answer'), findsNWidgets(2));
    expect(find.text('time.correction.grant'), findsOneWidget);
    // The reason rides the line under the name, after the days it is about.
    expect(
      find.textContaining('time.correction.reason.MAX_DAYS_BACK'),
      findsOneWidget,
    );
    expect(
      find.textContaining('time.correction.reason.APPROVAL'),
      findsOneWidget,
    );
  });

  testWidgets('opening the days needs no reason', (tester) async {
    final repository = await show(tester);

    await tester.tap(find.text('time.correction.grant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('time.correction.grantSend'));
    await tester.pumpAndSettle();

    expect(repository.granted, [('r1', '')]);
  });

  testWidgets('opening the days sends the reason and shows it in place', (
    tester,
  ) async {
    final repository = await show(tester);

    await tester.tap(find.text('time.correction.grant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Passt, bitte nachtragen.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('time.correction.grantSend'));
    await tester.pumpAndSettle();

    expect(repository.granted, [('r1', 'Passt, bitte nachtragen.')]);
    expect(repository.answered, isEmpty);
    expect(find.text('time.correction.grantedBy'), findsOneWidget);
    expect(find.text('Passt, bitte nachtragen.'), findsOneWidget);
    expect(find.text('time.correction.grant'), findsNothing);
    // In place: the list was not read again to show it.
    expect(repository.pages, 1);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('an answer without opening anything reads as an answer', (
    tester,
  ) async {
    final repository = await show(tester);

    await tester.tap(find.text('time.correction.answer').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ich öffne den Zeitraum.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('time.correction.answerSend'));
    await tester.pumpAndSettle();

    expect(repository.answered, [('r2', 'Ich öffne den Zeitraum.')]);
    expect(find.text('time.correction.answeredBy'), findsOneWidget);
    expect(find.text('time.correction.grantedBy'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}

class _FakeTimeRepository implements TimeRepository {
  _FakeTimeRepository(this.requests);

  final List<TimeCorrectionRequest> requests;
  final List<(String, String)> granted = [];
  final List<(String, String)> answered = [];
  int pages = 0;

  @override
  Future<PageResult<TimeCorrectionRequest>> correctionRequests({
    int page = 0,
    int size = 25,
  }) async {
    pages++;
    return (items: requests, total: requests.length);
  }

  @override
  Future<TimeCorrectionRequest> grantCorrection(String id, String note) async {
    granted.add((id, note));
    return _answered(id, note, granted: true);
  }

  @override
  Future<TimeCorrectionRequest> answerCorrection(String id, String note) async {
    answered.add((id, note));
    return _answered(id, note, granted: false);
  }

  TimeCorrectionRequest _answered(
    String id,
    String note, {
    required bool granted,
  }) {
    final request = requests.firstWhere((r) => r.id == id);
    return TimeCorrectionRequest(
      id: request.id,
      kind: request.kind,
      entryId: request.entryId,
      date: request.date,
      from: request.from,
      to: request.to,
      projectId: request.projectId,
      reason: request.reason,
      note: request.note,
      requesterId: request.requesterId,
      requesterLabel: request.requesterLabel,
      at: request.at,
      answer: TimeCorrectionAnswer(
        note: note,
        byLabel: 'Admin',
        at: DateTime.utc(2026, 9, 13),
        granted: granted,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  const _FakeProjectRepository();

  @override
  Future<List<Project>> resolveProjects(List<String> ids) async => [
    for (final id in ids) Project(id: id, key: 'HIN', name: 'Hinata'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
