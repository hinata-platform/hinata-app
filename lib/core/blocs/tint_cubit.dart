import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../models/account_models.dart';
import '../repositories/account_repository.dart';
import '../theme/app_theme.dart';
import '../theme/tint_palette.dart';

/// The tint and everything derived from it, built once per preferences: the
/// palette and the two Material themes. `MaterialApp` animates between
/// `ThemeData` instances that are not `==`, and a theme built fresh on every
/// build never is (`ColorScheme.fromSeed`, new closures), so a rebuild that
/// changed nothing used to start a 200 ms cross-fade of the whole tree. Held
/// here, an unchanged state hands back the same instances.
///
/// Equal on [preferences] alone: the rest is a function of them.
class TintState extends Equatable {
  const TintState._(
    this.preferences,
    this.palette,
    this.lightTheme,
    this.darkTheme,
  );

  factory TintState.of(TintPreferences preferences) {
    final palette = TintPalette.of(preferences);
    return TintState._(
      preferences,
      palette,
      AppTheme.light(palette: palette),
      AppTheme.dark(palette: palette),
    );
  }

  final TintPreferences preferences;
  final TintPalette palette;
  final ThemeData lightTheme;
  final ThemeData darkTheme;

  @override
  List<Object?> get props => [preferences];
}

/// The colour this person gives the app (HIN-150), as one live value.
///
/// Lives on the account, so every device agrees, and is hydrated on the
/// device so the first frame already wears it. Beside [ThemeCubit], not
/// inside it: light/dark is the device's and only ever local, the tint is
/// the person's and written to the server, and the two have nothing to say
/// to each other.
///
/// Writes follow [TimePreferencesCubit]: optimistic, collected into one
/// request per burst, rolled back to the last value the server confirmed
/// when refused. On top of that they run one after another, because a
/// slider can finish a second burst while the first request is still out,
/// and two requests in flight can land in either order.
class TintCubit extends HydratedCubit<TintState> {
  TintCubit(this._account) : super(TintState.of(TintPreferences.standard));

  final AccountRepository _account;

  /// Fixed: the default is `runtimeType.toString()`, which a web release
  /// build minifies and a rename would change, and either loses the cache.
  @override
  String get storagePrefix => 'TintCubit';

  /// What the sliders show while they are being dragged. Only the preview
  /// surfaces listen; the app itself follows [commit].
  final previewPalette = ValueNotifier<TintPalette>(TintPalette.standard);

  /// How long a burst of keyboard or screen-reader steps is collected before
  /// anything is written or shown app-wide. A held arrow key fires thirty
  /// steps a second; thirty theme changes a second is not a feature.
  static const Duration settle = Duration(milliseconds: 450);

  TintPreferences _confirmed = TintPreferences.standard;
  Timer? _collect;
  Completer<bool>? _collecting;
  Future<bool>? _inFlight;
  bool _again = false;

  /// Takes preferences that arrived with an account read somebody else made.
  void adopt(TintPreferences preferences) {
    _confirmed = preferences;
    _show(preferences);
  }

  /// Shows [preferences] on the preview surfaces only.
  void preview(TintPreferences preferences) {
    previewPalette.value = TintPalette.of(preferences);
  }

  /// Applies [preferences] to the app at once and writes them to the account.
  /// With [collect], the write (and the app-wide change) waits [settle] for
  /// more of the same.
  Future<bool> commit(TintPreferences preferences, {bool collect = false}) {
    if (preferences == _confirmed && _collecting == null) {
      _show(preferences);
      return Future.value(true);
    }
    if (!collect) {
      _collect?.cancel();
      _collect = null;
      _show(preferences);
      final waiting = _collecting;
      _collecting = null;
      final result = _write();
      if (waiting != null) unawaited(result.then(waiting.complete));
      return result;
    }
    _show(preferences);
    _collect?.cancel();
    final waiting = _collecting ??= Completer<bool>();
    _collect = Timer(settle, () {
      _collecting = null;
      _collect = null;
      unawaited(_write().then(waiting.complete));
    });
    return waiting.future;
  }

  /// Back to the standard, with nothing left of the person: at sign-out,
  /// account deletion and a server switch. A pending save answers false.
  void reset() {
    _collect?.cancel();
    _collect = null;
    _collecting?.complete(false);
    _collecting = null;
    _again = false;
    _confirmed = TintPreferences.standard;
    _show(TintPreferences.standard);
  }

  void _show(TintPreferences preferences) {
    if (preferences != state.preferences) emit(TintState.of(preferences));
    previewPalette.value = state.palette;
  }

  Future<bool> _write() {
    final running = _inFlight;
    if (running != null) {
      // One more after this one, with whatever is newest by then.
      _again = true;
      return running.then((_) => _inFlight ?? Future.value(true));
    }
    final request = _send();
    _inFlight = request;
    return request;
  }

  Future<bool> _send() async {
    final asked = state.preferences;
    var ok = true;
    try {
      final saved = await _account.updateMyProfile(tint: asked);
      _confirmed = saved.tint;
      if (asked == state.preferences) _show(_confirmed);
    } catch (_) {
      ok = false;
      if (asked == state.preferences) _show(_confirmed);
    }
    _inFlight = null;
    if (_again && isClosed == false) {
      _again = false;
      if (state.preferences != _confirmed) {
        final next = _send();
        _inFlight = next;
        return next;
      }
    }
    return ok;
  }

  @override
  TintState? fromJson(Map<String, dynamic> json) {
    final tint = json['tint'];
    if (tint is! Map<String, dynamic>) return null;
    final preferences = TintPreferences.fromJson(tint);
    _confirmed = preferences;
    return TintState.of(preferences);
  }

  @override
  Map<String, dynamic>? toJson(TintState state) => {
    'tint': state.preferences.toJson(),
  };

  @override
  Future<void> close() {
    _collect?.cancel();
    previewPalette.dispose();
    return super.close();
  }
}
