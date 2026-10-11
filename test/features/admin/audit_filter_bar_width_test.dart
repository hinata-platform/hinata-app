import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/audit_models.dart';
import 'package:hinata/features/admin/sections/admin_audit_section.dart';
import 'package:hinata/features/admin/sections/audit_log_cubit.dart';

/// The audit log's filter bar beside the organisation's menu.
///
/// On a wide window the bar is a search field beside a scrolling row of
/// filters. The search once had a fixed width of 320, so in the narrow column
/// a mid-sized window leaves next to the menu (about 314 points on macOS) the
/// row overflowed and drew the striped warning over the field.
void main() {
  testWidgets(
    'the filter bar fits a column narrower than the search once was',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final cubit = AuditLogCubit(
        ({
          String query = '',
          AuditCategory? category,
          AuditSeverity? severity,
          String? outcome,
          int page = 1,
          int perPage = 30,
        }) async => const AuditPage(items: [], total: 0, page: 1, perPage: 30),
      );
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                height: 800,
                child: BlocProvider.value(
                  value: cubit,
                  child: const AdminAuditSection(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
    },
  );
}
