import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/core/router/app_router.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/moderation/queue/moderation_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fixed_app_config.dart';

/// The moderation pages as the app's own router has them (HIN-174): the
/// address a notification opens, the suspended accounts, and a view that
/// comes back as it was written. Not the guard alone, which another test
/// checks: a route that forgot it would pass there.
void main() {
  AuthUser user(Set<String> roles) => AuthUser(
    id: 'u1',
    email: 'u1@example.org',
    username: 'u1',
    displayName: 'U One',
    roles: roles,
  );

  Future<GoRouter> routerFor(AuthUser who) async {
    SharedPreferences.setMockInitialValues({});
    final storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final router = buildRouter(
      appConfig: FixedAppConfig(),
      auth: RecordingAuth(user: who),
      storage: storage,
    );
    addTearDown(router.dispose);
    return router;
  }

  GoRouterState stateAt(GoRouter router, Uri uri, String fullPath) =>
      GoRouterState(
        router.configuration,
        uri: uri,
        matchedLocation: uri.path,
        fullPath: fullPath,
        pathParameters: router.configuration.findMatch(uri).pathParameters,
        pageKey: ValueKey(fullPath),
      );

  /// Where [location] sends [who] on, or null when it lets them in.
  Future<String?> redirectOf(
    WidgetTester tester,
    AuthUser who,
    String location,
  ) async {
    final router = await routerFor(who);
    final uri = Uri.parse(location);
    final match = router.configuration.findMatch(uri);
    final route = match.last.route;
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (built) {
          context = built;
          return const SizedBox();
        },
      ),
    );
    return route.redirect?.call(context, stateAt(router, uri, match.fullPath));
  }

  final moderator = user({'USER', 'MODERATOR'});
  final member = user({'USER'});

  testWidgets('a case a notification opens is the moderators\' alone', (
    tester,
  ) async {
    expect(
      await redirectOf(tester, moderator, '/moderation/cases/k1'),
      moderationLocation(caseId: 'k1'),
    );
    expect(
      await redirectOf(tester, member, '/moderation/cases/k1'),
      '/dashboard',
    );
  });

  testWidgets('so are the suspended accounts', (tester) async {
    expect(await redirectOf(tester, moderator, suspensionsLocation), isNull);
    expect(await redirectOf(tester, member, suspensionsLocation), '/dashboard');
  });

  testWidgets('a view comes back as it was written, with its case', (
    tester,
  ) async {
    final router = await routerFor(moderator);
    final uri = Uri.parse(
      moderationLocation(view: CaseView.appeal, caseId: 'k1'),
    );
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (built) {
          context = built;
          return const SizedBox();
        },
      ),
    );
    final route = router.configuration.findMatch(uri).last.route;
    final page =
        route.pageBuilder!(context, stateAt(router, uri, '/moderation'))
            as CustomTransitionPage<void>;
    final screen = page.child as ModerationScreen;

    expect(screen.view, CaseView.appeal);
    expect(screen.caseId, 'k1');
  });
}
