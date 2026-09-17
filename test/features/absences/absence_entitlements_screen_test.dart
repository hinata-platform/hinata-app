import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/absences/absence_entitlements_screen.dart';

/// Admin → Entitlements (HIN-116): a page of the directory beside where each
/// person stands for one type and year.
///
/// What is tested is what the page decides, not how it looks: only types with
/// something to grant are offered, a row that was never granted says so instead
/// of showing four zeros, and nothing is granted to nobody.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> pump(WidgetTester tester, _FakeAbsences repository) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 1600)),
        child: MaterialApp(
          // A Scaffold, because the app shell is one: the page is mounted
          // inside it and its controls want the Material under them.
          home: Scaffold(
            body: MultiRepositoryProvider(
              providers: [
                RepositoryProvider<AbsenceRepository>.value(value: repository),
                RepositoryProvider<UserRepository>.value(value: _FakeUsers()),
              ],
              child: const AbsenceEntitlementsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a type with no quota is not a type to grant', (tester) async {
    await pump(
      tester,
      _FakeAbsences(
        types: const [
          // Sickness is unlimited and counts against nothing: there is no year
          // to hand out, so the page must not offer it as one.
          AbsenceType(
            id: 't-sick',
            key: 'sick',
            kind: AbsenceKind.sick,
            systemKey: 'sick',
            unlimited: true,
          ),
        ],
      ),
    );

    expect(find.text('absence.entitlements.noTypes'), findsOneWidget);
  });

  testWidgets('a row nobody was granted says so rather than showing zeros', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeAbsences(
        types: [_vacation],
        standings: const [AbsenceStanding(userId: 'u-1')],
      ),
    );

    expect(find.text('Nina Keeper'), findsOneWidget);
    expect(find.text('absence.entitlements.notGranted'), findsOneWidget);
    expect(find.text('absence.entitlements.remaining'), findsNothing);
  });

  testWidgets('a granted row shows the four figures', (tester) async {
    await pump(
      tester,
      _FakeAbsences(
        types: [_vacation],
        standings: const [
          AbsenceStanding(
            userId: 'u-1',
            granted: true,
            accruedMilliDays: 20 * kMilliDay,
            takenMilliDays: 5 * kMilliDay,
            plannedMilliDays: 2 * kMilliDay,
            remainingMilliDays: 13 * kMilliDay,
          ),
        ],
      ),
    );

    expect(find.text('absence.entitlements.entitled'), findsOneWidget);
    expect(find.text('absence.entitlements.taken'), findsOneWidget);
    expect(find.text('absence.entitlements.planned'), findsOneWidget);
    expect(find.text('absence.entitlements.remaining'), findsOneWidget);
  });

  testWidgets('the bulk grant appears only once somebody is chosen', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeAbsences(
        types: [_vacation],
        standings: const [AbsenceStanding(userId: 'u-1')],
      ),
    );

    expect(find.text('absence.entitlements.peopleChosen'), findsNothing);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('absence.entitlements.peopleChosen'), findsOneWidget);
  });

  testWidgets('nobody found is a sentence and a way out of it', (tester) async {
    await pump(tester, _FakeAbsences(types: [_vacation]));

    expect(find.text('absence.entitlements.empty'), findsOneWidget);
  });
}

const _vacation = AbsenceType(
  id: 't-vacation',
  key: 'vacation',
  kind: AbsenceKind.vacation,
  systemKey: 'vacation',
  countsAgainstBalance: true,
  allowanceMilliDays: 20 * kMilliDay,
  icon: 'palmtree',
);

class _FakeAbsences implements AbsenceRepository {
  _FakeAbsences({required List<AbsenceType> types, this.standings = const []})
    : _types = types;

  final List<AbsenceType> _types;
  final List<AbsenceStanding> standings;

  @override
  Future<List<AbsenceType>> types({bool includeInactive = false}) async =>
      _types;

  @override
  Future<PageResult<AbsenceStanding>> overview({
    required String typeId,
    required int year,
    String query = '',
    int page = 0,
    int size = 25,
  }) async => (items: standings, total: standings.length);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUsers implements UserRepository {
  @override
  Future<List<DirectoryUser>> usersByIds(List<String> ids) async => [
    for (final id in ids)
      if (id == 'u-1')
        const DirectoryUser(
          id: 'u-1',
          username: 'nina',
          displayName: 'Nina Keeper',
        ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
