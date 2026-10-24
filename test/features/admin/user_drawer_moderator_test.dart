import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/admin/users/user_management_modals.dart';
import 'package:hinata/features/admin/users/user_management_widgets.dart';

/// The moderation role in user management (HIN-26): a switch in the drawer
/// beside the organisation role, a badge in the row, and a question before it
/// is granted.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  AdminUser user({
    String id = 'u1',
    bool moderator = false,
    UserStatus status = UserStatus.active,
  }) => AdminUser(
    id: id,
    name: id == 'me' ? 'Acting Admin' : 'Mira Kaya',
    username: 'mira',
    email: 'mira@example.org',
    title: '',
    role: AdminRole.user,
    moderator: moderator,
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
    setOrgAdmin: (_, _) async => true,
    setModerator: (ids, moderator) async {
      try {
        await repository.adminSetModeratorRole(ids, moderator);
        return true;
      } catch (_) {
        return false;
      }
    },
    openDemote: (_) {},
    openResend: (_) {},
    openReset: (_) {},
    revokeSessions: (_) {},
    openUnlinkSso: (_) {},
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

  Finder moderatorSwitch() => find.descendant(
    of: find.byType(ModeratorToggle),
    matching: find.byType(HiveSwitch),
  );

  testWidgets(
    'the drawer names the role, and what it grants waits behind the "i"',
    (tester) async {
      await tester.pumpWidget(host(user(), _FakeAdminRepository()));
      await tester.pumpAndSettle();

      expect(find.text('admin.um.moderatorTitle'), findsOneWidget);
      expect(find.text('admin.um.moderatorHint'), findsNothing);
      await tester.ensureVisible(find.byTooltip('admin.um.moderatorInfo'));
      await tester.tap(find.byTooltip('admin.um.moderatorInfo'));
      await tester.pumpAndSettle();
      expect(find.text('admin.um.moderatorHint'), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(tester.widget<HiveSwitch>(moderatorSwitch()).value, isFalse);
      expect(find.byType(ModeratorBadge), findsNothing);
    },
  );

  testWidgets('a screen reader reaches the switch by the role name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(user(), _FakeAdminRepository()));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(moderatorSwitch()),
      isSemantics(label: 'admin.um.moderatorTitle', hasToggledState: true),
    );
    semantics.dispose();
  });

  testWidgets('switching it on and off goes through the repository', (
    tester,
  ) async {
    final repository = _FakeAdminRepository();
    await tester.pumpWidget(host(user(), repository));
    await tester.pumpAndSettle();

    await tester.ensureVisible(moderatorSwitch());
    await tester.tap(moderatorSwitch());
    await tester.pumpAndSettle();
    expect(tester.widget<HiveSwitch>(moderatorSwitch()).value, isTrue);
    await tester.tap(moderatorSwitch());
    await tester.pumpAndSettle();

    // Records compare lists by identity, so the halves are read apart.
    expect(repository.calls.map((c) => c.$1), [
      ['u1'],
      ['u1'],
    ]);
    expect(repository.calls.map((c) => c.$2), [true, false]);
  });

  testWidgets('a refused change, such as the last moderator, puts it back', (
    tester,
  ) async {
    final repository = _FakeAdminRepository(fail: true);
    await tester.pumpWidget(host(user(moderator: true), repository));
    await tester.pumpAndSettle();

    await tester.ensureVisible(moderatorSwitch());
    await tester.tap(moderatorSwitch());
    await tester.pumpAndSettle();

    expect(repository.calls, hasLength(1));
    expect(tester.widget<HiveSwitch>(moderatorSwitch()).value, isTrue);
  });

  testWidgets('nobody switches it on their own row or for an open invitation', (
    tester,
  ) async {
    await tester.pumpWidget(host(user(id: 'me'), _FakeAdminRepository()));
    await tester.pumpAndSettle();
    expect(tester.widget<HiveSwitch>(moderatorSwitch()).onChanged, isNull);
    expect(find.text('admin.um.reasonOwnModeratorRole'), findsOneWidget);

    await tester.pumpWidget(
      host(user(status: UserStatus.invited), _FakeAdminRepository()),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<HiveSwitch>(moderatorSwitch()).onChanged, isNull);
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
                onPressed: () async => answer = await confirmModeratorChange(
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
      expect(find.text('admin.um.moderatorConfirmOne'), findsOneWidget);
      expect(find.text('Mira Kaya'), findsOneWidget);
    });

    testWidgets('a cancelled grant does not happen, a confirmed one does', (
      tester,
    ) async {
      expect(
        await ask(tester, [user()], grant: true, press: 'common.cancel'),
        isFalse,
      );
      expect(
        await ask(
          tester,
          [user()],
          grant: true,
          press: 'admin.um.makeModerator',
        ),
        isTrue,
      );
    });

    testWidgets('taking the role back asks nothing', (tester) async {
      final answer = await ask(
        tester,
        [user(moderator: true)],
        grant: false,
        press: '',
      );
      expect(answer, isTrue);
      expect(find.text('admin.um.moderatorConfirmOne'), findsNothing);
    });
  });

  testWidgets('a row shows the badge beside the platform role', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RoleBadges(user(moderator: true)))),
    );
    expect(find.byType(RoleBadge), findsOneWidget);
    expect(find.text('admin.um.moderatorBadge'), findsOneWidget);
  });
}

class _FakeAdminRepository implements AdminRepository {
  _FakeAdminRepository({this.fail = false});

  final bool fail;
  final List<(List<String>, bool)> calls = [];

  @override
  Future<void> adminSetModeratorRole(List<String> ids, bool moderator) async {
    calls.add((ids, moderator));
    if (fail) throw StateError('refused');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
