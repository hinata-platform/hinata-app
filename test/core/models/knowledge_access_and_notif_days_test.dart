import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/models/team_models.dart';

/// HIN-129 wire shapes: a membership's knowledge access, and the days
/// notifications may arrive on.
void main() {
  group('KnowledgeAccess', () {
    test('SOME round-trips with its pages', () {
      final access = KnowledgeAccess.some(const ['a1', 'a2']);
      final json = access.toJson();

      expect(json, {
        'scope': 'SOME',
        'articleIds': ['a1', 'a2'],
      });
      expect(KnowledgeAccess.fromJson(json), access);
    });

    test('ALL and NONE carry no page list', () {
      expect(const KnowledgeAccess.all().toJson(), {'scope': 'ALL'});
      expect(const KnowledgeAccess.none().toJson(), {'scope': 'NONE'});
      expect(
        KnowledgeAccess.fromJson(const {'scope': 'ALL'}),
        const KnowledgeAccess.all(),
      );
    });

    test('a membership without knowledge reads nothing', () {
      final membership = TeamMembership.fromJson(const {
        'userId': 'u1',
        'role': 'MEMBER',
        'access': {'scope': 'ALL'},
      });

      expect(membership.knowledge, const KnowledgeAccess.none());
      expect(membership.access.scope, AccessScope.all);
    });

    test('a membership keeps its knowledge grant', () {
      final membership = TeamMembership.fromJson(const {
        'userId': 'u1',
        'knowledge': {
          'scope': 'SOME',
          'articleIds': ['p1'],
        },
      });

      expect(membership.knowledge.scope, AccessScope.some);
      expect(membership.knowledge.articleIds, ['p1']);
    });
  });

  group('NotifPrefs weekdays', () {
    Map<String, dynamic> wire({Object? weekdays, Object? defaults}) => {
      'emailEnabled': true,
      'pushEnabled': false,
      'events': <String, dynamic>{},
      'weekdays': weekdays,
      'defaultWeekdays': ?defaults,
    };

    test('own days round-trip as DayOfWeek names', () {
      final prefs = NotifPrefs.fromJson(
        wire(
          weekdays: ['SUNDAY', 'MONDAY', 'WEDNESDAY'],
          defaults: ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY'],
        ),
      );

      expect(prefs.weekdays, [1, 3, 7]);
      expect(prefs.defaultWeekdays, [1, 2, 3, 4, 5]);
      expect(prefs.effectiveWeekdays, [1, 3, 7]);
      expect(prefs.toJson()['weekdays'], ['MONDAY', 'WEDNESDAY', 'SUNDAY']);
    });

    test('null follows the default and is sent as null', () {
      final prefs = NotifPrefs.fromJson(
        wire(
          defaults: ['SUNDAY', 'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY'],
        ),
      );

      expect(prefs.weekdays, isNull);
      expect(prefs.hasCustomWeekdays, isFalse);
      expect(prefs.effectiveWeekdays, [1, 2, 3, 4, 7]);
      final json = prefs.toJson();
      expect(json.containsKey('weekdays'), isTrue);
      expect(json['weekdays'], isNull);
      // Read-only: the server computes it, the app never sends it back.
      expect(json.containsKey('defaultWeekdays'), isFalse);
    });

    test(
      'an older server without a default falls back to Monday to Friday',
      () {
        final prefs = NotifPrefs.fromJson(wire());
        expect(prefs.defaultWeekdays, NotifPrefs.workingWeekdays);
      },
    );

    test('copyWith sets days, keeps them, and resets them to null', () {
      final base = NotifPrefs.fromJson(wire());
      final custom = base.copyWith(weekdays: [6, 7]);
      expect(custom.weekdays, [6, 7]);
      expect(custom.copyWith(emailEnabled: false).weekdays, [6, 7]);
      expect(custom.copyWith(weekdays: null).weekdays, isNull);
    });
  });
}
