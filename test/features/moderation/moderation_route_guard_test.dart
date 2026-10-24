import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/core/router/app_router.dart';
import 'package:hinata/features/moderation/queue/moderation_screen.dart';
import 'package:hinata/features/shell/shell_nav.dart';

/// Who reaches the moderation pages (HIN-174), and how they sit in the shell.
void main() {
  AuthUser user(Set<String> roles) => AuthUser(
    id: 'u1',
    email: 'u1@example.org',
    username: 'u1',
    displayName: 'U One',
    roles: roles,
  );

  test('only moderators reach the page; everybody else lands on the '
      'dashboard', () {
    expect(moderationGuard(user({'USER', 'MODERATOR'})), isNull);
    // Administrators see no content since HIN-129, and moderation is content.
    expect(moderationGuard(user({'ADMIN'})), '/dashboard');
    expect(moderationGuard(user({'USER'})), '/dashboard');
    expect(moderationGuard(null), '/dashboard');
  });

  test('a case has an address of its own on the one page', () {
    expect(moderationLocation(), '/moderation');
    expect(
      moderationLocation(view: CaseView.appeal, caseId: 'k/1'),
      '/moderation?view=appeal&case=k%2F1',
    );
  });

  test('the pages carry a title and lead back to the settings', () {
    expect(
      subPageTitleKey('/moderation', advancedTime: false),
      'moderation.queue.title',
    );
    expect(
      subPageTitleKey(suspensionsLocation, advancedTime: false),
      'moderation.suspension.pageTitle',
    );
    expect(subPageBackRoute('/moderation'), '/settings');
    expect(subPageBackRoute(suspensionsLocation), '/moderation');
  });
}
