import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/repositories/meta_repository.dart';

/// The first-run wizard's one request: the organisation and its first admin.
///
/// Holds no state: the form keeps its fields, spinner and error, as before.
/// A refusal passes through as the repository's `ApiFailure`.
class SetupCubit extends Cubit<void> {
  SetupCubit(this._meta) : super(null);

  final MetaRepository _meta;

  Future<void> complete({
    required String organizationName,
    required String adminEmail,
    required String adminUsername,
    required String adminDisplayName,
    required String adminPassword,
  }) => _meta.completeSetup(
    organizationName: organizationName,
    adminEmail: adminEmail,
    adminUsername: adminUsername,
    adminDisplayName: adminDisplayName,
    adminPassword: adminPassword,
  );
}
