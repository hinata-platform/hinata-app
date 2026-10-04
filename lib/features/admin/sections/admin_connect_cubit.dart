import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/repositories/admin_repository.dart';

/// What Admin → Connect asks of the server: the enrolment state, the automated
/// handshake, the token enrolment and dropping the enrolment again.
///
/// Holds no state: the section keeps the status it shows, its spinners and its
/// polling timer, as before. Every call answers with the status the server
/// holds afterwards; failures pass through as the repository's `ApiFailure`.
class AdminConnectCubit extends Cubit<void> {
  AdminConnectCubit(this._admin) : super(null);

  final AdminRepository _admin;

  Future<Map<String, dynamic>> status() => _admin.connectStatus();

  Future<Map<String, dynamic>> startHandshake() =>
      _admin.connectHandshakeStart();

  Future<Map<String, dynamic>> cancelHandshake() =>
      _admin.connectHandshakeCancel();

  Future<Map<String, dynamic>> enroll(String token) =>
      _admin.connectEnroll(token);

  Future<Map<String, dynamic>> disconnect() => _admin.connectDisconnect();
}
