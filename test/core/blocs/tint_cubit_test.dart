import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/theme_cubit.dart';
import 'package:hinata/core/blocs/tint_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/theme/tint_palette.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../support/timer_surface_fakes.dart';
import '../../support/tint_fakes.dart';

/// The tint lives on the account and is cached on the device (HIN-150). What
/// is worth pinning: the cache key never moves, a save shows at once and rolls
/// back on refusal, bursts collapse to one write, writes never overtake each
/// other, and a sign-out leaves nothing of the person behind.
void main() {
  late MemoryStorage storage;
  late FakeTintAccountRepository account;

  const tinted = TintPreferences(style: TintStyle.tinted, hue: 200, level: 60);
  const other = TintPreferences(style: TintStyle.tinted, hue: 20, level: 100);

  setUp(() {
    storage = MemoryStorage();
    HydratedBloc.storage = storage;
    account = FakeTintAccountRepository();
  });

  test('hydrates under a fixed key, from what a previous run wrote', () async {
    storage.values['TintCubit'] = {
      'tint': {'style': 'TINTED', 'hue': 200, 'level': 60},
    };
    final cubit = TintCubit(account);
    expect(cubit.state.preferences, tinted);
    expect(cubit.storagePrefix, 'TintCubit');
    await cubit.close();
  });

  test('leaves the theme cubit\'s storage untouched', () async {
    storage.values['ThemeCubit'] = {'mode': 'dark'};
    final cubit = TintCubit(account);
    await cubit.commit(tinted);
    expect(storage.values['ThemeCubit'], {'mode': 'dark'});
    expect(ThemeCubit().state, ThemeMode.dark);
    await cubit.close();
  });

  test('adopt with the same preferences does not emit', () async {
    final cubit = TintCubit(account);
    var emits = 0;
    final sub = cubit.stream.listen((_) => emits++);
    cubit.adopt(TintPreferences.standard);
    cubit.adopt(tinted);
    cubit.adopt(tinted);
    await Future<void>.delayed(Duration.zero);
    expect(emits, 1);
    await sub.cancel();
    await cubit.close();
  });

  test(
    'a collected burst moves only the preview, then shows and writes once',
    () async {
      final cubit = TintCubit(account);
      final futures = <Future<bool>>[];
      for (var hue = 1; hue <= 5; hue++) {
        final next = TintPreferences(
          style: TintStyle.tinted,
          hue: hue,
          level: 100,
        );
        futures.add(cubit.commit(next, collect: true));
        // Nothing app-wide yet: a held arrow key must not rebuild the app
        // thirty times a second. The preview follows at once.
        expect(cubit.state.preferences, TintPreferences.standard);
        expect(cubit.previewPalette.value, same(TintPalette.of(next)));
      }
      expect(account.saved, isEmpty);
      expect(await Future.wait(futures), everyElement(isTrue));
      expect(cubit.state.preferences.hue, 5);
      expect(account.saved, hasLength(1));
      expect(account.saved.single.hue, 5);
      await cubit.close();
    },
  );

  test('commit without collect writes at once', () async {
    final cubit = TintCubit(account);
    expect(await cubit.commit(tinted), isTrue);
    expect(account.saved, [tinted]);
    await cubit.close();
  });

  test('commit rolls back to the confirmed value on refusal', () async {
    final cubit = TintCubit(account);
    await cubit.commit(tinted);
    account.refuse = true;
    expect(await cubit.commit(other), isFalse);
    expect(cubit.state.preferences, tinted);
    await cubit.close();
  });

  test('writes run one after another, the newest wins', () async {
    final cubit = TintCubit(account);
    final gate = Completer<void>();
    account.gate = gate.future;
    final first = cubit.commit(tinted);
    final second = cubit.commit(other);
    await Future<void>.delayed(Duration.zero);
    expect(account.saved, [tinted]);
    gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(account.saved, [tinted, other]);
    expect(cubit.state.preferences, other);
    await cubit.close();
  });

  test('a queued write that is refused answers false', () async {
    final cubit = TintCubit(account);
    final gate = Completer<void>();
    account.gate = gate.future;
    final first = cubit.commit(tinted);
    final second = cubit.commit(other);
    await Future<void>.delayed(Duration.zero);
    account.refuse = true;
    gate.complete();
    expect(await first, isFalse);
    expect(await second, isFalse);
    expect(cubit.state.preferences, tinted);
    await cubit.close();
  });

  test(
    'going back to the confirmed value while a write is out still writes',
    () async {
      final cubit = TintCubit(account);
      await cubit.commit(tinted);
      final gate = Completer<void>();
      account.gate = gate.future;
      final away = cubit.commit(other);
      final back = cubit.commit(tinted);
      gate.complete();
      await Future.wait([away, back]);
      expect(account.saved, [tinted, other, tinted]);
      expect(cubit.state.preferences, tinted);
      await cubit.close();
    },
  );

  test('reset drops the answer of a request that is still out', () async {
    final cubit = TintCubit(account);
    final gate = Completer<void>();
    account.gate = gate.future;
    final pending = cubit.commit(tinted);
    cubit.reset();
    gate.complete();
    expect(await pending, isFalse);
    expect(cubit.state.preferences, TintPreferences.standard);
    // The next person's refused save falls back to the standard, not to the
    // previous person's colour.
    account.refuse = true;
    await cubit.commit(other);
    expect(cubit.state.preferences, TintPreferences.standard);
    await cubit.close();
  });

  test('the preview starts on what was hydrated', () async {
    storage.values['TintCubit'] = {
      'tint': {'style': 'TINTED', 'hue': 200, 'level': 60},
    };
    final cubit = TintCubit(account);
    expect(cubit.previewPalette.value, same(cubit.state.palette));
    await cubit.close();
  });

  test('reset cancels a pending save and returns to the standard', () async {
    final cubit = TintCubit(account);
    final pending = cubit.commit(tinted, collect: true);
    cubit.reset();
    expect(await pending, isFalse);
    expect(account.saved, isEmpty);
    expect(cubit.state.preferences, TintPreferences.standard);
    expect(storage.values['TintCubit'], {
      'tint': {'style': 'DEFAULT', 'hue': 79, 'level': 100},
    });
    await cubit.close();
  });

  test(
    'copyWith keeps the palette and the themes for equal preferences',
    () async {
      final cubit = TintCubit(account);
      await cubit.commit(tinted);
      final before = cubit.state;
      cubit.adopt(tinted);
      expect(identical(cubit.state.palette, before.palette), isTrue);
      expect(identical(cubit.state.lightTheme, before.lightTheme), isTrue);
      expect(cubit.state.palette, same(TintPalette.of(tinted)));
      expect(
        cubit.state.lightTheme.colorScheme.secondary,
        cubit.state.palette.accent,
      );
      await cubit.close();
    },
  );

  test('preview updates the notifier and emits nothing', () async {
    final cubit = TintCubit(account);
    var emits = 0;
    final sub = cubit.stream.listen((_) => emits++);
    cubit.preview(tinted);
    await Future<void>.delayed(Duration.zero);
    expect(emits, 0);
    expect(cubit.previewPalette.value, same(TintPalette.of(tinted)));
    expect(account.saved, isEmpty);
    await sub.cancel();
    await cubit.close();
  });
}
