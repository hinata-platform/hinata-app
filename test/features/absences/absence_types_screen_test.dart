import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/absences/absence_types_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Admin → Absence types (HIN-116): the catalogue a keeper keeps.
///
/// Three things here are decisions, not layout. A built-in ships without a name
/// and is labelled from the reader's language, so a German instance does not
/// read "Vacation". A built-in cannot be deleted, so it does not offer a button
/// that only ever refuses. And a retired type is out of the way without being
/// gone, because the balances under it still are.
///
/// Widget tests render raw i18n keys, so nothing here asserts on prose.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> pump(WidgetTester tester, _FakeAbsences repository) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1100, 1400)),
        child: MaterialApp(
          home: RepositoryProvider<AbsenceRepository>.value(
            value: repository,
            child: const AbsenceTypesScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a built-in is named by the language, not by the document', (
    tester,
  ) async {
    await pump(tester, _FakeAbsences(types: [_vacation()]));

    expect(find.text('absence.type.vacation'), findsOneWidget);
    expect(find.text('absence.types.system'), findsOneWidget);
  });

  testWidgets('a built-in offers no way to delete it', (tester) async {
    await pump(tester, _FakeAbsences(types: [_vacation()]));

    // Editing yes, deleting no: entitlements and bookings point at it by id.
    expect(find.byIcon(LucideIcons.pencil), findsOneWidget);
    expect(find.byIcon(LucideIcons.trash2), findsNothing);
  });

  testWidgets('a type somebody added can be deleted', (tester) async {
    await pump(
      tester,
      _FakeAbsences(
        types: [
          _vacation(),
          _own(name: 'Fortbildung'),
        ],
      ),
    );

    expect(find.text('Fortbildung'), findsOneWidget);
    expect(find.byIcon(LucideIcons.trash2), findsOneWidget);
  });

  testWidgets('a retired type is out of the way until it is asked for', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeAbsences(
        types: [
          _vacation(),
          _own(name: 'Sabbatical', active: false),
        ],
      ),
    );

    expect(find.text('Sabbatical'), findsNothing);
    expect(find.text('absence.types.showInactive'), findsOneWidget);

    await tester.tap(find.byType(HiveSwitch));
    await tester.pumpAndSettle();

    expect(find.text('Sabbatical'), findsOneWidget);
    expect(find.text('absence.types.inactive'), findsOneWidget);
  });

  testWidgets('with nothing retired there is nothing to reveal', (
    tester,
  ) async {
    await pump(tester, _FakeAbsences(types: [_vacation()]));

    expect(find.text('absence.types.showInactive'), findsNothing);
  });

  testWidgets('an empty catalogue is a sentence and a way out of it', (
    tester,
  ) async {
    await pump(tester, _FakeAbsences(types: const []));

    expect(find.text('absence.types.empty'), findsOneWidget);
    expect(find.text('absence.types.new'), findsWidgets);
  });
}

AbsenceType _vacation() => const AbsenceType(
  id: 't-vacation',
  key: 'vacation',
  kind: AbsenceKind.vacation,
  systemKey: 'vacation',
  countsAgainstBalance: true,
  allowanceMilliDays: 20 * kMilliDay,
  icon: 'palmtree',
);

AbsenceType _own({required String name, bool active = true}) => AbsenceType(
  id: 't-$name',
  key: name.toLowerCase(),
  kind: AbsenceKind.training,
  name: name,
  countsAgainstBalance: true,
  allowanceMilliDays: 5 * kMilliDay,
  active: active,
);

/// A catalogue that answers with one fixed list.
///
/// Implemented rather than extended: the screen asks it one question, and a
/// real repository would want an ApiClient this test has no use for.
class _FakeAbsences implements AbsenceRepository {
  _FakeAbsences({required List<AbsenceType> types}) : _types = types;

  final List<AbsenceType> _types;

  @override
  Future<List<AbsenceType>> types({bool includeInactive = false}) async =>
      _types;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
