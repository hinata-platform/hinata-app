import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/admin/sections/admin_connect_section.dart';

/// Admin → Connect (HIN-178): Hinata Connect asks every instance for a contact
/// for reports, so the section says so while the instance publishes none.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  Future<void> pump(WidgetTester tester, {required bool contactMissing}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryProvider<AdminRepository>.value(
            value: _FakeAdmin(),
            child: BlocProvider<AppConfigBloc>.value(
              value: _StubAppConfig(contactMissing: contactMissing),
              child: const SingleChildScrollView(child: AdminConnectSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('asks for the contact for reports while none is published', (
    tester,
  ) async {
    await pump(tester, contactMissing: true);

    expect(find.text('admin.connectContactMissing'), findsOneWidget);
  });

  testWidgets('says nothing once the contact is published', (tester) async {
    await pump(tester, contactMissing: false);

    expect(find.text('admin.connectContactMissing'), findsNothing);
  });
}

/// Not enrolled yet: the section offers to connect.
class _FakeAdmin implements AdminRepository {
  @override
  Future<Map<String, dynamic>> connectStatus() async => {'enrolled': false};

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
