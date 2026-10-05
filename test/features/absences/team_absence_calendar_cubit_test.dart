import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/team_absence_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/features/absences/team_absence_calendar_cubit.dart';

import '../../support/recording_fake.dart';

void main() {
  late FakeAbsenceRepository absences;
  late FakeTeamRepository teams;
  late TeamAbsenceCalendarCubit cubit;

  final from = DateTime(2026, 6, 1);
  final to = DateTime(2026, 6, 30);
  const scope = TeamAbsenceScope(teamId: 'team1', label: 'Core');

  setUp(() {
    absences = FakeAbsenceRepository();
    teams = FakeTeamRepository();
    cubit = TeamAbsenceCalendarCubit(absences, teams);
  });

  tearDown(() => cubit.close());

  test('rows reads the window, group and page as given', () async {
    const page = TeamAbsencePage(
      rows: [],
      total: 0,
      level: AbsenceCalendarLevel.type,
    );
    absences.answer<TeamAbsencePage>(#teamCalendar, page);

    final result = await cubit.rows(
      from: from,
      to: to,
      scope: scope,
      awayOnly: true,
      page: 1,
      size: 100,
    );

    expect(result, same(page));
    expect(
      absences.only,
      invoked(
        #teamCalendar,
        named: {
          #from: from,
          #to: to,
          #scope: scope,
          #awayOnly: true,
          #page: 1,
          #size: 100,
        },
      ),
    );
  });

  test('band reads the resolution asked for', () async {
    const band = CapacityBand(
      resolution: CapacityResolution.week,
      people: 4,
      buckets: [],
    );
    absences.answer<CapacityBand>(#capacityBand, band);

    final result = await cubit.band(
      from: from,
      to: to,
      scope: scope,
      resolution: CapacityResolution.week,
    );

    expect(result, same(band));
    expect(
      absences.only,
      invoked(
        #capacityBand,
        named: {
          #from: from,
          #to: to,
          #scope: scope,
          #resolution: CapacityResolution.week,
        },
      ),
    );
  });

  test('a reader who does not plan the group gets no band', () async {
    absences.fail(
      #capacityBand,
      ApiFailure('error.availability.forbidden', statusCode: 403),
    );

    final result = await cubit.band(
      from: from,
      to: to,
      scope: scope,
      resolution: CapacityResolution.day,
    );

    expect(result, isNull);
  });

  test('any other failure of the band is handed back', () async {
    absences.fail(#capacityBand, failure);

    await expectLater(
      cubit.band(
        from: from,
        to: to,
        scope: scope,
        resolution: CapacityResolution.day,
      ),
      throwsA(same(failure)),
    );
  });

  test('teams offers each team as id and name', () async {
    teams.answer<List<Team>>(#teams, const [
      Team(id: 'team1', key: 'CORE', name: 'Core'),
    ]);

    expect(await cubit.teams(), [(id: 'team1', name: 'Core')]);
    expect(teams.only, invoked(#teams));
  });
}
