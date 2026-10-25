import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/features/admin/users/user_management_widgets.dart';

/// Closing the user drawer on a wide window: a second tap on the dimmed page,
/// while the drawer is still sliding out, closes nothing else. It used to pop
/// the page below, and on the router's last page that crashed the app.
void main() {
  const user = AdminUser(
    id: 'u1',
    name: 'Mira Kaya',
    username: 'mira',
    email: 'mira@example.org',
    title: '',
    role: AdminRole.user,
    orgAdmin: false,
    origin: UserOrigin.local,
    status: UserStatus.active,
    twoFA: false,
    sso: false,
    sessions: 0,
  );

  final actions = UserActions(
    openDrawer: (_) {},
    openEdit: (_) {},
    activate: (_) {},
    approve: (_) {},
    openDeactivate: (_) {},
    setRole: (_, _) {},
    setOrgAdmin: (_, _) async => true,
    setModerator: (_, _) async => true,
    openDemote: (_) {},
    openResend: (_) {},
    openReset: (_) {},
    revokeSessions: (_) {},
    openUnlinkSso: (_) {},
    openLiftSuspension: (_) {},
    openDelete: (_) {},
    isLastActiveAdmin: (_) => false,
    nameById: (_) => null,
    currentUserId: 'me',
  );

  testWidgets('a second tap while the drawer slides out leaves the page', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1400, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Text('home')),
        routes: {
          '/users': (_) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showUserDrawer(
                  context,
                  user: user,
                  actions: actions,
                  phone: false,
                ),
                child: const Text('users page'),
              ),
            ),
          ),
        },
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/users');
    await tester.pumpAndSettle();
    await tester.tap(find.text('users page'));
    await tester.pumpAndSettle();

    // On the dimmed page left of the drawer, twice: the second lands while
    // the drawer is still on its way out.
    await tester.tapAt(const Offset(40, 500));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(40, 500));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('users page'), findsOneWidget);
  });
}
