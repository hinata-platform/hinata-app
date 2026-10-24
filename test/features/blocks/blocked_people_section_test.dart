import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/blocks/blocked_people_section.dart';
import 'package:hinata/features/blocks/hidden_content_cubit.dart';

import '../../support/recording_fake.dart';
import 'block_fakes.dart';

/// Settings › Privacy › Blocked people (HIN-168): the list, lifting a block
/// from it, and the empty state.
///
/// Widget tests render raw i18n keys, so the assertions look for keys.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  final jonas = BlockedPerson(
    id: 'jonas',
    displayName: 'Jonas Becker',
    blockedAt: DateTime.utc(2026, 10, 23, 9),
  );
  const tomas = BlockedPerson(id: 'tomas', displayName: 'Tomáš Horák');

  Future<FakeAccountRepository> pump(
    WidgetTester tester,
    List<BlockedPerson> people, {
    int? total,
  }) async {
    final account = FakeAccountRepository();
    final hidden = await hiddenContent(
      account,
      blocked: {for (final person in people) person.id},
    );
    addTearDown(hidden.close);
    account.answer<({List<BlockedPerson> items, int total})>(#blocksPage, (
      items: people,
      total: total ?? people.length,
    ));
    await tester.pumpWidget(
      RepositoryProvider<AccountRepository>.value(
        value: account,
        child: BlocProvider<HiddenContentCubit>.value(
          value: hidden,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: BlockedPeopleSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return account;
  }

  testWidgets('lists who one blocks, newest first', (tester) async {
    final account = await pump(tester, [jonas, tomas]);
    expect(find.text('Jonas Becker'), findsOneWidget);
    expect(find.text('Tomáš Horák'), findsOneWidget);
    expect(find.text('blocks.list.since'), findsOneWidget);
    expect(
      account.callTo(#blocksPage),
      invoked(#blocksPage, named: {#page: 0, #size: 25}),
    );
  });

  testWidgets('lifting a block drops the row and unfolds the person', (
    tester,
  ) async {
    final account = await pump(tester, [jonas, tomas]);
    account.answer<void>(#unblock, null);
    final hidden = tester
        .element(find.byType(BlockedPeopleSection))
        .read<HiddenContentCubit>();

    await tester.tap(find.text('blocks.list.unblock').first);
    await tester.pump();

    expect(account.callTo(#unblock), invoked(#unblock, positional: ['jonas']));
    expect(find.text('Jonas Becker'), findsNothing);
    expect(find.text('Tomáš Horák'), findsOneWidget);
    expect(hidden.state.blocks('jonas'), isFalse);
    expect(hidden.state.blocks('tomas'), isTrue);
    // Let the toast run out.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('nobody blocked shows the empty state', (tester) async {
    await pump(tester, const []);
    expect(find.text('blocks.list.emptyTitle'), findsOneWidget);
    expect(find.text('blocks.list.unblock'), findsNothing);
  });

  testWidgets('more than a page offers the next one', (tester) async {
    await pump(tester, [jonas], total: 30);
    expect(find.text('blocks.list.more'), findsOneWidget);
  });

  testWidgets('the button says whose block it lifts', (tester) async {
    await pump(tester, [jonas]);
    expect(find.bySemanticsLabel('blocks.list.unblockLabel'), findsOneWidget);
  });
}
