import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/repositories/moderation_repository.dart';

enum NoticeStatus { loading, ready, gone, failure }

/// The moderation's notice about the reader's own content, and an appeal
/// against it (HIN-173).
class NoticeState extends Equatable {
  const NoticeState({
    this.status = NoticeStatus.loading,
    this.statement,
    this.errorKey,
    this.appealing = false,
    this.appealErrorKey,
  });

  final NoticeStatus status;
  final Statement? statement;

  /// Why the notice could not be read.
  final String? errorKey;

  final bool appealing;

  /// Why the appeal was not taken, in the server's words.
  final String? appealErrorKey;

  NoticeState copyWith({
    NoticeStatus? status,
    Statement? statement,
    String? Function()? errorKey,
    bool? appealing,
    String? Function()? appealErrorKey,
  }) => NoticeState(
    status: status ?? this.status,
    statement: statement ?? this.statement,
    errorKey: errorKey == null ? this.errorKey : errorKey(),
    appealing: appealing ?? this.appealing,
    appealErrorKey: appealErrorKey == null
        ? this.appealErrorKey
        : appealErrorKey(),
  );

  @override
  List<Object?> get props => [
    status,
    statement,
    errorKey,
    appealing,
    appealErrorKey,
  ];
}

class NoticeCubit extends Cubit<NoticeState> {
  NoticeCubit(this._moderation, this.caseId) : super(const NoticeState());

  final ModerationRepository _moderation;
  final String caseId;

  /// Reads the notice. Gone answers 404: the time to keep it ran out, or it
  /// is not the reader's.
  Future<void> load() async {
    emit(state.copyWith(status: NoticeStatus.loading, errorKey: () => null));
    try {
      final statement = await _moderation.notice(caseId);
      emit(state.copyWith(status: NoticeStatus.ready, statement: statement));
    } on ApiFailure catch (failure) {
      emit(
        state.copyWith(
          status: failure.statusCode == 404
              ? NoticeStatus.gone
              : NoticeStatus.failure,
          errorKey: () => failure.message,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: NoticeStatus.failure,
          errorKey: () => 'errors.unexpected',
        ),
      );
    }
  }

  /// Appeals with [text]; true once it is in. A refusal stays in the sheet,
  /// and one that says the appeal is closed or already in reads the notice
  /// again, so the page shows what holds now.
  Future<bool> appeal(String text) async {
    final words = text.trim();
    if (words.isEmpty || state.appealing) return false;
    emit(state.copyWith(appealing: true, appealErrorKey: () => null));
    try {
      final statement = await _moderation.appeal(caseId, words);
      emit(state.copyWith(appealing: false, statement: statement));
      return true;
    } on ApiFailure catch (failure) {
      emit(
        state.copyWith(appealing: false, appealErrorKey: () => failure.message),
      );
      if (failure.statusCode == 409) await _refresh();
      return false;
    } catch (_) {
      emit(
        state.copyWith(
          appealing: false,
          appealErrorKey: () => 'errors.unexpected',
        ),
      );
      return false;
    }
  }

  /// Reads the notice again without leaving the page.
  Future<void> _refresh() async {
    try {
      final statement = await _moderation.notice(caseId);
      if (!isClosed) emit(state.copyWith(statement: statement));
    } catch (_) {
      // The page keeps what it showed.
    }
  }
}
