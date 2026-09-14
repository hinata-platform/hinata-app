/// Logging and correcting time on an issue opens the time module's own editor
/// while the module is on. With it off the module's routes do not exist, and
/// the issue keeps its work log.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/issues/work_items_section.dart';

import '../time/fake_time_policy_cubit.dart';

const _issue = Issue(
  id: 'i1',
  projectId: 'p1',
  readableId: 'MOB-1',
  title: 'Fix the login screen',
  state: 'OPEN',
);

void main() {
  Future<void> open(
    WidgetTester tester, {
    required bool module,
    required Future<Object?> Function(BuildContext context) action,
  }) async {
    tester.view
      ..physicalSize = const Size(900, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final time = _FakeTimeRepository();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IssueRepository>.value(
            value: _FakeIssueRepository(),
          ),
          RepositoryProvider<ProjectRepository>.value(
            value: _FakeProjectRepository(),
          ),
          RepositoryProvider<TimeRepository>.value(value: time),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AppConfigBloc>.value(
              value: _StubAppConfig(module: module),
            ),
            BlocProvider<TimePolicyCubit>.value(
              value: FakeTimePolicyCubit(TimePolicySnapshot.none, time),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => action(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('logging time opens the time editor, filed on the issue', (
    tester,
  ) async {
    await open(
      tester,
      module: true,
      action: (context) => showLogWork(context, _issue),
    );

    expect(find.text('time.entry.new'), findsOneWidget);
    expect(find.text('MOB-1 · Fix the login screen'), findsOneWidget);
    expect(find.text('issues.logTime'), findsNothing);
  });

  testWidgets('correcting an entry opens the same editor', (tester) async {
    await open(
      tester,
      module: true,
      action: (context) => showEditWorkItem(
        context,
        _issue.id,
        WorkItem(
          id: 'w1',
          userId: 'u1',
          durationMinutes: 45,
          activityType: 'Development',
          date: DateTime.now(),
          description: 'Demo tracked work',
        ),
      ),
    );

    expect(find.text('time.entry.edit'), findsOneWidget);
    expect(find.text('time.editEntry'), findsNothing);
  });

  testWidgets('without the module the issue keeps its work log', (
    tester,
  ) async {
    // The editor would save to routes this server does not have.
    await open(
      tester,
      module: false,
      action: (context) => showLogWork(context, _issue),
    );

    expect(find.text('issues.logTime'), findsOneWidget);
    expect(find.text('time.entry.new'), findsNothing);
  });
}

/// An [AppConfigBloc] that is only ever asked for its state.
class _StubAppConfig extends AppConfigBloc {
  _StubAppConfig({required bool module})
    : super(repository: _UnusedMetaRepository(), storage: _UnusedStorage()) {
    emit(
      AppConfigState(
        status: AppConfigStatus.ready,
        meta: ServerMeta(
          serverVersion: '2.1.0',
          minAppVersion: '0.0.0',
          setupCompleted: true,
          featureFlags: {PlatformFlags.advancedTimeTracking: module},
        ),
      ),
    );
  }
}

class _UnusedMetaRepository implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeTimeRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<List<Project>> resolveProjects(List<String> ids) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeIssueRepository implements IssueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
