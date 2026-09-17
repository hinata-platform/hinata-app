import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/features/absences/absence_entitlement_sheets.dart';

/// The journal sheet, and the one thing about it that has gone wrong before.
///
/// A sheet is `Column(min)` inside a box that caps it at most of the screen. A
/// `Flexible` child is handed that whole height as its maximum, and an empty
/// state is a `Center` — which has no height factor, so it takes every point it
/// is offered. The sheet then opens the size of the display with two lines of
/// text floating in the middle.
///
/// Only the list gets the `Flexible`; the spinner and the empty state are
/// ordinary children and size to themselves. This test measures that, because
/// nothing else does: the layout is not wrong, only enormous, so it throws no
/// overflow and renders every widget the other tests look for.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  /// A tall window, so a sheet that grabs the height has room to be wrong in.
  const window = Size(1200, 1400);

  Future<void> open(WidgetTester tester, _FakeAbsences repository) async {
    // The *view*, not a MediaQuery widget: the sheet is pushed on the root
    // navigator and reads the window, so a MediaQuery wrapped around the page
    // never reaches it — and the test would measure a modal sized for the
    // 800x600 default while believing it had given it room to misbehave.
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: window),
        child: MaterialApp(
          home: RepositoryProvider<AbsenceRepository>.value(
            value: repository,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showAbsenceLedgerSheet(
                      context,
                      userId: 'u-1',
                      name: 'Mei Lin',
                      typeId: 't-vacation',
                      year: 2026,
                    ),
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

  testWidgets('an empty journal is the size of its own sentence', (
    tester,
  ) async {
    await open(tester, _FakeAbsences());

    expect(find.text('absence.entitlements.ledgerEmpty'), findsOneWidget);

    // Generous, because the point is the order of magnitude: the empty state is
    // a heading, a line of prose and a mark, which is a couple of hundred
    // points. Grabbing the sheet's whole allowance would be four figures.
    final empty = tester.getSize(find.byType(HiveEmptyState));
    expect(
      empty.height,
      lessThan(window.height / 3),
      reason:
          'the empty journal grew to fill the sheet — a Center inside a '
          'Flexible takes every point it is offered',
    );
  });

  testWidgets('a journal with rows in it scrolls instead of growing', (
    tester,
  ) async {
    await open(tester, _FakeAbsences(entries: _manyEntries()));

    // Forty rows are taller than any sheet, so this one has to scroll — which
    // is exactly what the Flexible is for, and why the empty state must not
    // have it.
    expect(find.byType(ListView), findsOneWidget);
    final list = tester.getSize(find.byType(ListView));
    expect(list.height, lessThan(window.height));
  });
}

List<AbsenceLedgerEntry> _manyEntries() => [
  for (var i = 0; i < 40; i++)
    AbsenceLedgerEntry(
      id: 'e-$i',
      typeId: 't-vacation',
      year: 2026,
      kind: AbsenceLedgerKind.adjustment,
      milliDays: kMilliDay,
      effectiveOn: DateTime.utc(2026, 1, 1 + (i % 28)),
      reason: 'Korrektur $i',
    ),
];

class _FakeAbsences implements AbsenceRepository {
  _FakeAbsences({this.entries = const []});

  final List<AbsenceLedgerEntry> entries;

  @override
  Future<PageResult<AbsenceLedgerEntry>> ledger({
    required String userId,
    required String typeId,
    required int year,
    int page = 0,
    int size = 50,
  }) async => (items: entries, total: entries.length);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
