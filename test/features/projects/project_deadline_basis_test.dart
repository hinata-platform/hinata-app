import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/features/projects/project_create_form.dart';

/// The deadline basis of a new project (HIN-129): offered only while project
/// templates are on, preselected on the organisation's default, and sent only
/// when somebody picked one. The server refuses the field with 400 while the
/// module is off, so "not sent" is the behaviour that matters most.
void main() {
  group('ProjectDraft', () {
    test('shows the organisation default until something is picked', () {
      final draft = ProjectDraft(
        takenKeys: const {},
        deadlineDefault: RelativeDateBasis.working,
      );
      addTearDown(draft.dispose);

      expect(draft.shownDeadlineBasis, RelativeDateBasis.working);
      // Untouched, the project follows the organisation.
      expect(draft.deadlineBasisToSend, isNull);

      draft.setDeadlineBasis(RelativeDateBasis.calendar);
      expect(draft.shownDeadlineBasis, RelativeDateBasis.calendar);
      expect(draft.deadlineBasisToSend, RelativeDateBasis.calendar);
    });

    test('never sends a basis while templates are off', () {
      final draft = ProjectDraft(takenKeys: const {});
      addTearDown(draft.dispose);

      draft.setDeadlineBasis(RelativeDateBasis.working);
      expect(draft.deadlineBasisToSend, isNull);
    });
  });

  group('ProjectCreateFields', () {
    Widget host(ProjectDraft draft) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepositoryProvider<UserRepository>.value(
        value: _FakeUsers(),
        child: Scaffold(
          body: SingleChildScrollView(
            child: ProjectCreateFields(draft: draft, autofocus: false),
          ),
        ),
      ),
    );

    testWidgets('offers the switch on the organisation default', (
      tester,
    ) async {
      final draft = ProjectDraft(
        takenKeys: const {},
        deadlineDefault: RelativeDateBasis.working,
      );
      addTearDown(draft.dispose);
      await tester.pumpWidget(host(draft));
      await tester.pump();

      expect(find.text('projects.deadlineBasis.label'), findsOneWidget);
      expect(find.text('projects.deadlineBasis.orgDefault'), findsOneWidget);
      expect(find.text('projects.deadlineBasis.hint'), findsOneWidget);
      final working = tester.widget<GlassSwitchChip>(
        find.widgetWithText(GlassSwitchChip, 'projects.deadlineBasis.working'),
      );
      expect(working.active, isTrue);

      await tester.ensureVisible(find.text('projects.deadlineBasis.calendar'));
      await tester.tap(find.text('projects.deadlineBasis.calendar'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(draft.deadlineBasisToSend, RelativeDateBasis.calendar);
    });

    testWidgets('has no switch while templates are off', (tester) async {
      final draft = ProjectDraft(takenKeys: const {});
      addTearDown(draft.dispose);
      await tester.pumpWidget(host(draft));
      await tester.pump();

      expect(find.text('projects.deadlineBasis.label'), findsNothing);
    });
  });

  group('ProjectRepository', () {
    late _RecordingApi api;
    late ProjectRepository repo;

    setUp(() {
      api = _RecordingApi();
      repo = ProjectRepository(api);
    });

    test('create leaves the basis out unless one is given', () async {
      await repo.createProject(key: 'FEST', name: 'Sommerfest');
      expect(api.bodies.single.containsKey('deadlineBasis'), isFalse);

      await repo.createProject(
        key: 'FEST',
        name: 'Sommerfest',
        deadlineBasis: RelativeDateBasis.working,
      );
      expect(api.bodies.last['deadlineBasis'], 'WORKING');
    });

    test('copy and instantiate send the basis only when given', () async {
      await repo.copyProject('p1', name: 'Copy');
      expect(api.bodies.last.containsKey('deadlineBasis'), isFalse);

      await repo.copyProject(
        'p1',
        name: 'Copy',
        deadlineBasis: RelativeDateBasis.calendar,
      );
      expect(api.bodies.last['deadlineBasis'], 'CALENDAR');

      await repo.instantiateTemplate('p1', name: 'From template');
      expect(api.bodies.last.containsKey('deadlineBasis'), isFalse);

      await repo.instantiateTemplate(
        'p1',
        name: 'From template',
        deadlineBasis: RelativeDateBasis.working,
      );
      expect(api.bodies.last['deadlineBasis'], 'WORKING');
    });
  });
}

class _FakeUsers implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Records each POST body and answers with just enough of a project for the
/// repository to parse.
class _RecordingApi implements ApiClient {
  final List<Map<String, dynamic>> bodies = [];

  static const _project = {'id': 'p2', 'key': 'FEST', 'name': 'Sommerfest'};

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    bodies.add(Map<String, dynamic>.from(body! as Map));
    if (path.endsWith('/copy') || path.endsWith('/instantiate')) {
      return {'project': _project};
    }
    return _project;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
