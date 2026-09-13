import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/models/time_privacy_models.dart';

void main() {
  group('TimePolicySnapshot (HIN-89 fields)', () {
    test('reads the four new fields', () {
      final policy = TimePolicySnapshot.fromJson(const {
        'leadsSeeMemberEntries': true,
        'maxDaysBack': 30,
        'arbzgHintsEnabled': true,
        'lateEntryHintDays': 7,
      });

      expect(policy.leadsSeeMemberEntries, isTrue);
      expect(policy.maxDaysBack, 30);
      expect(policy.arbzgHintsEnabled, isTrue);
      expect(policy.lateEntryHintDays, 7);
      expect(policy.hintsEnabled, isTrue);
    });

    test('a server that does not send them yet means the old rules', () {
      final policy = TimePolicySnapshot.fromJson(const {});

      expect(policy.leadsSeeMemberEntries, isFalse);
      expect(policy.maxDaysBack, TimePolicySnapshot.defaultMaxDaysBack);
      expect(policy.hintsEnabled, isFalse);
    });

    test('the first recordable day reaches back to an opened older span', () {
      final today = DateTime(2026, 9, 10);
      final opened = TimePolicySnapshot(
        maxDaysBack: 30,
        lockExceptions: [
          TimeLockException(
            id: 'e1',
            from: DateTime(2026, 1, 5),
            to: DateTime(2026, 1, 9),
            note: 'Nachtrag',
          ),
        ],
      );

      expect(
        const TimePolicySnapshot(maxDaysBack: 30).firstRecordableDay(today),
        DateTime(2026, 8, 11),
      );
      expect(opened.firstRecordableDay(today), DateTime(2026, 1, 5));
    });

    test('days opened for the reader count as recordable and as open', () {
      final today = DateTime(2026, 9, 10);
      final policy = TimePolicySnapshot.fromJson(const {
        'maxDaysBack': 30,
        'lockBefore': '2026-09-01',
        'myBackfillGrants': [
          {
            'from': '2026-03-02',
            'to': '2026-03-06',
            'expiresAt': '2026-09-24T10:00:00Z',
          },
          {'from': null, 'to': '2026-03-06'},
        ],
      });

      expect(policy.myBackfillGrants, hasLength(1));
      expect(policy.firstRecordableDay(today), DateTime(2026, 3, 2));
      // Inside the limit, inside the opening, and the gap between them.
      expect(policy.withinReach(DateTime(2026, 8, 20), today), isTrue);
      expect(policy.withinReach(DateTime(2026, 3, 4), today), isTrue);
      expect(policy.withinReach(DateTime(2026, 5, 1), today), isFalse);
      // The lock date does not freeze days opened for the reader.
      expect(policy.isLocked(DateTime(2026, 3, 4)), isFalse);
      expect(policy.isLocked(DateTime(2026, 8, 20)), isTrue);
    });

    test('the frozen periods copy keeps the new fields', () {
      const policy = TimePolicySnapshot(
        leadsSeeMemberEntries: true,
        maxDaysBack: 60,
        lateEntryHintDays: 3,
      );

      final copy = policy.withFrozenPeriods(const []);

      expect(copy.leadsSeeMemberEntries, isTrue);
      expect(copy.maxDaysBack, 60);
      expect(copy.lateEntryHintDays, 3);
    });
  });

  group('the privacy answer', () {
    test('reads the notice, the confirmation and the visibility', () {
      final privacy = TimePrivacy.fromJson(const {
        'notice': '## Deine Arbeitszeit',
        'customNotice': false,
        'acknowledgedAt': '2026-09-10T12:00:00Z',
        'visibility': {
          'leadsSeeEntries': true,
          'entryRetentionMonths': 24,
          'timerEventsRecorded': false,
          'lateEntryHintDays': 7,
        },
      });

      expect(privacy.acknowledged, isTrue);
      expect(privacy.visibility.leadsSeeEntries, isTrue);
      expect(privacy.visibility.entryRetentionMonths, 24);
      expect(privacy.visibility.lateEntryHintDays, 7);
      expect(privacy.visibility.maxDaysBack, 365);
    });

    test('a hint without a day is dropped, a known kind is kept', () {
      expect(TimeHint.fromJson(const {'kind': 'SUNDAY_WORK'}), isNull);

      final hint = TimeHint.fromJson(const {
        'kind': 'LATE_ENTRY',
        'date': '2026-06-12',
        'entryId': 'w1',
        'daysLate': 90,
      })!;

      expect(hint.isKnown, isTrue);
      expect(hint.isLateEntry, isTrue);
      expect(hint.daysLate, 90);
      expect(
        TimeHint(kind: 'SOMETHING_NEW', date: DateTime(2026)).isKnown,
        isFalse,
      );
    });

    test('a correction request carries its answer when there is one', () {
      final request = TimeCorrectionRequest.fromJson(const {
        'id': 'r1',
        'entryId': 'w1',
        'date': '2026-09-02',
        'reason': 'LOCK_DATE',
        'note': 'Es waren 90 Minuten',
        'answer': {'note': 'Ich öffne den Tag.', 'byLabel': 'Admin'},
      });

      expect(request.answered, isTrue);
      expect(request.answer!.note, 'Ich öffne den Tag.');
      expect(request.date, DateTime(2026, 9, 2));
    });

    test('a request for older days names its span, and a grant says so', () {
      final request = TimeCorrectionRequest.fromJson(const {
        'id': 'r2',
        'kind': 'SPAN',
        'from': '2025-06-02',
        'to': '2025-06-06',
        'reason': 'MAX_DAYS_BACK',
        'grantable': true,
        'answer': {'note': 'Passt.', 'byLabel': 'Admin', 'granted': true},
      });

      expect(request.isSpan, isTrue);
      expect(request.from, DateTime(2025, 6, 2));
      expect(request.to, DateTime(2025, 6, 6));
      expect(request.grantable, isTrue);
      expect(request.answer!.granted, isTrue);
      // A server from before this stage sends neither: an entry nobody grants.
      final older = TimeCorrectionRequest.fromJson(const {
        'id': 'r3',
        'entryId': 'w1',
      });
      expect(older.isSpan, isFalse);
      expect(older.grantable, isFalse);
    });

    test('an opening for a person reads its span and when it closes', () {
      final grant = TimeBackfillGrant.fromJson(const {
        'id': 'g1',
        'userId': 'u2',
        'userLabel': 'Ada',
        'from': '2025-06-02',
        'to': '2025-06-06',
        'note': 'Nachtrag',
        'grantedByLabel': 'Admin',
        'grantedAt': '2026-09-12T08:00:00Z',
        'expiresAt': '2026-09-26T08:00:00Z',
      })!;

      expect(grant.from, DateTime(2025, 6, 2));
      expect(
        grant.expiresAt!.isAtSameMomentAs(DateTime.utc(2026, 9, 26, 8)),
        isTrue,
      );
      expect(
        TimeBackfillGrant.fromJson(const {'id': 'g2', 'from': '2025-06-02'}),
        isNull,
      );
    });
  });

  test('a refusal for a day too far back is a lock this build can name', () {
    final lock = TimeLockInfo.fromDetails(const {
      'reason': 'maxDaysBack',
      'holder': 'admin',
      'remedy': 'backfillGrant',
      'lockDate': '2026-08-11',
    });

    expect(lock, isNotNull);
    expect(lock!.isBeyondLimit, isTrue);
    expect(lock.reasonKey, 'time.lock.reason.maxDaysBack');
    expect(lock.lockDate, DateTime(2026, 8, 11));
  });
}
