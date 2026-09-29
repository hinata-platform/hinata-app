import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/project_template_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/features/projects/project_copy_sheet.dart';

/// The copy sheet: what it shows, what it sends, and what it does with a
/// refusal.
///
/// The numbers under the switches are the point of the scope request — they sit
/// next to decisions somebody is making, so they come from the server and not
/// from whatever the app happens to have loaded. And a refusal has to stay in
/// the sheet with the form still filled in: retyping a form to read the reason
/// for a refusal is the worst possible way to learn it.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  late _FakeProjectRepository repo;

  setUp(() => repo = _FakeProjectRepository());

  Project source({
    bool template = false,
    DateTime? eventDate,
    RelativeDateBasis? deadlineBasis,
  }) => Project(
    id: 'p1',
    key: 'BFQ',
    name: 'Beers 4 Queers',
    template: template,
    eventDate: eventDate,
    deadlineBasis: deadlineBasis,
  );

  /// [config] null hosts the sheet without any [AppConfigBloc], the way the
  /// older cases here do: the sheet then offers no deadline basis.
  Widget host({
    required Project project,
    ProjectCopyMode mode = ProjectCopyMode.copy,
    void Function(ProjectCopyResult?)? onResult,
    double width = 900,
    AppConfigBloc? config,
  }) {
    final sheet = RepositoryProvider<ProjectRepository>.value(
      value: repo,
      child: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: ElevatedButton(
                onPressed: () async {
                  final result = await showProjectCopySheet(
                    context,
                    source: project,
                    mode: mode,
                  );
                  onResult?.call(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: config == null
          ? sheet
          : BlocProvider<AppConfigBloc>.value(value: config, child: sheet),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the counts and the suggested key come from the server', (
    tester,
  ) async {
    repo.scope = const ProjectCopyScope(
      issues: 34,
      subtasks: 11,
      attachments: 3,
      attachmentBytes: 12 * 1024 * 1024,
      suggestedKey: 'BFQ2',
    );
    await tester.pumpWidget(host(project: source()));
    await open(tester);

    expect(repo.scopedFor, 'p1');
    expect(find.text('projects.copy.scope'), findsOneWidget);
    // The key field starts on the free key the server named, so nobody has to
    // guess one the server will refuse.
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      'BFQ2',
    );
  });

  testWidgets('a project above the limit says so and cannot be copied', (
    tester,
  ) async {
    repo.scope = const ProjectCopyScope(issues: 900, withinLimit: false);
    await tester.pumpWidget(host(project: source()));
    await open(tester);

    expect(find.text('projects.copy.tooLarge'), findsOneWidget);
    // The confirm button is there and does nothing: the sheet refuses before
    // the server has to.
    await tester.tap(find.text('projects.copy.confirm'));
    await tester.pumpAndSettle();
    expect(repo.copies, isEmpty);
  });

  testWidgets('copying sends the switches as they stand', (tester) async {
    repo.scope = const ProjectCopyScope(issues: 4, suggestedKey: 'BFQ2');
    await tester.pumpWidget(host(project: source()));
    await open(tester);

    await tester.enterText(find.byType(TextField).first, 'Beers 27');
    await tester.pumpAndSettle();
    await tester.tap(find.text('projects.copy.confirm'));
    await tester.pumpAndSettle();

    expect(repo.copies, hasLength(1));
    final sent = repo.copies.single;
    expect(sent.name, 'Beers 27');
    expect(sent.key, 'BFQ2');
    // Members and time settings default on, attachments and the board off:
    // the first two say who works on the plan and how its hours are counted,
    // the other two are bulk a copy usually does not want.
    expect(sent.includeMembers, isTrue);
    expect(sent.includeTimeSettings, isTrue);
    expect(sent.includeAttachments, isFalse);
    expect(sent.includeBoard, isFalse);
  });

  testWidgets('from a template it instantiates instead, with no switches', (
    tester,
  ) async {
    repo.scope = const ProjectCopyScope(issues: 8, suggestedKey: 'TPL2');
    await tester.pumpWidget(
      host(project: source(template: true), mode: ProjectCopyMode.instantiate),
    );
    await open(tester);

    // The scope is decided on this way in, so the switches are not offered.
    expect(find.text('projects.copy.include'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Beers SoSe 27');
    await tester.pumpAndSettle();
    await tester.tap(find.text('projects.copy.create'));
    await tester.pumpAndSettle();

    expect(repo.copies, isEmpty);
    expect(repo.instantiations, hasLength(1));
    expect(repo.instantiations.single.name, 'Beers SoSe 27');
  });

  testWidgets('a refusal stays in the sheet with the form intact', (
    tester,
  ) async {
    repo.scope = const ProjectCopyScope(issues: 4, suggestedKey: 'BFQ2');
    repo.failCopyWith = 'This project has 900 issues; a copy takes at most 500';
    ProjectCopyResult? result;
    await tester.pumpWidget(
      host(project: source(), onResult: (r) => result = r),
    );
    await open(tester);

    await tester.enterText(find.byType(TextField).first, 'Beers 27');
    await tester.pumpAndSettle();
    await tester.tap(find.text('projects.copy.confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('900 issues'), findsOneWidget);
    // Still open, still filled in, nothing returned.
    expect(find.text('projects.copy.confirm'), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('with no files of its own the attachment switch is off limits', (
    tester,
  ) async {
    repo.scope = const ProjectCopyScope(issues: 4, attachments: 0);
    await tester.pumpWidget(host(project: source()));
    await open(tester);

    expect(find.text('projects.copy.attachmentsDetail'), findsNothing);
  });

  for (final width in <double>[360, 700, 1200]) {
    testWidgets('lays out without overflow at ${width}px', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      repo.scope = const ProjectCopyScope(
        issues: 34,
        subtasks: 11,
        attachments: 3,
        attachmentBytes: 12 * 1024 * 1024,
        suggestedKey: 'BFQ2',
      );

      await tester.pumpWidget(host(project: source(), width: width));
      await open(tester);

      expect(tester.takeException(), isNull);
    });
  }

  group('deadline basis', () {
    testWidgets('is neither shown nor sent while templates are off', (
      tester,
    ) async {
      repo.scope = const ProjectCopyScope(issues: 4, suggestedKey: 'BFQ2');
      await tester.pumpWidget(
        host(
          project: source(),
          config: _FakeAppConfig(templates: false, basis: 'WORKING'),
        ),
      );
      await open(tester);

      expect(find.text('projects.deadlineBasis.label'), findsNothing);
      await tester.tap(find.text('projects.copy.confirm'));
      await tester.pumpAndSettle();
      expect(repo.copies.single.deadlineBasis, isNull);
    });

    testWidgets('shows the source\'s effective basis and the org default', (
      tester,
    ) async {
      repo.scope = const ProjectCopyScope(issues: 4, suggestedKey: 'BFQ2');
      await tester.pumpWidget(
        host(
          project: source(),
          config: _FakeAppConfig(templates: true, basis: 'WORKING'),
        ),
      );
      await open(tester);

      expect(find.text('projects.deadlineBasis.label'), findsOneWidget);
      expect(find.text('projects.deadlineBasis.orgDefault'), findsOneWidget);
      // The source follows the organisation, so working days are on and the
      // chip for them is the inert one.
      final working = tester.widget<GlassSwitchChip>(
        find.widgetWithText(GlassSwitchChip, 'projects.deadlineBasis.working'),
      );
      expect(working.active, isTrue);

      // Untouched, nothing is sent: the copy keeps the source's own setting,
      // which here is "follow the organisation".
      await tester.tap(find.text('projects.copy.confirm'));
      await tester.pumpAndSettle();
      expect(repo.copies.single.deadlineBasis, isNull);
    });

    testWidgets('a picked basis is sent', (tester) async {
      repo.scope = const ProjectCopyScope(issues: 4, suggestedKey: 'BFQ2');
      await tester.pumpWidget(
        host(
          project: source(),
          config: _FakeAppConfig(templates: true, basis: 'CALENDAR'),
        ),
      );
      await open(tester);

      await tester.ensureVisible(find.text('projects.deadlineBasis.working'));
      await tester.tap(find.text('projects.deadlineBasis.working'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('projects.copy.confirm'));
      await tester.pumpAndSettle();

      expect(repo.copies.single.deadlineBasis, RelativeDateBasis.working);
    });

    testWidgets('instantiating sends the picked basis too', (tester) async {
      repo.scope = const ProjectCopyScope(issues: 8, suggestedKey: 'TPL2');
      await tester.pumpWidget(
        host(
          project: source(
            template: true,
            deadlineBasis: RelativeDateBasis.working,
          ),
          mode: ProjectCopyMode.instantiate,
          config: _FakeAppConfig(templates: true, basis: 'CALENDAR'),
        ),
      );
      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'Beers SoSe 27');
      await tester.ensureVisible(find.text('projects.deadlineBasis.calendar'));
      await tester.tap(find.text('projects.deadlineBasis.calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('projects.copy.create'));
      await tester.pumpAndSettle();

      expect(
        repo.instantiations.single.deadlineBasis,
        RelativeDateBasis.calendar,
      );
    });
  });

  testWidgets('a template is the same copy with one flag set', (tester) async {
    // The way in from the Templates tab. The project it is made from keeps
    // running — that is the whole difference from the switch in its settings,
    // which moves the project itself onto the Templates list.
    await tester.pumpWidget(
      host(project: source(), mode: ProjectCopyMode.template),
    );
    await open(tester);

    expect(find.text('projects.copy.makeTemplate'), findsOneWidget);
    expect(find.text('projects.copy.makeTemplateConfirm'), findsOneWidget);

    await tester.tap(find.text('projects.copy.makeTemplateConfirm'));
    await tester.pumpAndSettle();

    expect(repo.copies, hasLength(1));
    expect(repo.copies.single.asTemplate, isTrue);
  });
}

/// What the sheet asked for, in the order it asked.
typedef _CopyCall = ({
  String? name,
  String? key,
  DateTime? eventDate,
  bool includeMembers,
  bool includeAttachments,
  bool includeTimeSettings,
  bool includeBoard,
  bool asTemplate,
  RelativeDateBasis? deadlineBasis,
});

typedef _InstantiateCall = ({
  String name,
  String? key,
  DateTime? eventDate,
  RelativeDateBasis? deadlineBasis,
});

class _FakeProjectRepository implements ProjectRepository {
  ProjectCopyScope scope = const ProjectCopyScope();
  String? scopedFor;
  String? failCopyWith;
  final List<_CopyCall> copies = [];
  final List<_InstantiateCall> instantiations = [];

  @override
  Future<ProjectCopyScope> scopeOfCopy(String id) async {
    scopedFor = id;
    return scope;
  }

  @override
  Future<ProjectCopyResult> copyProject(
    String id, {
    String? name,
    String? key,
    DateTime? eventDate,
    bool includeMembers = true,
    bool includeAttachments = false,
    bool includeTimeSettings = true,
    bool includeBoard = false,
    bool asTemplate = false,
    RelativeDateBasis? deadlineBasis,
  }) async {
    if (failCopyWith != null) {
      throw ApiFailure(failCopyWith!, statusCode: 400);
    }
    copies.add((
      name: name,
      key: key,
      eventDate: eventDate,
      includeMembers: includeMembers,
      includeAttachments: includeAttachments,
      includeTimeSettings: includeTimeSettings,
      includeBoard: includeBoard,
      asTemplate: asTemplate,
      deadlineBasis: deadlineBasis,
    ));
    return ProjectCopyResult(
      project: Project(id: 'p2', key: key ?? 'X', name: name ?? 'copy'),
      issuesCopied: 4,
    );
  }

  @override
  Future<ProjectCopyResult> instantiateTemplate(
    String id, {
    required String name,
    String? key,
    DateTime? eventDate,
    RelativeDateBasis? deadlineBasis,
  }) async {
    instantiations.add((
      name: name,
      key: key,
      eventDate: eventDate,
      deadlineBasis: deadlineBasis,
    ));
    return ProjectCopyResult(
      project: Project(id: 'p2', key: key ?? 'X', name: name),
      issuesCopied: 8,
      deadlinesSet: 8,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// An [AppConfigBloc] with one fixed answer, whether project templates are on
/// and what the organisation's deadline basis is.
class _FakeAppConfig extends AppConfigBloc {
  _FakeAppConfig({required bool templates, required String basis})
    : _fixed = AppConfigState(
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          featureFlags: {PlatformFlags.projectTemplates: templates},
          defaultDeadlineBasis: RelativeDateBasis.fromWire(basis),
        ),
      ),
      super(repository: _UnusedMeta(), storage: _UnusedStorage());

  final AppConfigState _fixed;

  @override
  AppConfigState get state => _fixed;
}

class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
