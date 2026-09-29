import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';

/// How a new relative deadline counts (HIN-129): the project's own basis,
/// else the organisation's, else calendar days. One helper for every editor.
void main() {
  ServerMeta meta(String? basis) =>
      ServerMeta.fromJson({'defaultDeadlineBasis': ?basis});

  const project = Project(id: 'p1', key: 'P', name: 'P');

  test('the server meta parses the basis into its type', () {
    expect(meta('WORKING').defaultDeadlineBasis, RelativeDateBasis.working);
    expect(meta('CALENDAR').defaultDeadlineBasis, RelativeDateBasis.calendar);
    // A server that predates the field counts calendar days.
    expect(meta(null).defaultDeadlineBasis, RelativeDateBasis.calendar);
  });

  test('the project wins, then the organisation, then calendar days', () {
    final own = project.copyWith(deadlineBasis: RelativeDateBasis.calendar);
    expect(deadlineBasisFor(own, meta('WORKING')), RelativeDateBasis.calendar);
    expect(
      deadlineBasisFor(project, meta('WORKING')),
      RelativeDateBasis.working,
    );
    expect(deadlineBasisFor(null, meta('WORKING')), RelativeDateBasis.working);
    expect(deadlineBasisFor(null, null), RelativeDateBasis.calendar);
  });
}
