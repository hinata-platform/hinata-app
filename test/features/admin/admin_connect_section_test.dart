import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/features/admin/sections/admin_connect_section.dart';

import '../../support/fixed_app_config.dart';
import '../../support/recording_fake.dart';

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
            value: (FakeAdminRepository()
              // Not enrolled yet: the section offers to connect.
              ..answer<Map<String, dynamic>>(#connectStatus, {
                'enrolled': false,
              })),
            child: BlocProvider<AppConfigBloc>.value(
              value: FixedAppConfig(
                moderation: ModerationMeta(
                  version: 1,
                  contactMissing: contactMissing,
                ),
              ),
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
