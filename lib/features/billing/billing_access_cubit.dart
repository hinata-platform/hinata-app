import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/billing_models.dart';
import '../../core/repositories/billing_repository.dart';

/// What the reader may do with billing, read once per surface.
///
/// Null until known. A reader who may do nothing — or a server that could not
/// answer — ends at [BillingAccess.none], so a surface hides itself rather
/// than showing a spinner that never resolves.
class BillingAccessCubit extends Cubit<BillingAccess?> {
  BillingAccessCubit(this._billing) : super(null);

  /// Null where billing is off: there is nobody to ask, and nobody may.
  final BillingRepository? _billing;

  Future<void> load() async {
    final billing = _billing;
    if (billing == null) {
      if (!isClosed) emit(BillingAccess.none);
      return;
    }
    try {
      final access = await billing.access();
      if (!isClosed) emit(access);
    } on ApiFailure {
      if (!isClosed) emit(BillingAccess.none);
    }
  }
}
