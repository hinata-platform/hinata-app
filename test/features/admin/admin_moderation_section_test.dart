import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/features/admin/admin_form_helpers.dart';
import 'package:hinata/features/admin/admin_settings_cubit.dart';
import 'package:hinata/features/admin/sections/admin_moderation_section.dart';

/// Admin → Moderation (HIN-26): who comes in without approval, who moderates,
/// a word when one person alone would decide, the contact for reports with a
/// warning while none is published, the house rules (HIN-175) and the text
/// check (HIN-176).
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
    AccountEntry entry = const AccountEntry(),
    Future<bool> Function()? onSave,
  }) async {
    final repository = _FakeAdminRepository(moderators, total)..entry = entry;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryProvider<AdminRepository>.value(
            value: repository,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AppConfigBloc>.value(
                  value: _StubAppConfig(contactMissing: contactMissing),
                ),
                BlocProvider(
                  create: (_) => AdminSettingsCubit(
                    admin: repository,
                    meta: _UnusedMeta(),
                  ),
                ),
              ],
              child: SingleChildScrollView(
                child: AdminModerationSection(
                  settings: settings ?? {},
                  onSave: onSave ?? () async => true,
                ),
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

  bool allowed(WidgetTester tester, String words) => tester
      .widget<AdminToggle>(
        find.widgetWithText(AdminToggle, 'admin.moderation.types.$words'),
      )
      .value;

  testWidgets('every file type is on until the server says otherwise, and '
      'looking writes nothing', (tester) async {
    final settings = <String, dynamic>{'moderation': <String, dynamic>{}};
    await pump(tester, moderators: [], settings: settings);

    for (final words in ['images', 'pdf', 'office', 'text', 'zip', 'voice']) {
      expect(allowed(tester, words), isTrue, reason: words);
    }
    expect((settings['moderation'] as Map).containsKey('uploads'), isFalse);
  });

  testWidgets('switching a file type writes the groups into the draft', (
    tester,
  ) async {
    // As decoded from JSON, with a group only a newer server knows.
    final settings = <String, dynamic>{
      'moderation': <String, dynamic>{
        'uploads': <String, dynamic>{
          'disabledGroups': <dynamic>['ZIP', 'FUTURE'],
        },
      },
    };
    await pump(tester, moderators: [], settings: settings);
    expect(allowed(tester, 'zip'), isFalse);

    for (final words in ['pdf', 'zip']) {
      final toggle = find.text('admin.moderation.types.$words');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }

    expect(allowed(tester, 'pdf'), isFalse);
    expect(allowed(tester, 'zip'), isTrue);
    final uploads = (settings['moderation'] as Map)['uploads'] as Map;
    expect(uploads['disabledGroups'], ['PDF', 'FUTURE']);
  });

  testWidgets('nothing about who comes in while every way waits for approval', (
    tester,
  ) async {
    await pump(tester, moderators: []);
    expect(find.text('admin.entry.title'), findsNothing);
    expect(find.text('admin.entry.proxy'), findsNothing);
  });

  testWidgets('an open way comes first, and switching approval on closes it '
      'in the draft and saves', (tester) async {
    final settings = <String, dynamic>{
      'app': <String, dynamic>{'registrationEnabled': true},
      'oidc': <String, dynamic>{'enabled': true, 'displayName': 'Firmen-SSO'},
    };
    late _FakeAdminRepository repository;
    var saves = 0;
    repository = await pump(
      tester,
      moderators: [],
      settings: settings,
      entry: const AccountEntry(
        openWays: [
          OpenWay(way: 'registration'),
          OpenWay(way: 'oidc', name: 'Firmen-SSO'),
        ],
      ),
      onSave: () async {
        saves++;
        repository.entry = const AccountEntry();
        return true;
      },
    );
    expect(find.text('admin.entry.title'), findsOneWidget);

    await tester.tap(find.text('admin.entry.enable'));
    await tester.pumpAndSettle();

    expect((settings['app'] as Map)['requireAdminApproval'], isTrue);
    expect((settings['oidc'] as Map)['requireApproval'], isTrue);
    expect(saves, 1);
    expect(find.text('admin.entry.title'), findsNothing);
  });

  testWidgets('a proxy the server does not trust is named on its own', (
    tester,
  ) async {
    await pump(
      tester,
      moderators: [],
      entry: const AccountEntry(proxyNotTrusted: true),
    );
    expect(find.text('admin.entry.proxy'), findsOneWidget);
    expect(find.text('admin.entry.enable'), findsNothing);
  });

  testWidgets('the house rules mode and text write into the draft', (
    tester,
  ) async {
    final settings = <String, dynamic>{'moderation': <String, dynamic>{}};
    await pump(tester, moderators: [], settings: settings);

    final own = find.text('admin.rules.mode.text');
    await tester.ensureVisible(own);
    await tester.tap(own);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rulesText')),
      '  # Unsere Regeln  ',
    );

    final rules = (settings['moderation'] as Map)['rules'] as Map;
    expect(rules['mode'], 'TEXT');
    expect(rules['text'], '# Unsere Regeln');
  });

  testWidgets('how long cases are kept writes into the draft, six months '
      'until somebody chooses', (tester) async {
    final settings = <String, dynamic>{'moderation': <String, dynamic>{}};
    await pump(tester, moderators: [], settings: settings);

    final chips = find.byWidgetPredicate(
      (widget) =>
          widget is GlassSwitchChip &&
          widget.label == 'admin.moderation.retentionMonths',
    );
    expect(chips, findsNWidgets(2));
    expect(tester.widget<GlassSwitchChip>(chips.first).active, isTrue);
    // Looking writes nothing: the server keeps its own value.
    expect(
      (settings['moderation'] as Map).containsKey('retentionMonths'),
      isFalse,
    );

    await tester.ensureVisible(chips.last);
    await tester.tap(chips.last);
    await tester.pumpAndSettle();
    expect((settings['moderation'] as Map)['retentionMonths'], 12);
  });

  testWidgets('every switcher is as wide as its choices: the house rules '
      'and how long cases are kept', (tester) async {
    // Room enough for the raw keys in the test font, so nothing scrolls.
    tester.view
      ..physicalSize = const Size(2400, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, moderators: []);

    final bars = find.byType(GlassSwitchBar);
    expect(bars, findsNWidgets(2));
    for (final bar in bars.evaluate()) {
      final chips = find.descendant(
        of: find.byWidget(bar.widget),
        matching: find.byType(GlassSwitchChip),
      );
      final width = tester
          .widgetList<GlassSwitchChip>(chips)
          .map((chip) => tester.getSize(find.byWidget(chip)).width)
          .fold<double>(0, (sum, width) => sum + width);
      expect(
        tester.getSize(find.byWidget(bar.widget)).width,
        closeTo(width + GlassSwitchBar.inset, 0.5),
      );
    }
  });

  testWidgets('asking everybody to agree again takes a confirmation', (
    tester,
  ) async {
    final repository = await pump(tester, moderators: []);

    final ask = find.text('admin.rules.reaccept');
    await tester.ensureVisible(ask);
    await tester.tap(ask);
    await tester.pumpAndSettle();
    expect(repository.reacceptances, 0);

    await tester.tap(find.text('admin.rules.reacceptConfirm'));
    await tester.pumpAndSettle();
    expect(repository.reacceptances, 1);
  });

  bool switchedOn(WidgetTester tester, String label) =>
      tester.widget<AdminToggle>(find.widgetWithText(AdminToggle, label)).value;

  testWidgets('the text check refuses until switched off, and looking writes '
      'nothing', (tester) async {
    final settings = <String, dynamic>{'moderation': <String, dynamic>{}};
    await pump(tester, moderators: [], settings: settings);

    expect(switchedOn(tester, 'admin.textCheck.block'), isTrue);
    expect(switchedOn(tester, 'admin.textCheck.flag'), isFalse);
    expect(find.text('admin.textCheck.flagNote'), findsNothing);
    expect((settings['moderation'] as Map).containsKey('filter'), isFalse);
  });

  testWidgets('putting texts before moderation comes with its note', (
    tester,
  ) async {
    final settings = <String, dynamic>{'moderation': <String, dynamic>{}};
    await pump(tester, moderators: [], settings: settings);

    final flag = find.text('admin.textCheck.flag');
    await tester.ensureVisible(flag);
    await tester.tap(flag);
    await tester.pumpAndSettle();

    final filter = (settings['moderation'] as Map)['filter'] as Map;
    expect(filter['flagEnabled'], isTrue);
    expect(find.text('admin.textCheck.flagNote'), findsOneWidget);
  });

  testWidgets('an own term is added once, in any case, and removed by its '
      'chip', (tester) async {
    // As decoded from JSON, with an exception already kept.
    final settings = <String, dynamic>{
      'moderation': <String, dynamic>{
        'filter': <String, dynamic>{
          'allowTerms': <dynamic>['Kill-Switch'],
        },
      },
    };
    await pump(tester, moderators: [], settings: settings);
    final filter = (settings['moderation'] as Map)['filter'] as Map;
    final field = find
        .widgetWithText(TextField, 'admin.textCheck.addTerm')
        .first;

    for (final term in ['  Spoiler ', 'spoiler']) {
      await tester.ensureVisible(field);
      await tester.enterText(field, term);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }
    expect(filter['blockTerms'], ['Spoiler']);
    expect(filter['allowTerms'], ['Kill-Switch']);

    await tester.ensureVisible(find.text('Spoiler'));
    await tester.tap(find.text('Spoiler'));
    await tester.pumpAndSettle();
    expect(filter['blockTerms'], isEmpty);
  });

  testWidgets('trying a text says what the server would do', (tester) async {
    final repository = await pump(tester, moderators: []);
    repository.verdict = const TextCheckResult(
      verdict: TextVerdict.allow,
      found: ['kill'],
      exceptions: ['kill -9'],
    );

    final field = find.widgetWithText(TextField, 'admin.textCheck.test');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Run kill -9 on the stuck worker');
    final check = find.text('admin.textCheck.testButton');
    await tester.ensureVisible(check);
    await tester.tap(check);
    await tester.pumpAndSettle();

    expect(repository.tested.single, 'Run kill -9 on the stuck worker');
    expect(
      find.text(
        'admin.textCheck.resultAllow admin.textCheck.resultFound '
        'admin.textCheck.resultException',
      ),
      findsOneWidget,
    );
  });
}

class _FakeAdminRepository implements AdminRepository {
  _FakeAdminRepository(this.moderators, this.total);

  final List<Map<String, dynamic>> moderators;
  final int? total;
  final List<UserRoleFilter?> roles = [];
  AccountEntry entry = const AccountEntry();
  HouseRulesVersions versions = HouseRulesVersions(
    version: 3,
    since: DateTime.utc(2026, 10, 2),
  );
  int reacceptances = 0;
  TextCheckResult verdict = const TextCheckResult(verdict: TextVerdict.allow);
  final List<String> tested = [];

  @override
  Future<AccountEntry> accountEntry() async => entry;

  @override
  Future<TextCheckResult> testText(String text) async {
    tested.add(text);
    return verdict;
  }

  @override
  Future<HouseRulesVersions> houseRulesVersions() async => versions;

  @override
  Future<HouseRulesVersions> requireRulesReacceptance() async {
    reacceptances++;
    return versions = HouseRulesVersions(
      version: (versions.version ?? 0) + 1,
      since: DateTime.utc(2026, 10, 24),
    );
  }

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
