import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/features/admin/users/user_management_modals.dart';
import 'package:hinata/features/admin/users/user_management_widgets.dart';
import 'package:hinata/features/auth/sso_errors.dart';

/// A suspension moderation decided (HIN-172), as the admin area shows it: the
/// badge says it with its end, and the drawer offers to lift it with a note,
/// in place of reactivating the account.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  // The badge spells the end as the app does once it has started.
  setUpAll(initializeDateFormatting);

  AdminUser user({bool suspended = true, DateTime? until}) => AdminUser(
    id: 'u1',
    name: 'Grace Hopper',
    username: 'grace',
    email: 'grace@example.org',
    title: '',
    role: AdminRole.user,
    origin: UserOrigin.local,
    status: UserStatus.disabled,
    twoFA: false,
    sso: false,
    sessions: 0,
    suspended: suspended,
    suspendedUntil: until,
  );

  UserActions actions(List<String> lifted, List<String> activated) =>
      UserActions(
        openDrawer: (_) {},
        openEdit: (_) {},
        activate: activated.addAll,
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
        openLiftSuspension: (u) => lifted.add(u.id),
        openDelete: (_) {},
        isLastActiveAdmin: (_) => false,
        nameById: (_) => null,
        currentUserId: 'me',
      );

  Widget host(AdminUser user, List<String> lifted, List<String> activated) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            height: 1400,
            child: UserDrawerBody(
              user: user,
              actions: actions(lifted, activated),
            ),
          ),
        ),
      );

  test('the admin view reads a suspension and its end', () {
    final read = AdminUser.fromJson(const {
      'id': 'u1',
      'role': 'USER',
      'origin': 'LOCAL',
      'status': 'DISABLED',
      'suspended': true,
      'suspendedUntil': '2026-11-01T12:00:00Z',
    });

    expect(read.suspended, isTrue);
    expect(read.suspendedUntil, DateTime.utc(2026, 11, 1, 12).toLocal());
    // A server from before HIN-172 sends neither.
    expect(
      AdminUser.fromJson(const {'id': 'u1', 'status': 'DISABLED'}).suspended,
      isFalse,
    );
  });

  test('a sign-in refused for a suspension has its own sentence', () {
    expect(ssoErrorKey('accountSuspended'), 'auth.ssoRefused.accountSuspended');
  });

  testWidgets('a suspended account offers to lift it instead of reactivating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lifted = <String>[];
    final activated = <String>[];
    await tester.pumpWidget(
      host(user(until: DateTime(2026, 11, 1)), lifted, activated),
    );
    await tester.pumpAndSettle();

    expect(find.text('admin.um.suspendedUntil'), findsWidgets);
    expect(find.text('admin.um.reactivateAccount'), findsNothing);
    await tester.ensureVisible(find.text('admin.um.liftSuspension'));
    await tester.tap(find.text('admin.um.liftSuspension'));
    await tester.pumpAndSettle();

    expect(lifted, ['u1']);
    expect(activated, isEmpty);
  });

  testWidgets('a suspension until further notice says no date', (tester) async {
    await tester.pumpWidget(host(user(), [], []));
    await tester.pumpAndSettle();

    expect(find.text('admin.um.suspended'), findsWidgets);
    expect(find.text('admin.um.suspendedUntil'), findsNothing);
  });

  testWidgets('lifting asks first and hands back the note', (tester) async {
    String? note;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  note = await showLiftSuspensionModal(context, user()),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField), 'Gespräch geführt');
    await tester.tap(find.text('admin.um.liftSuspensionAction').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(note, 'Gespräch geführt');
  });
}
