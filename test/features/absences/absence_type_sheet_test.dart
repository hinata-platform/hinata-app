import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/absences/absence_type_sheet.dart';

/// The absence-type editor (HIN-116).
///
/// The rules that are not preferences: a sick type is never subject to approval
/// (§ 5 EFZG, R11) — the switch is not off, it is not a question — and a type
/// without a quota has nothing to accrue, carry or count against, so switching
/// that on takes the quota fields with it rather than letting somebody save a
/// combination the server refuses.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> open(WidgetTester tester, AbsenceType? existing) async {
    final repository = _FakeAbsences();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1000, 1600)),
        child: MaterialApp(
          home: RepositoryProvider<AbsenceRepository>.value(
            value: repository,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () =>
                        showAbsenceTypeSheet(context, existing: existing),
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

  /// The switch on the row carrying [label].
  HiveSwitch switchFor(WidgetTester tester, String label) =>
      tester.widget<HiveSwitch>(
        find.descendant(
          // The closest Row: a SettingRow lays its text and its control out
          // side by side, so the nearest one is that row and not the column
          // holding half the form.
          of: find
              .ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate((widget) => widget is Row),
              )
              .first,
          matching: find.byType(HiveSwitch),
        ),
      );

  testWidgets('a sick type is not asked whether it needs approval', (
    tester,
  ) async {
    await open(tester, _type(kind: AbsenceKind.sick));

    // Off, and not a question: § 5 EFZG knows a duty to notify, not to ask.
    final approval = switchFor(tester, 'absence.types.approval');
    expect(approval.value, isFalse);
    expect(approval.onChanged, isNull);
    expect(find.text('absence.types.approvalSick'), findsOneWidget);
  });

  testWidgets('every other type is', (tester) async {
    await open(tester, _type(kind: AbsenceKind.vacation));

    expect(switchFor(tester, 'absence.types.approval').onChanged, isNotNull);
    expect(find.text('absence.types.approvalSick'), findsNothing);
  });

  testWidgets('a type without a quota takes its quota fields with it', (
    tester,
  ) async {
    await open(tester, _type(kind: AbsenceKind.vacation));

    // The quota is there while the type has one.
    expect(find.text('absence.types.allowance'), findsOneWidget);
    expect(find.text('absence.types.carryover'), findsOneWidget);

    final unlimited = find.byWidget(
      switchFor(tester, 'absence.types.unlimited'),
    );
    await tester.ensureVisible(unlimited);
    await tester.pumpAndSettle();
    await tester.tap(unlimited);
    await tester.pumpAndSettle();

    // And gone once it does not: an unlimited type has nothing to accrue to,
    // carry or count against, and the server refuses the combination outright.
    expect(find.text('absence.types.allowance'), findsNothing);
    expect(find.text('absence.types.carryover'), findsNothing);
    expect(switchFor(tester, 'absence.types.counts').onChanged, isNull);
  });

  testWidgets('a built-in keeps its key and its category', (tester) async {
    await open(
      tester,
      _type(kind: AbsenceKind.vacation, systemKey: 'vacation'),
    );

    // The key is what a year of history is attached to, so it is not offered
    // for editing at all — not even greyed out.
    expect(find.text('absence.types.key'), findsNothing);
    expect(find.text('absence.types.system'), findsOneWidget);
  });

  testWidgets('a new type is asked for a key', (tester) async {
    await open(tester, null);

    expect(find.text('absence.types.key'), findsOneWidget);
    expect(find.text('absence.types.new'), findsOneWidget);
  });
}

AbsenceType _type({required AbsenceKind kind, String? systemKey}) =>
    AbsenceType(
      id: 't-1',
      key: 'k',
      kind: kind,
      systemKey: systemKey,
      name: systemKey == null ? 'Eigene Art' : null,
      countsAgainstBalance: true,
      allowanceMilliDays: 20 * kMilliDay,
      accrual: AbsenceAccrual.annual,
    );

class _FakeAbsences implements AbsenceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
