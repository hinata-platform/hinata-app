import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/admin/users/user_management_modals.dart';
import 'package:hinata/features/admin/users/user_management_widgets.dart';

/// The organisation role in user management (HIN-129): a badge beside the
/// platform role, and a switch in the drawer that grants or takes it back.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  AdminUser user({
    String id = 'u1',
    bool orgAdmin = false,
    UserStatus status = UserStatus.active,
  }) => AdminUser(
    id: id,
    name: id == 'me' ? 'Acting Admin' : 'Mira Kaya',
    username: 'mira',
    email: 'mira@example.org',
    title: '',
    role: AdminRole.user,
    orgAdmin: orgAdmin,
    origin: UserOrigin.local,
    status: status,
    twoFA: false,
    sso: false,
    sessions: 0,
  );

  UserActions actions(_FakeAdminRepository repository) => UserActions(
    openDrawer: (_) {},
    openEdit: (_) {},
    activate: (_) {},
    approve: (_) {},
    openDeactivate: (_) {},
    setRole: (_, _) {},
    setOrgAdmin: (ids, orgAdmin) async {
      try {
        await repository.adminSetOrgRole(ids, orgAdmin);
        return true;
      } catch (_) {
        return false;
      }
    },
    openDemote: (_) {},
    openResend: (_) {},
    openReset: (_) {},
    revokeSessions: (_) {},
    openDelete: (_) {},
    isLastActiveAdmin: (_) => false,
    nameById: (_) => null,
    currentUserId: 'me',
  );

  Widget host(AdminUser user, _FakeAdminRepository repository) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 440,
        height: 1400,
        child: UserDrawerBody(user: user, actions: actions(repository)),
      ),
    ),
  );

  Finder orgSwitch() => find.descendant(
    of: find.byType(OrgAdminToggle),
    matching: find.byType(HiveSwitch),
  );

  testWidgets('the drawer names the role and what it grants', (tester) async {
    await tester.pumpWidget(host(user(), _FakeAdminRepository()));
    await tester.pumpAndSettle();

    expect(find.text('admin.um.orgAdminTitle'), findsOneWidget);
    // What it grants waits behind the "i" rather than filling the drawer.
    expect(find.text('admin.um.orgAdminHint'), findsNothing);
    await tester.ensureVisible(find.byTooltip('admin.um.orgAdminInfo'));
    await tester.tap(find.byTooltip('admin.um.orgAdminInfo'));
    await tester.pumpAndSettle();
    expect(find.text('admin.um.orgAdminHint'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(tester.widget<HiveSwitch>(orgSwitch()).value, isFalse);
    // No badge for a role the user does not hold.
    expect(find.byType(OrgAdminBadge), findsNothing);
  });

  testWidgets('a screen reader reaches the switch and the "i" apart', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(user(), _FakeAdminRepository()));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byTooltip('admin.um.orgAdminInfo')),
      isSemantics(isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(orgSwitch()),
      isSemantics(label: 'admin.um.orgAdminTitle', hasToggledState: true),
    );
    semantics.dispose();
  });

  testWidgets('switching it on grants the role through the repository', (
    tester,
  ) async {
    final repository = _FakeAdminRepository();
    await tester.pumpWidget(host(user(), repository));
    await tester.pumpAndSettle();

    await tester.ensureVisible(orgSwitch());
    await tester.tap(orgSwitch());
    await tester.pumpAndSettle();

    // Records compare lists by identity, so the two halves are read apart.
    expect(repository.calls.single.$1, ['u1']);
    expect(repository.calls.single.$2, true);
    expect(tester.widget<HiveSwitch>(orgSwitch()).value, isTrue);
  });

  testWidgets('switching it off takes the role back', (tester) async {
    final repository = _FakeAdminRepository();
    await tester.pumpWidget(host(user(orgAdmin: true), repository));
    await tester.pumpAndSettle();

    expect(find.byType(OrgAdminBadge), findsOneWidget);
    await tester.ensureVisible(orgSwitch());
    await tester.tap(orgSwitch());
    await tester.pumpAndSettle();

    // Records compare lists by identity, so the two halves are read apart.
    expect(repository.calls.single.$1, ['u1']);
    expect(repository.calls.single.$2, false);
  });

  testWidgets('a refused change puts the switch back', (tester) async {
    final repository = _FakeAdminRepository(fail: true);
    await tester.pumpWidget(host(user(), repository));
    await tester.pumpAndSettle();

    await tester.ensureVisible(orgSwitch());
    await tester.tap(orgSwitch());
    await tester.pumpAndSettle();

    expect(repository.calls, hasLength(1));
    expect(tester.widget<HiveSwitch>(orgSwitch()).value, isFalse);
  });

  testWidgets('an open invitation cannot be given the role', (tester) async {
    final repository = _FakeAdminRepository();
    await tester.pumpWidget(host(user(status: UserStatus.invited), repository));
    await tester.pumpAndSettle();

    expect(tester.widget<HiveSwitch>(orgSwitch()).onChanged, isNull);
  });

  group('confirming the role', () {
    Future<bool?> ask(
      WidgetTester tester,
      List<AdminUser> users, {
      required bool grant,
      required String press,
    }) async {
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => answer = await confirmOrgAdminChange(
                  context,
                  users,
                  grant: grant,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (press.isNotEmpty) {
        await tester.tap(find.text(press).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      return answer;
    }

    testWidgets('granting asks first and names the person', (tester) async {
      final answer = await ask(tester, [user()], grant: true, press: '');
      expect(answer, isNull);
      expect(find.text('admin.um.orgAdminConfirmOne'), findsOneWidget);
      expect(find.text('Mira Kaya'), findsOneWidget);
    });

    testWidgets('granting to several lists all of them', (tester) async {
      const other = AdminUser(
        id: 'u2',
        name: 'Jon Berg',
        username: 'jon',
        email: 'jon@example.org',
        title: '',
        role: AdminRole.user,
        origin: UserOrigin.local,
        status: UserStatus.active,
        twoFA: false,
        sso: false,
        sessions: 0,
      );
      await ask(tester, [user(), other], grant: true, press: '');
      expect(find.text('admin.um.orgAdminConfirmMany'), findsOneWidget);
      expect(find.text('Mira Kaya'), findsOneWidget);
      expect(find.text('Jon Berg'), findsOneWidget);
    });

    testWidgets('a cancelled grant does not happen', (tester) async {
      final answer = await ask(
        tester,
        [user()],
        grant: true,
        press: 'common.cancel',
      );
      expect(answer, isFalse);
    });

    testWidgets('a confirmed grant goes ahead', (tester) async {
      final answer = await ask(
        tester,
        [user()],
        grant: true,
        press: 'admin.um.makeOrgAdmin',
      );
      expect(answer, isTrue);
    });

    testWidgets('taking the role back asks nothing', (tester) async {
      final answer = await ask(
        tester,
        [user(orgAdmin: true)],
        grant: false,
        press: '',
      );
      expect(answer, isTrue);
      expect(find.text('admin.um.orgAdminConfirmOne'), findsNothing);
    });
  });

  testWidgets('nobody switches the role on their own row', (tester) async {
    await tester.pumpWidget(host(user(id: 'me'), _FakeAdminRepository()));
    await tester.pumpAndSettle();

    expect(tester.widget<HiveSwitch>(orgSwitch()).onChanged, isNull);
    expect(find.text('admin.um.reasonOwnOrgRole'), findsOneWidget);
  });

  group('bulk grant', () {
    Future<_FakeAdminRepository> pumpBar(
      WidgetTester tester,
      List<AdminUser> selected,
    ) async {
      tester.view
        ..physicalSize = const Size(2400, 400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _FakeAdminRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BulkActionBar(
                selected: selected,
                actions: actions(repository),
                onClear: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return repository;
    }

    testWidgets('leaves out the acting admin', (tester) async {
      final repository = await pumpBar(tester, [user(id: 'me'), user()]);

      await tester.tap(find.text('admin.um.makeOrgAdmin'));
      await tester.pump();

      expect(repository.calls.single.$1, ['u1']);
    });

    testWidgets('is not offered for oneself alone', (tester) async {
      await pumpBar(tester, [user(id: 'me')]);
      expect(find.text('admin.um.makeOrgAdmin'), findsNothing);
    });
  });

  testWidgets('a row shows the badge beside the platform role', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RoleBadges(user(orgAdmin: true)))),
    );
    expect(find.byType(RoleBadge), findsOneWidget);
    expect(find.text('admin.um.orgAdminBadge'), findsOneWidget);
  });
}

class _FakeAdminRepository implements AdminRepository {
  _FakeAdminRepository({this.fail = false});

  final bool fail;
  final List<(List<String>, bool)> calls = [];

  @override
  Future<void> adminSetOrgRole(List<String> ids, bool orgAdmin) async {
    calls.add((ids, orgAdmin));
    if (fail) throw StateError('refused');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
