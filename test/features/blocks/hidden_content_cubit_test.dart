import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/blocks/hidden_content_cubit.dart';

import '../../support/recording_fake.dart';

/// What the reader folds away (HIN-168): read once per sign-in, changed by
/// every block and unblock, forgotten on sign-out.
void main() {
  late FakeAccountRepository account;

  setUp(() => account = FakeAccountRepository());

  HiddenContentCubit cubit({bool enabled = true}) {
    final hidden = HiddenContentCubit(account, enabled: () => enabled);
    addTearDown(hidden.close);
    return hidden;
  }

  test('folds what the people one blocks write, once loaded', () async {
    account.answer<Set<String>>(#blockedIds, {'jonas'});
    final hidden = cubit();
    await hidden.load();
    expect(hidden.state.blocks('jonas'), isTrue);
    expect(hidden.state.folds(authorId: 'jonas', contentId: 'c1'), isTrue);
    expect(hidden.state.folds(authorId: 'lena', contentId: 'c2'), isFalse);
  });

  test('a server without blocking is not asked', () async {
    final hidden = cubit(enabled: false);
    await hidden.load();
    expect(account.calls, isEmpty);
    expect(hidden.state, const HiddenContentState());
  });

  test('a failed read folds nothing', () async {
    account.fail(#blockedIds, failure);
    final hidden = cubit();
    await hidden.load();
    expect(hidden.state.blocked, isEmpty);
  });

  test('blocking folds at once, and lifting it unfolds', () async {
    account
      ..answer<void>(#block, null)
      ..answer<void>(#unblock, null);
    final hidden = cubit();
    await hidden.block('jonas');
    expect(account.only, invoked(#block, positional: ['jonas']));
    expect(hidden.state.folds(authorId: 'jonas', contentId: 'c1'), isTrue);

    await hidden.unblock('jonas');
    expect(account.callTo(#unblock), invoked(#unblock, positional: ['jonas']));
    expect(hidden.state.blocks('jonas'), isFalse);
  });

  test('a refused block changes nothing and comes back unchanged', () async {
    account.fail(#block, failure);
    final hidden = cubit();
    await expectLater(hidden.block('jonas'), throwsFailure);
    expect(hidden.state.blocks('jonas'), isFalse);
  });

  test('showing one folded comment leaves the others folded', () async {
    account.answer<Set<String>>(#blockedIds, {'jonas'});
    final hidden = cubit();
    await hidden.load();
    hidden.reveal('c1');
    expect(hidden.state.folds(authorId: 'jonas', contentId: 'c1'), isFalse);
    expect(hidden.state.folds(authorId: 'jonas', contentId: 'c2'), isTrue);
  });

  test('signing out forgets the blocks and what was shown anyway', () async {
    account.answer<Set<String>>(#blockedIds, {'jonas'});
    final hidden = cubit();
    await hidden.load();
    hidden.reveal('c1');
    hidden.reset();
    expect(hidden.state, const HiddenContentState());
  });

  test(
    'an answer for the account that left folds nothing for the next',
    () async {
      final pending = Completer<Set<String>>();
      account.answerWith(#blockedIds, (_) => pending.future);
      final hidden = cubit();
      final load = hidden.load();
      hidden.reset();
      pending.complete({'jonas'});
      await load;
      expect(hidden.state.blocked, isEmpty);
    },
  );
}
