import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/moderation_case_models.dart';
import '../../../core/repositories/moderation_repository.dart';

/// The numbers on the moderation page and its badge in the settings
/// (HIN-174): read when the page opens and once a minute while it is open,
/// paused while the app is in the background. Notifications bring the rest.
///
/// Null until the first answer. A failed read keeps the numbers shown: a badge
/// that blinks out on a dropped connection says nothing true.
class ModerationSummaryCubit extends Cubit<ModerationSummary?> {
  ModerationSummaryCubit(
    this._moderation, {
    this.every = const Duration(seconds: 60),
  }) : super(null);

  final ModerationRepository _moderation;

  /// How often the numbers are read again while running.
  final Duration every;

  Timer? _timer;

  bool get running => _timer != null;

  /// Reads now and then every [every], until [pause] or [close].
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  /// Reads the numbers once, as after a step on a case.
  Future<void> refresh() async {
    try {
      final summary = await _moderation.summary();
      if (!isClosed) emit(summary);
    } catch (_) {
      // What is shown stands.
    }
  }

  @override
  Future<void> close() {
    pause();
    return super.close();
  }
}
