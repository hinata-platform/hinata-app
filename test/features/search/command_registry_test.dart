import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/search/command_registry.dart';
import 'package:hinata/features/search/search_models.dart';

/// What the ⌘K palette offers, and to whom.
///
/// The list used to be a literal inside the palette's own controller, private
/// and unreachable — which is how the timesheet came to be missing from it.
/// Since HIN-165 every page of the navigation is a command, each only where
/// the reader may see the page: a module that is off lists nothing, the admin
/// area is for admins, the organisation page for organisation admins.
void main() {
  const member = PaletteAccess();
  const everything = PaletteAccess(
    modules: SearchModules(
      advancedTime: true,
      absences: true,
      billing: true,
      shifts: true,
    ),
    admin: true,
    orgAdmin: true,
    mcp: true,
    workloadReports: true,
    absenceReports: true,
  );

  Iterable<String> ids(PaletteAccess access) =>
      paletteCommands(access).map((c) => c.id);

  test('the time module is listed only where the module exists', () {
    final without = ids(member);
    final with_ = ids(
      const PaletteAccess(modules: SearchModules(advancedTime: true)),
    );

    expect(without, isNot(contains('time.focus')));
    expect(without, isNot(contains('time.timesheet')));
    expect(without, isNot(contains('time.absences')));
    expect(without, isNot(contains('settings.time')));
    // The base timesheet is always there, and goes away where the module's
    // own takes its place.
    expect(without, contains('nav.timesheet'));
    expect(with_, isNot(contains('nav.timesheet')));
    expect(
      with_,
      containsAll([
        'time.toggle',
        'time.newEntry',
        'time.focus',
        'time.list',
        'time.calendar',
        'time.approvals',
        'time.timesheet',
        'time.absences',
        'time.askAbsence',
        'reports.overview',
        'reports.summary',
        'settings.time',
      ]),
    );
  });

  test('every navigation page is a command', () {
    final all = ids(everything);
    expect(
      all,
      containsAll([
        'nav.dashboard',
        'nav.projects',
        'nav.issues',
        'nav.board',
        'nav.timeline',
        'nav.reports',
        'nav.knowledge',
        'nav.teams',
        'nav.watched',
        'nav.notifications',
        'nav.weeklySummary',
        'nav.settings',
        'shifts.mine',
        'shifts.calendar',
        'shifts.events',
        'time.list',
        'time.calendar',
        'time.timesheet',
        'time.approvals',
        'time.absences',
        'reports.workload',
        'reports.billing',
        'billing.rates',
        'billing.invoices',
        'admin',
        'admin.users',
        'organization',
        'settings.security',
        'settings.tokens',
      ]),
    );
  });

  test('a module that is off lists none of its pages', () {
    final all = ids(member);
    expect(all.where((id) => id.startsWith('shifts.')), isEmpty);
    expect(all.where((id) => id.startsWith('billing.')), isEmpty);
    expect(all.where((id) => id.startsWith('reports.')), isEmpty);

    // Billing alone on is not enough for its pages: they are the organisation
    // admin's.
    final lead = ids(
      const PaletteAccess(
        modules: SearchModules(advancedTime: true, billing: true),
      ),
    );
    expect(lead, isNot(contains('billing.rates')));
    expect(lead, isNot(contains('reports.billing')));
  });

  test('pages that are not the reader\'s are not listed', () {
    final all = ids(member);
    expect(all.where((id) => id.startsWith('admin')), isEmpty);
    expect(all.where((id) => id.startsWith('organization')), isEmpty);
    expect(all, isNot(contains('settings.tokens')));

    final orgAdmin = ids(const PaletteAccess(orgAdmin: true));
    expect(orgAdmin, contains('organization'));
    expect(orgAdmin.where((id) => id.startsWith('admin')), isEmpty);

    final admin = ids(const PaletteAccess(admin: true));
    expect(admin, contains('admin.users'));
    expect(admin, isNot(contains('organization')));
  });

  test('a report tab is listed only where the report shows it', () {
    final plain = ids(
      const PaletteAccess(modules: SearchModules(advancedTime: true)),
    );
    expect(plain, isNot(contains('reports.workload')));
    expect(plain, isNot(contains('reports.absences')));
    expect(plain, isNot(contains('reports.billing')));
    expect(ids(everything), contains('reports.absences'));
  });

  test('every command either goes somewhere or does something', () {
    for (final command in paletteCommands(everything)) {
      expect(
        command.route != null || command.onSelect != null,
        isTrue,
        reason: '${command.id} does nothing at all',
      );
    }
  });

  test('every label exists in every language', () {
    final bundles = {
      for (final lang in const [
        'ar',
        'de',
        'en',
        'es',
        'fr',
        'hi',
        'ja',
        'ru',
        'zh',
      ])
        lang:
            jsonDecode(File('assets/i18n/$lang/common.json').readAsStringSync())
                as Map<String, dynamic>,
    };
    Object? lookup(Map<String, dynamic> bundle, String key) {
      Object? node = bundle;
      for (final part in key.split('.')) {
        if (node is! Map<String, dynamic>) return null;
        node = node[part];
      }
      return node;
    }

    for (final command in paletteCommands(everything)) {
      for (final key in [command.labelKey, ?command.contextKey]) {
        for (final MapEntry(key: lang, value: bundle) in bundles.entries) {
          expect(
            lookup(bundle, key),
            isA<String>(),
            reason: '${command.id}: $key missing in $lang',
          );
        }
      }
    }
  });

  test('no two commands share an id', () {
    final all = ids(everything).toList();
    expect(all.toSet(), hasLength(all.length));
  });

  test('a command that toggles something does not close the palette', () {
    final commands = {
      for (final command in paletteCommands(everything)) command.id: command,
    };

    // Both are switches: somebody comparing light against dark, or starting a
    // timer and then wanting the next command, should not have to reopen it.
    expect(commands['app.theme']!.closesOnSelect, isFalse);
    expect(commands['time.toggle']!.closesOnSelect, isFalse);
    // Navigating away obviously does.
    expect(commands['nav.board']!.closesOnSelect, isTrue);
  });

  test('a section says which page it belongs to', () {
    final commands = {
      for (final command in paletteCommands(everything)) command.id: command,
    };
    expect(commands['settings.security']!.contextKey, 'nav.settings');
    expect(commands['admin.security']!.contextKey, 'admin.title');
    expect(commands['settings.security']!.route, '/settings?section=security');
  });
}
