import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/features/admin/users/user_management_modals.dart';
import 'package:hinata/features/admin/users/user_management_widgets.dart';

/// Undoing an account's SSO binding (HIN-179): the drawer offers it only for
/// an account that is bound, and asks before it goes through, because the
/// next sign-in with the address binds the account again.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  AdminUser user({bool ssoLinked = true}) => AdminUser(
    id: 'u1',
    name: 'Grace Hopper',
    username: 'grace',
    email: 'grace@example.org',
    title: '',
    role: AdminRole.user,
    origin: UserOrigin.oidc,
    status: UserStatus.active,
    twoFA: false,
    sso: true,
    ssoLinked: ssoLinked,
    sessions: 1,
  );

  UserActions actions(List<String> unlinked) => UserActions(
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
    openUnlinkSso: (u) => unlinked.add(u.id),
    openDelete: (_) {},
    isLastActiveAdmin: (_) => false,
    nameById: (_) => null,
    currentUserId: 'me',
  );

  Widget host(AdminUser user, List<String> unlinked) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 440,
        height: 1400,
        child: UserDrawerBody(user: user, actions: actions(unlinked)),
      ),
    ),
  );

  test('the admin view says whether an account is bound', () {
    Map<String, dynamic> json(Object? ssoLinked) => {
      'id': 'u1',
      'role': 'USER',
      'origin': 'OIDC',
      'status': 'ACTIVE',
      'ssoLinked': ?ssoLinked,
    };

    expect(AdminUser.fromJson(json(true)).ssoLinked, isTrue);
    expect(AdminUser.fromJson(json(false)).ssoLinked, isFalse);
    // A server from before HIN-179 does not send the field.
    expect(AdminUser.fromJson(json(null)).ssoLinked, isFalse);
  });

  testWidgets('a bound account offers to undo the binding', (tester) async {
    // The whole drawer on screen: the row sits below the default 600 px.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final unlinked = <String>[];
    await tester.pumpWidget(host(user(), unlinked));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('admin.um.unlinkSso'));
    await tester.tap(find.text('admin.um.unlinkSso'));
    await tester.pumpAndSettle();

    expect(unlinked, ['u1']);
  });

  testWidgets('an account without a binding has nothing to undo', (
    tester,
  ) async {
    await tester.pumpWidget(host(user(ssoLinked: false), []));
    await tester.pumpAndSettle();

    expect(find.text('admin.um.unlinkSso'), findsNothing);
  });

  testWidgets('undoing a binding asks first', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  answer = await showUnlinkSsoModal(context, user()),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('admin.um.unlinkSsoConfirm'), findsOneWidget);
    await tester.tap(find.text('admin.um.unlinkSsoAction').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(answer, isTrue);
  });
}
