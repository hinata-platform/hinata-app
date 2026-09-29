import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/router/app_router.dart';
import 'package:hinata/features/shell/shell_nav.dart';

/// Who reaches the Organisation pages (HIN-129), and how they sit in the shell.
void main() {
  AuthUser user(Set<String> roles) => AuthUser(
    id: 'u1',
    email: 'u1@example.org',
    username: 'u1',
    displayName: 'U One',
    roles: roles,
  );

  group('organizationGuard', () {
    test('lets an organisation admin through', () {
      expect(organizationGuard(user({'USER', 'ORG_ADMIN'})), isNull);
    });

    test('sends a platform admin without the role away', () {
      // The platform role does not open the organisation's settings.
      expect(organizationGuard(user({'ADMIN'})), '/dashboard');
    });

    test('sends everybody else away', () {
      expect(organizationGuard(user({'USER'})), '/dashboard');
      expect(organizationGuard(null), '/dashboard');
    });
  });

  group('the shell', () {
    test('gives the pages a sub-page bar', () {
      // A route missing here loses its back button and title.
      expect(subPageTitleKey('/organization', advancedTime: true), 'org.title');
      expect(
        subPageTitleKey('/organization/holidays', advancedTime: true),
        'availability.admin.pageTitle',
      );
    });

    test('leads back the way the pages are reached', () {
      expect(subPageBackRoute('/organization/holidays'), '/organization');
      expect(subPageBackRoute('/organization'), '/settings');
    });

    test('every page under Organisation has a title and leads back', () {
      // Read from the router itself, so a page added there without a bar
      // fails here instead of shipping without a back button.
      final router = File('lib/core/router/app_router.dart').readAsStringSync();
      final paths = {
        for (final m in RegExp(
          r"path: '(/organization/[^']+)'",
        ).allMatches(router))
          m.group(1)!,
      };
      expect(
        paths,
        containsAll(['/organization/holidays', '/organization/audit']),
      );
      for (final path in paths) {
        expect(
          subPageTitleKey(path, advancedTime: true),
          isNotNull,
          reason: path,
        );
        expect(subPageBackRoute(path), '/organization', reason: path);
      }
      expect(
        subPageTitleKey('/organization/audit', advancedTime: true),
        'org.audit.title',
      );
    });
  });
}
