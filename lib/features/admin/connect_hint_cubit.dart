import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/repositories/admin_repository.dart';

/// Where this instance stands with Hinata Connect, for the one-time hint the
/// dashboard shows an admin (see `maybeShowConnectHint`).
///
/// Holds no state: the hint decides from one answer and remembers in storage.
/// Failures pass through as the repository's `ApiFailure`.
class ConnectHintCubit extends Cubit<void> {
  ConnectHintCubit(this._admin) : super(null);

  final AdminRepository _admin;

  /// The enrolment status: `enabled`, `enrolled`, `handshakePending`.
  Future<Map<String, dynamic>> connectStatus() => _admin.connectStatus();
}
