import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/models/time_models.dart';

/// What a day is, asked from one place for every surface that marks days
/// (HIN-91), and the calendar window that carries the layers.
void main() {
  final monday = DateTime(2026, 12, 21);
  final tuesday = DateTime(2026, 12, 22);
  final wednesday = DateTime(2026, 12, 23);
  final thursday = DateTime(2026, 12, 24);

  group('DayMarks', () {
    final marks = DayMarks(
      holidays: [
        HolidayMark(date: thursday, name: 'Heiligabend', halfDay: true),
      ],
      absences: [
        TimeOff(
          userId: 'u1',
          type: TimeOffType.vacation,
          from: tuesday,
          to: thursday,
        ),
      ],
      scheduledMinutes: {
        monday: 0,
        tuesday: 480,
        wednesday: 480,
        thursday: 480,
      },
    );

    test(
      'a holiday comes first, then an absence, then a day without hours',
      () {
        expect(
          marks.on(thursday),
          const DayMark.holiday('Heiligabend', halfDay: true),
        );
        expect(
          marks.on(wednesday),
          const DayMark.absence(TimeOffType.vacation),
        );
        expect(marks.on(monday), const DayMark.nonRegular());
      },
    );

    test(
      'an ordinary day, or a day the window says nothing about, is unmarked',
      () {
        expect(DayMarks(scheduledMinutes: {monday: 480}).on(monday), isNull);
        expect(marks.on(DateTime(2027, 1, 4)), isNull);
      },
    );

    test('a time of day does not move the day', () {
      expect(
        marks.on(DateTime(2026, 12, 21, 23, 30)),
        const DayMark.nonRegular(),
      );
    });

    test('windows loaded one at a time merge into one answer', () {
      final january = DayMarks(
        holidays: [HolidayMark(date: DateTime(2027, 1, 1), name: 'Neujahr')],
      );

      final both = marks.merge(january);

      expect(both.on(DateTime(2027, 1, 1)), const DayMark.holiday('Neujahr'));
      expect(both.on(monday), const DayMark.nonRegular());
    });

    test('overlapping windows keep one answer a day, the later window\'s', () {
      final earlier = DayMarks(
        absences: [
          TimeOff(
            userId: 'u1',
            type: TimeOffType.vacation,
            from: monday,
            to: wednesday,
          ),
        ],
      );
      final later = DayMarks(
        absences: [
          TimeOff(
            userId: 'u1',
            type: TimeOffType.sick,
            from: wednesday,
            to: thursday,
          ),
        ],
      );

      // The same window twice, as a list that pages back over it would.
      final both = earlier.merge(later).merge(later);

      expect(both.on(monday), const DayMark.absence(TimeOffType.vacation));
      expect(both.on(wednesday), const DayMark.absence(TimeOffType.sick));
      expect(both.on(thursday), const DayMark.absence(TimeOffType.sick));
    });
  });

  test('an absence covers its first and its last day', () {
    final absence = TimeOff(
      userId: 'u1',
      type: TimeOffType.sick,
      from: tuesday,
      to: wednesday,
    );

    expect(absence.covers(monday), isFalse);
    expect(absence.covers(tuesday), isTrue);
    expect(absence.covers(DateTime(2026, 12, 23, 18)), isTrue);
    expect(absence.covers(thursday), isFalse);
  });

  group('the calendar window', () {
    test('reads the layers stage 10 added', () {
      final window = CalendarWindow.fromJson(const {
        'from': '2026-12-21',
        'to': '2026-12-27',
        'entries': <dynamic>[],
        'truncated': false,
        'absences': <dynamic>[
          {
            'type': 'VACATION',
            'from': '2026-12-22',
            'to': '2026-12-22',
            'halfDay': true,
          },
          {'type': 'SOMETHING_NEW', 'from': '2026-12-23', 'to': '2026-12-23'},
        ],
        'holidays': <dynamic>[
          {'date': '2026-12-24', 'name': 'Heiligabend', 'halfDay': true},
        ],
        'scheduledMinutes': <String, dynamic>{
          '2026-12-21': 0,
          '2026-12-22': 480,
        },
      });

      // A type this build does not know is left out rather than guessed.
      expect(window.absences, hasLength(1));
      expect(
        window.marks.on(tuesday),
        const DayMark.absence(TimeOffType.vacation, halfDay: true),
      );
      expect(
        window.marks.on(thursday),
        const DayMark.holiday('Heiligabend', halfDay: true),
      );
      expect(window.marks.on(monday), const DayMark.nonRegular());
    });

    test('an answer without them reads as no markings', () {
      final window = CalendarWindow.fromJson(const {
        'from': '2026-12-21',
        'to': '2026-12-27',
        'entries': <dynamic>[],
      });

      expect(window.absences, isEmpty);
      expect(window.holidays, isEmpty);
      expect(window.marks.isEmpty, isTrue);
    });
  });

  test('a pattern always has seven days, whatever arrived', () {
    expect(WorkingPattern.minutesOf([480, 480]), [480, 480, 0, 0, 0, 0, 0]);
    expect(WorkingPattern.minutesOf(null), [0, 0, 0, 0, 0, 0, 0]);
  });
}
