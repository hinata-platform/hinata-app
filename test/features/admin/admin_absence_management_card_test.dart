import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/admin/policy_controls.dart';
import 'package:hinata/features/admin/sections/admin_absence_management_card.dart';

/// The switch that brings absence management into existence, and the circle of
/// people who keep it.
///
/// Three things here are not cosmetic. The switch carries the co-determination
/// note, because general holiday principles and the holiday plan are
/// co-determined in their own right (§ 87 Abs. 1 Nr. 5 BetrVG). It says so when
/// it cannot take effect, rather than looking on while the routes answer 404.
/// And an empty keeper list is a statement — administrators — not a gap.
///
/// Widget tests render raw i18n keys, so nothing here asserts on copy.
void main() {
  Widget host({
    bool? enabled,
    bool? effective,
    bool advancedOn = true,
    List<String> managers = const [],
    ValueChanged<bool?>? onEnabledChanged,
    ValueChanged<List<String>>? onManagersChanged,
  }) => RepositoryProvider<UserRepository>.value(
    value: _FakeUsers(),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 900,
            child: SingleChildScrollView(
              child: AdminAbsenceManagementCard(
                enabled: enabled,
                effective: effective,
                advancedOn: advancedOn,
                managers: managers,
                onEnabledChanged: onEnabledChanged ?? (_) {},
                onManagersChanged: onManagersChanged ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('the switch carries the co-determination note', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final policy = tester.widget<PolicySwitch>(find.byType(PolicySwitch));
    expect(policy.title, 'admin.absence.enabledTitle');
    expect(policy.monitoring, isTrue);
    expect(find.byType(CodeterminationNote), findsOneWidget);
  });

  testWidgets('off is the state a fresh instance is in', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Nothing stored and nothing resolved: the module is not there yet.
    final policy = tester.widget<PolicySwitch>(find.byType(PolicySwitch));
    expect(policy.value, isNull);
    expect(policy.effective, isNull);
  });

  testWidgets('without the extended module it says why it cannot work', (
    tester,
  ) async {
    await tester.pumpWidget(host(enabled: true, advancedOn: false));
    await tester.pumpAndSettle();

    expect(find.text('admin.absence.needsAdvanced'), findsOneWidget);
    // And the switch keeps the position somebody left it in: turning the
    // extended module on must not look like flipping a second switch.
    expect(
      tester.widget<PolicySwitch>(find.byType(PolicySwitch)).value,
      isTrue,
    );
  });

  testWidgets('with the extended module on, the warning is gone', (
    tester,
  ) async {
    await tester.pumpWidget(host(enabled: true, advancedOn: true));
    await tester.pumpAndSettle();

    expect(find.text('admin.absence.needsAdvanced'), findsNothing);
  });

  testWidgets('nobody named means administrators, and the card says so', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('admin.absence.keepersEmpty'), findsOneWidget);
    expect(find.text('admin.absence.keepersAdd'), findsOneWidget);
  });

  testWidgets('a named keeper is shown by name and can be removed', (
    tester,
  ) async {
    List<String>? changed;
    await tester.pumpWidget(
      host(managers: const ['u-1'], onManagersChanged: (ids) => changed = ids),
    );
    await tester.pumpAndSettle();

    // Read from the directory, not printed as an object id.
    expect(find.text('Nina Keeper'), findsOneWidget);
    expect(find.text('admin.absence.keepersEmpty'), findsNothing);

    await tester.tap(find.byTooltip('common.remove'));
    await tester.pumpAndSettle();

    expect(changed, isEmpty);
  });

  testWidgets('a keeper whose name cannot be read is still removable', (
    tester,
  ) async {
    List<String>? changed;
    await tester.pumpWidget(
      host(managers: const ['gone'], onManagersChanged: (ids) => changed = ids),
    );
    await tester.pumpAndSettle();

    // The directory answered nothing for this id; the chip falls back to it
    // rather than disappearing, because a keeper nobody can see is worse than
    // one shown as an id.
    expect(find.text('gone'), findsOneWidget);

    await tester.tap(find.byTooltip('common.remove'));
    await tester.pumpAndSettle();

    expect(changed, isEmpty);
  });
}

/// A directory that knows one person, so a chip can be read as a name.
///
/// Implemented rather than extended: the card asks it exactly one question, and
/// a real repository would want an ApiClient this test has no use for.
class _FakeUsers implements UserRepository {
  @override
  Future<List<DirectoryUser>> usersByIds(List<String> ids) async => [
    for (final id in ids)
      if (id == 'u-1')
        const DirectoryUser(
          id: 'u-1',
          username: 'nina',
          displayName: 'Nina Keeper',
        ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
