import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/team_absence_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/absences/team_absence_agenda.dart';
import 'package:hinata/features/absences/team_absence_calendar.dart';
import 'package:hinata/features/absences/away_today_list.dart';
import 'package:hinata/features/time/time_privacy_sheet.dart';

/// The team absence calendar (HIN-118): the band on a wide window, the weekly
/// agenda on a phone, the dashboard's list of who is away today, and the
/// section of the transparency panel that says who sees one's absences.
///
/// Widget tests render i18n keys, so the assertions name keys. What is worth
/// failing a build over: an entry the server sent without a type never grows
/// one here; a request always says it is one in words, not only as a hatch;
/// and the dashboard never lists more than five names.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  final from = DateTime(2026, 6, 1);
  final to = DateTime(2026, 6, 30);

  TeamAbsenceEntry typed(int first, int last, {bool requested = false}) =>
      TeamAbsenceEntry(
        from: DateTime(2026, 6, first),
        to: DateTime(2026, 6, last),
        requested: requested,
        typeId: 't-vacation',
        typeSystemKey: 'vacation',
        icon: 'palmtree',
        hue: 150,
      );

  TeamAbsenceEntry busy(int first, int last) => TeamAbsenceEntry(
    from: DateTime(2026, 6, first),
    to: DateTime(2026, 6, last),
  );

  final rows = [
    TeamAbsenceRow(userId: 'a', name: 'Amira', entries: [typed(1, 5)]),
    TeamAbsenceRow(userId: 'b', name: 'Ben', entries: [busy(8, 10)]),
    TeamAbsenceRow(
      userId: 'c',
      name: 'Chiara',
      entries: [typed(15, 19, requested: true)],
    ),
  ];

  Widget app(Widget child, {Size size = const Size(1200, 700)}) => MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(home: Scaffold(body: child)),
  );

  group('band', () {
    testWidgets('names people and says in words what each bar is', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        app(TeamAbsenceBand(from: from, to: to, rows: rows)),
      );
      await tester.pumpAndSettle();

      for (final name in ['Amira', 'Ben', 'Chiara']) {
        expect(find.text(name), findsOneWidget);
      }
      // The typed bar is labelled with its type, the busy one only as away.
      expect(find.text('absence.type.vacation'), findsWidgets);
      expect(find.text('absence.team.away'), findsOneWidget);
      // A request says so in its accessible label, not only with a hatch.
      expect(
        find.bySemanticsLabel(RegExp('Chiara.*absence.team.legend.requested')),
        findsOneWidget,
      );
    });

    testWidgets(
      'shows the capacity strip only when the reader plans the group',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          app(TeamAbsenceBand(from: from, to: to, rows: rows)),
        );
        await tester.pumpAndSettle();
        expect(find.text('ABSENCE.TEAM.CAPACITY'), findsNothing);

        final band = CapacityBand(
          resolution: CapacityResolution.day,
          people: 3,
          buckets: [
            CapacityBucket(
              from: from,
              to: from,
              scheduledMinutes: 1440,
              capacityMinutes: 960,
              away: 1,
            ),
          ],
        );
        await tester.pumpWidget(
          app(TeamAbsenceBand(from: from, to: to, rows: rows, capacity: band)),
        );
        await tester.pumpAndSettle();
        expect(find.text('ABSENCE.TEAM.CAPACITY'), findsOneWidget);
      },
    );

    test('a type the server did not send is never invented', () {
      final entry = busy(1, 1);
      expect(entry.typed, isFalse);
    });
  });

  group('agenda', () {
    testWidgets(
      'one block per week, a week without absences says everybody is here',
      (tester) async {
        tester.view.physicalSize = const Size(390, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          app(
            TeamAbsenceAgenda(from: from, to: to, rows: rows),
            size: const Size(390, 2400),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Amira'), findsOneWidget);
        expect(find.text('Ben'), findsOneWidget);
        expect(find.text('Chiara'), findsOneWidget);
        // 22–28 June and 29–30 June carry nobody.
        expect(find.text('absence.team.everybodyHere'), findsNWidgets(2));
        expect(
          find.textContaining('absence.team.legend.requested'),
          findsOneWidget,
        );
      },
    );

    testWidgets('writes the week\'s capacity out rather than drawing it only', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final band = CapacityBand(
        resolution: CapacityResolution.day,
        people: 3,
        buckets: [
          CapacityBucket(
            from: from,
            to: from,
            scheduledMinutes: 1440,
            capacityMinutes: 960,
          ),
        ],
      );

      await tester.pumpWidget(
        app(
          TeamAbsenceAgenda(from: from, to: to, rows: rows, capacity: band),
          size: const Size(390, 2400),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('absence.team.capacityWeek'), findsOneWidget);
    });
  });

  group('away today', () {
    testWidgets('lists at most five and says how many more', (tester) async {
      final seven = [
        for (var i = 0; i < 5; i++)
          TeamAbsenceRow(
            userId: 'u$i',
            name: 'Person $i',
            entries: [busy(1, 1)],
          ),
      ];
      await tester.pumpWidget(
        app(
          AwayTodayList(
            page: TeamAbsencePage(
              rows: seven,
              total: 8,
              level: AbsenceCalendarLevel.busyOnly,
            ),
          ),
        ),
      );

      expect(find.textContaining('Person '), findsNWidgets(5));
      expect(find.text('dashboard.awayMore'), findsOneWidget);
    });

    testWidgets('an empty day is said, not left blank', (tester) async {
      await tester.pumpWidget(
        app(
          const AwayTodayList(
            page: TeamAbsencePage(
              rows: [],
              total: 0,
              level: AbsenceCalendarLevel.type,
            ),
          ),
        ),
      );

      expect(find.text('dashboard.awayNone'), findsOneWidget);
    });
  });

  group('transparency panel', () {
    Future<void> panel(WidgetTester tester, AbsenceVisibility? absences) =>
        tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: TimeVisibilityPanel(
                visibility: TimeVisibility(absences: absences),
              ),
            ),
          ),
        );

    testWidgets('says nothing about absences while the module is off', (
      tester,
    ) async {
      await panel(tester, null);
      expect(find.text('time.privacy.absence.heading'), findsNothing);
    });

    for (final level in AbsenceCalendarLevel.values) {
      testWidgets('names the calendar level ${level.name} in force', (
        tester,
      ) async {
        await panel(
          tester,
          AbsenceVisibility(calendar: level, keepersNamed: true),
        );
        expect(find.text('time.privacy.absence.heading'), findsOneWidget);
        expect(
          find.text('time.privacy.absence.calendar.${level.name}'),
          findsOneWidget,
        );
        expect(find.text('time.privacy.absence.keepersNamed'), findsOneWidget);
        expect(find.text('time.privacy.absence.leadsDoNot'), findsOneWidget);
      });
    }
  });

  group('wire', () {
    test(
      'a calendar page reads its rows, its level and whether it was cut',
      () {
        final page = TeamAbsencePage.fromJson(const {
          'content': [
            {
              'userId': 'a',
              'name': 'Amira',
              'holidays': [
                {
                  'date': '2026-06-04',
                  'name': 'Fronleichnam',
                  'halfDay': false,
                },
              ],
              'entries': [
                {
                  'from': '2026-06-01',
                  'to': '2026-06-02',
                  'halfDay': false,
                  'requested': true,
                },
              ],
            },
          ],
          'totalElements': 7,
          'visibility': 'BUSY_ONLY',
          'truncated': true,
        });

        expect(page.level, AbsenceCalendarLevel.busyOnly);
        expect(page.total, 7);
        expect(page.truncated, isTrue);
        expect(page.rows.single.holidays.single.name, 'Fronleichnam');
        expect(page.rows.single.entries.single.requested, isTrue);
        expect(page.rows.single.entries.single.typed, isFalse);
      },
    );

    test(
      'the policy reads the calendar level, and an old server means off',
      () {
        expect(
          TimePolicySnapshot.fromJson(const {
            'absenceCalendarVisibility': 'TYPE',
          }).absenceCalendar,
          AbsenceCalendarLevel.type,
        );
        expect(
          TimePolicySnapshot.fromJson(const {}).absenceCalendar,
          AbsenceCalendarLevel.off,
        );
      },
    );

    test('the band reads its buckets and resolution', () {
      final band = CapacityBand.fromJson(const {
        'resolution': 'WEEK',
        'people': 4,
        'buckets': [
          {
            'from': '2026-06-01',
            'to': '2026-06-07',
            'scheduledMinutes': 9600,
            'capacityMinutes': 7200,
            'away': 1,
            'requested': 2,
          },
        ],
      });
      expect(band.resolution, CapacityResolution.week);
      expect(band.buckets.single.share, 0.75);
      expect(band.buckets.single.requested, 2);
    });
  });
}
