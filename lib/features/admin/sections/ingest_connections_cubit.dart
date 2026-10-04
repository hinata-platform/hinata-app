import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/ingest_models.dart';
import '../../../core/repositories/admin_repository.dart';

/// What the e-mail-to-ticket connections card and its editor ask of the
/// server: the connections, the projects they can feed, the mailbox folders,
/// and every change to a connection.
///
/// Holds no state: the card keeps its list, its labels and its spinners, the
/// editor its form, as before. Failures pass through as the repository's
/// `ApiFailure`.
class IngestConnectionsCubit extends Cubit<void> {
  IngestConnectionsCubit(this._admin) : super(null);

  final AdminRepository _admin;

  Future<List<IngestConnection>> connections() => _admin.ingestConnections();

  /// One page of the projects a connection can feed, narrowed by [query].
  Future<({List<IngestProjectOption> items, int total})> projectOptions({
    String query = '',
    int page = 0,
    int size = 25,
  }) => _admin.ingestProjectOptions(query: query, page: page, size: size);

  Future<IngestConnection> create(IngestConnection connection) =>
      _admin.createIngestConnection(connection);

  Future<IngestConnection> update(IngestConnection connection) =>
      _admin.updateIngestConnection(connection);

  Future<void> delete(String id) => _admin.deleteIngestConnection(id);

  /// Reads the mailbox again; [createMissing] also re-creates tickets for
  /// mails that have none any more.
  Future<({int scanned, int updated, int created})> reprocess(
    String id, {
    bool createMissing = false,
  }) => _admin.reprocessIngestConnection(id, createMissing: createMissing);

  /// The folders of the mailbox the form describes, before it is saved.
  Future<List<String>> probeFolders({
    String? connectionId,
    required String host,
    required int port,
    required bool ssl,
    required String username,
    String? password,
  }) => _admin.probeIngestFolders(
    connectionId: connectionId,
    host: host,
    port: port,
    ssl: ssl,
    username: username,
    password: password,
  );
}
