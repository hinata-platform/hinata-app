import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/sprint/planning/held_cards.dart';

Issue _card({String? sprintId, int? points}) => Issue(
  id: 'c1',
  projectId: 'p1',
  readableId: 'HIN-1',
  title: 'Card',
  state: 'Open',
  sprintId: sprintId,
  storyPoints: points,
);

void main() {
  group('held cards', () {
    test('hold what the server had before the first change under way', () {
      final held = HeldCards()
        ..begin(_card(sprintId: 's1', points: 3))
        // A second change starts from the planning, not from the server.
        ..begin(_card(sprintId: 's2', points: 5));

      expect(held.sprintOf('c1'), 's1');
      expect(held.pointsOf('c1'), 3);
    });

    test('take what the server took while another change still runs', () {
      final held = HeldCards()
        ..begin(_card(sprintId: 's1', points: 3))
        ..begin(_card(sprintId: 's2', points: 3))
        ..moved('c1', 's2');

      expect(held.sprintOf('c1'), 's2');

      // Once no change is under way, the next one starts from the card again.
      held
        ..estimated('c1', 8)
        ..begin(_card(sprintId: 's3', points: 1));
      expect(held.sprintOf('c1'), 's3');
      expect(held.pointsOf('c1'), 1);
    });

    test('keep what the server holds when a change is refused', () {
      final held = HeldCards()
        ..begin(_card(points: 2))
        ..begin(_card(sprintId: 's1', points: 2))
        ..end('c1');

      expect(held.sprintOf('c1'), isNull);
      expect(held.pointsOf('c1'), 2);
    });
  });
}
