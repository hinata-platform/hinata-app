import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/personal_access_token.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/account/account_cubit.dart';
import 'package:hinata/features/account/pat_section.dart';

import '../../support/recording_fake.dart';

/// Settings → Access tokens (HIN-164): the create sheet offers the shift
/// scopes only while shift planning is on; a token may still carry them.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  test('the shift scopes are known, and offered only with the module', () {
    expect(kPatScopes, containsAll(kShiftPatScopes));
    expect(patScopesFor(shiftPlanning: true), kPatScopes);
    final off = patScopesFor(shiftPlanning: false);
    expect(off, isNot(contains('shifts:read')));
    expect(off, isNot(contains('shifts:write')));
    expect(off, isNot(contains('shifts:plan')));
    expect(off, contains('worklog:write'));
    expect(patScopeKey('shifts:plan'), 'pat.scope.shifts_plan');
  });

  Future<void> openCreateSheet(
    WidgetTester tester, {
    required bool shiftPlanning,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final account = FakeAccountRepository()
      ..answer<List<PersonalAccessToken>>(#listPats, const []);
    final cubit = AccountCubit(account);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      BlocProvider<AppConfigBloc>.value(
        value: _FakeAppConfig(shiftPlanning: shiftPlanning),
        child: BlocProvider<AccountCubit>.value(
          value: cubit,
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: PatSection())),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('pat.createButton'));
    await tester.pumpAndSettle();
    expect(find.text('pat.create.title'), findsOneWidget);
  }

  testWidgets('with shift planning on the sheet offers the shift scopes', (
    tester,
  ) async {
    await openCreateSheet(tester, shiftPlanning: true);
    for (final scope in kShiftPatScopes) {
      expect(find.text(scope), findsWidgets, reason: scope);
    }
    expect(find.text('issues:read'), findsWidgets);
  });

  testWidgets('with shift planning off the sheet leaves them out', (
    tester,
  ) async {
    await openCreateSheet(tester, shiftPlanning: false);
    for (final scope in kShiftPatScopes) {
      expect(find.text(scope), findsNothing, reason: scope);
    }
    expect(find.text('issues:read'), findsWidgets);
  });
}

/// An [AppConfigBloc] with one fixed answer about the server, so the section
/// can ask for `shift_planning` the way every screen asks.
class _FakeAppConfig extends AppConfigBloc {
  _FakeAppConfig({required bool shiftPlanning})
    : _fixed = AppConfigState(
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          featureFlags: {
            PlatformFlags.mcp: true,
            PlatformFlags.shiftPlanning: shiftPlanning,
          },
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
