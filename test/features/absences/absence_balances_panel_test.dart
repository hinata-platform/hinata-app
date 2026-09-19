import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/my_absences_cubit.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/absences/absence_balances_panel.dart';

import 'absence_test_support.dart';

/// Settings → your absence balances (HIN-116).
///
/// Four things worth failing a build over. It is not there at all while the
/// module is off. "Not granted" and "nothing left" are different sentences,
/// because they are different situations. A quota under the statutory minimum
/// is said to the person it is about, not only to the operator who set it
/// (§ 3 BUrlG). And the way into the keeper's pages appears for a keeper, which
/// is not the same thing as an administrator.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> pump(
    WidgetTester tester,
    _FakeAbsences repository, {
    bool moduleOn = true,
  }) async {
    final config = FakeAppConfig(absenceManagement: moduleOn);
    // The panel takes the catalogue and "do I keep absences" from the module's
    // own state rather than asking again, so the fake holds what the fake
    // repository would have answered.
    final mine = FakeMyAbsencesCubit(
      managed: moduleOn,
      types: await repository.types(),
      keeper: await repository.isKeeper(),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1100, 1600)),
        child: MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<AppConfigBloc>.value(value: config),
                BlocProvider<MyAbsencesCubit>.value(value: mine),
              ],
              child: RepositoryProvider<AbsenceRepository>.value(
                value: repository,
                child: const SingleChildScrollView(
                  child: AbsenceBalancesPanel(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with the module off there is nothing on the page', (
    tester,
  ) async {
    final repository = _FakeAbsences();
    await pump(tester, repository, moduleOn: false);

    expect(find.text('absence.balances.title'), findsNothing);
    // And nothing was asked of a server whose routes do not exist for us.
    expect(repository.balancesAsked, 0);
  });

  testWidgets('a year nobody granted says so rather than showing a zero', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeAbsences(
        balances: [const AbsenceBalance(typeId: 't-vacation', year: 2026)],
      ),
    );

    expect(find.text('absence.balances.notGranted'), findsOneWidget);
    expect(find.text('absence.balances.notGrantedHint'), findsOneWidget);
  });

  testWidgets('a granted year shows what is left, out of what', (tester) async {
    await pump(
      tester,
      _FakeAbsences(
        balances: [
          const AbsenceBalance(
            typeId: 't-vacation',
            year: 2026,
            granted: true,
            accruedMilliDays: 20 * kMilliDay,
            takenMilliDays: 5 * kMilliDay,
            plannedMilliDays: 2 * kMilliDay,
            remainingMilliDays: 13 * kMilliDay,
          ),
        ],
      ),
    );

    // The one number somebody opened the page for, large and on its own.
    expect(find.text('13'), findsOneWidget);
    expect(find.text('absence.type.vacation'), findsOneWidget);
  });

  testWidgets('a quota under the statutory floor is said to the person', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeAbsences(
        balances: [
          const AbsenceBalance(
            typeId: 't-vacation',
            year: 2026,
            granted: true,
            accruedMilliDays: 18 * kMilliDay,
            remainingMilliDays: 18 * kMilliDay,
            belowLegalMinimum: true,
            legalMinimumMilliDays: 20 * kMilliDay,
          ),
        ],
      ),
    );

    expect(find.text('absence.balances.belowMinimum'), findsOneWidget);
  });

  testWidgets('a keeper is offered the way into the keeper pages', (
    tester,
  ) async {
    await pump(tester, _FakeAbsences(keeper: true));

    expect(find.text('absence.balances.manage'), findsOneWidget);
  });

  testWidgets('everybody else is not, and a keeper is not an administrator', (
    tester,
  ) async {
    await pump(tester, _FakeAbsences(keeper: false));

    expect(find.text('absence.balances.manage'), findsNothing);
  });

  testWidgets('the journal opens on a type that can have one', (tester) async {
    await pump(
      tester,
      _FakeAbsences(
        balances: const [
          // Sickness first in the catalogue, and unlimited: it has no balance at
          // all, so its journal is empty by construction. Opening on it would
          // show an empty state that can never fill.
          AbsenceBalance(typeId: 't-sick', year: 2026, unlimited: true),
          AbsenceBalance(typeId: 't-vacation', year: 2026),
        ],
      ),
    );

    // The header names the type the journal is of, and it is the one with a
    // quota rather than the one first in the catalogue.
    expect(
      find.text('absence.balances.journal  ·  absence.type.vacation'),
      findsOneWidget,
    );
  });

  testWidgets('no balances at all is a sentence, not a blank', (tester) async {
    await pump(tester, _FakeAbsences());

    expect(find.text('absence.balances.empty'), findsOneWidget);
  });
}

/// One person's standing, fixed, plus a count of what was asked for — the
/// module being off has to mean *no request*, not an empty answer.
class _FakeAbsences implements AbsenceRepository {
  _FakeAbsences({List<AbsenceBalance> balances = const [], this.keeper = false})
    : _balances = balances;

  final List<AbsenceBalance> _balances;
  final bool keeper;
  int balancesAsked = 0;

  @override
  Future<AbsenceBalances> balances({String? userId, int? year}) async {
    balancesAsked++;
    return AbsenceBalances(
      userId: 'me',
      year: year ?? 2026,
      workingDaysPerWeek: 5,
      balances: _balances,
    );
  }

  @override
  Future<List<AbsenceType>> types({bool includeInactive = false}) async =>
      const [
        AbsenceType(
          id: 't-sick',
          key: 'sick',
          kind: AbsenceKind.sick,
          systemKey: 'sick',
          unlimited: true,
          icon: 'thermometer',
        ),
        AbsenceType(
          id: 't-vacation',
          key: 'vacation',
          kind: AbsenceKind.vacation,
          systemKey: 'vacation',
          countsAgainstBalance: true,
          icon: 'palmtree',
        ),
      ];

  @override
  Future<bool> isKeeper() async => keeper;

  @override
  Future<PageResult<AbsenceLedgerEntry>> ledger({
    required String userId,
    required String typeId,
    required int year,
    int page = 0,
    int size = 50,
  }) async => (items: const <AbsenceLedgerEntry>[], total: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
