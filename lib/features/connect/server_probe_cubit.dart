import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/core_models.dart' show ServerProbe;
import '../../core/repositories/meta_repository.dart';

/// The server manager's reachability checks: the ping on every saved server
/// and the connection test before one is added.
///
/// Holds no state of its own: each row and the add page keep what their probe
/// answered.
class ServerProbeCubit extends Cubit<void> {
  ServerProbeCubit(this._meta) : super(null);

  final MetaRepository _meta;

  /// What [url] answered, or null when nothing did.
  Future<ServerProbe?> probe(String url) => _meta.probeServer(url);
}
