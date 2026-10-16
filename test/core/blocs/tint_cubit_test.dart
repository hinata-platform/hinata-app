import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/theme_cubit.dart';
import 'package:hinata/core/blocs/tint_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/theme/tint_palette.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

/// The tint lives on the account and is cached on the device (HIN-150). What
/// is worth pinning: the cache key never moves, a save shows at once and rolls
/// back on refusal, bursts collapse to one write, writes never overtake each
/// other, and a sign-out leaves nothing of the person behind.
void main() {
  late _MemoryStorage storage;
  late _FakeAccountRepository account;

  const tinted = TintPreferences(style: TintStyle.tinted, hue: 200, level: 60);
  const other = TintPreferences(style: TintStyle.tinted, hue: 20, level: 100);

  setUp(() {
    storage = _MemoryStorage();
    HydratedBloc.storage = storage;
    account = _FakeAccountRepository();
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

  test('commit is optimistic and a collected burst is one write', () async {
    final cubit = TintCubit(account);
    final futures = <Future<bool>>[];
    for (var hue = 1; hue <= 5; hue++) {
      futures.add(
        cubit.commit(
          TintPreferences(style: TintStyle.tinted, hue: hue, level: 100),
          collect: true,
        ),
      );
      expect(cubit.state.preferences.hue, hue);
    }
    expect(account.saved, isEmpty);
    await Future.wait(futures);
    expect(account.saved, hasLength(1));
    expect(account.saved.single.hue, 5);
    await cubit.close();
  });

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
    await Future.wait([first, second]);
    expect(account.saved, [tinted, other]);
    expect(cubit.state.preferences, other);
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

class _MemoryStorage implements Storage {
  final Map<String, dynamic> values = {};

  @override
  dynamic read(String key) => values[key];

  @override
  Future<void> write(String key, dynamic value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<void> close() async {}
}

class _FakeAccountRepository implements AccountRepository {
  bool refuse = false;
  Future<void>? gate;
  final List<TintPreferences> saved = [];

  @override
  Future<Me> updateMyProfile({
    String? displayName,
    String? title,
    String? pronouns,
    String? locale,
    String? timezone,
    TimePreferences? timePreferences,
    TintPreferences? tint,
  }) async {
    if (refuse) throw ApiFailure('nope');
    saved.add(tint!);
    await gate;
    return _me(tint);
  }

  Me _me(TintPreferences tint) => Me(
    id: 'u1',
    displayName: 'Me',
    username: 'me',
    email: 'me@example.org',
    emailVerified: true,
    origin: AuthOrigin.local,
    roles: const ['MEMBER'],
    active: true,
    twoFactor: const TwoFactor(
      enabled: false,
      method: 'TOTP',
      recoveryRemaining: 0,
    ),
    notificationPreferences: NotifPrefs.fromJson(const {}),
    tint: tint,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
