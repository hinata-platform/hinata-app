import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/router/app_router.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/moderation/notice/notice_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_fake.dart';

/// A second notice opened from the bell is that notice: go_router keys the
/// page by the route pattern, so without a key of its own the screen stayed,
/// with the first case's notice and an appeal button for the first case.
void main() {
  testWidgets('each notice is a screen of its own', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final appConfig = AppConfigBloc(
      repository: FakeMetaRepository(),
      storage: storage,
    );
    // Not closed: Bloc.close() inside a testWidgets body runs against the fake
    // clock and never settles. An open bloc holds no timers.
    final auth = AuthBloc(repository: FakeAuthRepository(), storage: storage);
    final router = buildRouter(
      appConfig: appConfig,
      auth: auth,
      storage: storage,
    );
    addTearDown(router.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (built) {
          context = built;
          return const SizedBox();
        },
      ),
    );

    NoticeScreen screenFor(String caseId) {
      final uri = Uri.parse('/notices/$caseId');
      final route = router.configuration.findMatch(uri).last.route;
      final page =
          route.pageBuilder!(
                context,
                GoRouterState(
                  router.configuration,
                  uri: uri,
                  matchedLocation: uri.path,
                  fullPath: '/notices/:caseId',
                  pathParameters: {'caseId': caseId},
                  pageKey: const ValueKey('/notices/:caseId'),
                ),
              )
              as CustomTransitionPage<void>;
      return page.child as NoticeScreen;
    }

    final first = screenFor('A');
    final second = screenFor('B');
    expect(second.caseId, 'B');
    expect(second.key, isNot(first.key));
  });
}
