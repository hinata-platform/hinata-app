import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/admin/sections/admin_moderation_section.dart';

/// Admin → Moderation (HIN-26): who moderates, a word when one person alone
/// would decide, and the contact for reports with a warning while none is
/// published.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  Map<String, dynamic> person(String id, String name) => {
    'id': id,
    'name': name,
    'email': '$id@example.org',
    'moderator': true,
  };

  Future<_FakeAdminRepository> pump(
    WidgetTester tester, {
    required List<Map<String, dynamic>> moderators,
    int? total,
    bool contactMissing = false,
    Map<String, dynamic>? settings,
  }) async {
    final repository = _FakeAdminRepository(moderators, total);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryProvider<AdminRepository>.value(
            value: repository,
            child: BlocProvider<AppConfigBloc>.value(
              value: _StubAppConfig(contactMissing: contactMissing),
              child: SingleChildScrollView(
                child: AdminModerationSection(settings: settings ?? {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('lists who moderates, asked for the role by name', (
    tester,
  ) async {
    final repository = await pump(
      tester,
      moderators: [person('u1', 'Mira Kaya'), person('u2', 'Jon Berg')],
    );

    expect(repository.roles.single, UserRoleFilter.moderator);
    expect(find.text('Mira Kaya'), findsOneWidget);
    expect(find.text('Jon Berg'), findsOneWidget);
    expect(find.text('admin.moderation.onlyOne'), findsNothing);
  });

  testWidgets('one moderator alone gets the word about deciding on oneself', (
    tester,
  ) async {
    await pump(tester, moderators: [person('u1', 'Mira Kaya')]);

    expect(find.text('admin.moderation.onlyOne'), findsOneWidget);
  });

  testWidgets('nobody moderating is a warning', (tester) async {
    await pump(tester, moderators: []);
    expect(find.text('admin.moderation.nobody'), findsOneWidget);
  });

  testWidgets('more than a page is counted, not left out', (tester) async {
    await pump(tester, moderators: [person('u1', 'Mira Kaya')], total: 51);
    expect(find.text('admin.moderation.more'), findsOneWidget);
    expect(find.text('admin.moderation.onlyOne'), findsNothing);
  });

  testWidgets('the missing contact is a warning until the server has one', (
    tester,
  ) async {
    await pump(tester, moderators: [], contactMissing: true);
    expect(find.text('admin.moderation.contactMissing'), findsOneWidget);

    await pump(tester, moderators: []);
    expect(find.text('admin.moderation.contactMissing'), findsNothing);
  });

  testWidgets('the contact fields write into the draft, blank as none', (
    tester,
  ) async {
    // As decoded from JSON: maps of dynamic values.
    final settings = <String, dynamic>{
      'moderation': <String, dynamic>{'contactEmail': 'old@example.org'},
    };
    await pump(tester, moderators: [], settings: settings);

    expect(find.text('old@example.org'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'admin.moderation.contactEmail'),
      ' moderation@example.org ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'admin.moderation.imprintUrl'),
      '   ',
    );

    final moderation = settings['moderation'] as Map<String, dynamic>;
    expect(moderation['contactEmail'], 'moderation@example.org');
    expect(moderation['imprintUrl'], isNull);
  });
}

class _FakeAdminRepository implements AdminRepository {
  _FakeAdminRepository(this.moderators, this.total);

  final List<Map<String, dynamic>> moderators;
  final int? total;
  final List<UserRoleFilter?> roles = [];

  @override
  Future<AdminUserPage> adminUsersPage({
    String query = '',
    UserRoleFilter? role,
    UserStatus? status,
    UserOrigin? origin,
    UserSortKey sort = UserSortKey.lastActive,
    bool desc = true,
    int page = 1,
    int perPage = 25,
  }) async {
    roles.add(role);
    return AdminUserPage.fromJson({
      'items': moderators,
      'total': total ?? moderators.length,
      'page': page,
      'perPage': perPage,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Answers with one fixed meta and dispatches nothing.
class _StubAppConfig extends AppConfigBloc {
  _StubAppConfig({required bool contactMissing})
    : super(repository: _UnusedMeta(), storage: _UnusedStorage()) {
    emit(
      AppConfigState(
        status: AppConfigStatus.ready,
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          moderation: ModerationMeta(
            version: 1,
            contactMissing: contactMissing,
          ),
        ),
      ),
    );
  }
}

class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
