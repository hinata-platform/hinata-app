import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/router/app_router.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/board/board_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_fake.dart';

/// Every address a search hit hands out (API-HIN-165), resolved by the app's
/// own router, not by a table the test builds itself: a route that went away
/// would fail here, where a hand-made table would still pass.
void main() {
  /// The address a hit carries, and the route that has to answer it.
  const links = <String, String>{
    '/issues/i1': '/issues/:id',
    '/issues/i1?comment=c1': '/issues/:id',
    '/issues/i1?attachment=a1': '/issues/:id',
    '/issues?projectId=p1': '/issues',
    '/teams/t1': '/teams/:id',
    '/people/u1': '/people/:id',
    // A board's old address, turned before going (see [currentBoardLink]).
    '/boards/b1': '/board/:id',
    '/boards/b1?sprint=s1': '/board/:id',
    '/knowledge/k1': '/knowledge/:id',
    '/knowledge/spaces/Handbuch%20Verein': '/knowledge/spaces/:space',
    '/shifts/events/e1': '/shifts/events/:id',
    '/shifts/events/e1?shift=sh1': '/shifts/events/:id',
    '/time/calendar?date=2026-10-19&entry=te1': '/time/calendar',
    '/time/timesheet?date=2026-10-19&project=p1': '/time/timesheet',
    '/time/absences?scope=requests&request=r1': '/time/absences',
    '/time/absences?scope=requests&type=ty1': '/time/absences',
    '/projects/p1/settings?section=timeTracking': '/projects/:id/settings',
    '/time/rates?rate=ra1': '/time/rates',
  };

  test('every address a hit names is a page of the app', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final appConfig = AppConfigBloc(
      repository: FakeMetaRepository(),
      storage: storage,
    );
    final auth = AuthBloc(repository: FakeAuthRepository(), storage: storage);
    addTearDown(appConfig.close);
    addTearDown(auth.close);
    final router = buildRouter(
      appConfig: appConfig,
      auth: auth,
      storage: storage,
    );
    addTearDown(router.dispose);

    for (final MapEntry(key: link, value: route) in links.entries) {
      final uri = Uri.parse(currentBoardLink(link));
      final match = router.configuration.findMatch(uri);
      expect(match.isError, isFalse, reason: '$link matches no route');
      expect(match.fullPath, route, reason: '$link lands elsewhere');
      // The query reaches the page as it was sent.
      expect(match.uri.queryParameters, uri.queryParameters);
    }
  });
}
