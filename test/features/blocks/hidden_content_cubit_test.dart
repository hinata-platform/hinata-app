import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/blocks/hidden_content_cubit.dart';

import '../../support/recording_fake.dart';

/// What the reader folds away (HIN-168, HIN-173): read once per sign-in,
/// changed by every block, unblock and report, forgotten on sign-out.
void main() {
  late FakeAccountRepository account;
  late FakeModerationRepository moderation;

  setUp(() {
    account = FakeAccountRepository();
    moderation = FakeModerationRepository()
      ..answer<Set<String>>(#reportedIds, const {});
  });

  HiddenContentCubit cubit({bool enabled = true}) {
    final hidden = HiddenContentCubit(
      account,
      moderation,
      enabled: () => enabled,
    );
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
    expect(moderation.calls, isEmpty);
    expect(hidden.state, const HiddenContentState());
  });

  test('waits for the server to say whether it knows blocking', () async {
    account.answer<Set<String>>(#blockedIds, {'jonas'});
    final known = Completer<bool>();
    final hidden = HiddenContentCubit(
      account,
      moderation,
      enabled: () => known.future,
    );
    addTearDown(hidden.close);

    final loading = hidden.load();
    await pumpEventQueue();
    expect(account.calls, isEmpty);

    known.complete(true);
    await loading;
    expect(hidden.state.blocks('jonas'), isTrue);
  });

  test(
    'an account that left before the server answered loads nothing',
    () async {
      account.answer<Set<String>>(#blockedIds, {'jonas'});
      final known = Completer<bool>();
      final hidden = HiddenContentCubit(
        account,
        moderation,
        enabled: () => known.future,
      );
      addTearDown(hidden.close);

      final loading = hidden.load();
      hidden.reset();
      known.complete(true);
      await loading;

      expect(account.calls, isEmpty);
      expect(moderation.calls, isEmpty);
    },
  );

  test('folds the comments one reported, and says why', () async {
    account.answer<Set<String>>(#blockedIds, {'jonas'});
    moderation.answer<Set<String>>(#reportedIds, {'c2'});
    final hidden = cubit();
    await hidden.load();

    expect(
      hidden.state.foldOf(authorId: 'lena', contentId: 'c2'),
      FoldReason.reported,
    );
    expect(
      hidden.state.foldOf(authorId: 'jonas', contentId: 'c2'),
      FoldReason.blocked,
    );
    expect(hidden.state.foldOf(authorId: 'lena', contentId: 'c3'), isNull);
  });

  test('one list failing keeps the other', () async {
    account.answer<Set<String>>(#blockedIds, {'jonas'});
    moderation.fail(#reportedIds, failure);
    final hidden = cubit();
    await hidden.load();
    expect(hidden.state.blocks('jonas'), isTrue);
    expect(hidden.state.reported, isEmpty);
  });

  test('a report folds the comment at once, also one shown anyway', () async {
    final hidden = cubit();
    hidden
      ..reveal('c1')
      ..noteReported('c1');
    expect(hidden.state.folds(authorId: 'lena', contentId: 'c1'), isTrue);
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
