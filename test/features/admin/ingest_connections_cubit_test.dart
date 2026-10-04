import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/ingest_models.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/features/admin/sections/ingest_connections_cubit.dart';

/// The e-mail-to-ticket connections: what the card and its editor ask, sent on
/// as asked and answered as the server answered.
void main() {
  late _FakeAdmin admin;
  late IngestConnectionsCubit cubit;

  setUp(() {
    admin = _FakeAdmin();
    cubit = IngestConnectionsCubit(admin);
  });

  tearDown(() => cubit.close());

  test('the list and the project options', () async {
    expect(await cubit.connections(), same(admin.list));

    final options = await cubit.projectOptions(
      query: 'web',
      page: 2,
      size: 100,
    );
    expect(options.items.single.id, 'p1');
    expect(admin.calls.last, 'projects web 2 100');
  });

  test('create, update, delete and reprocess', () async {
    const draft = IngestConnection(id: 'c1', host: 'imap.example.org');

    expect(await cubit.create(draft), same(draft));
    expect(await cubit.update(draft), same(draft));
    await cubit.delete('c1');
    final result = await cubit.reprocess('c1', createMissing: true);

    expect(result.created, 1);
    expect(admin.calls, [
      'create c1',
      'update c1',
      'delete c1',
      'reprocess c1 true',
    ]);
  });

  test('a folder probe carries the form as it stands', () async {
    final folders = await cubit.probeFolders(
      connectionId: 'c1',
      host: 'imap.example.org',
      port: 993,
      ssl: true,
      username: 'tickets',
      password: 'secret',
    );

    expect(folders, ['INBOX']);
    expect(
      admin.calls.single,
      'probe c1 imap.example.org 993 true tickets secret',
    );
  });

  test('a refusal passes through', () async {
    admin.fail = true;

    await expectLater(cubit.connections(), throwsA(isA<ApiFailure>()));
  });
}

class _FakeAdmin implements AdminRepository {
  bool fail = false;
  final List<String> calls = [];
  final List<IngestConnection> list = [const IngestConnection(id: 'c1')];

  @override
  Future<List<IngestConnection>> ingestConnections() async {
    if (fail) throw ApiFailure('error.forbidden', statusCode: 403);
    return list;
  }

  @override
  Future<({List<IngestProjectOption> items, int total})> ingestProjectOptions({
    String query = '',
    int page = 0,
    int size = 25,
  }) async {
    calls.add('projects $query $page $size');
    return (
      items: const [
        IngestProjectOption(
          id: 'p1',
          key: 'WEB',
          name: 'Web',
          color: '#AEC6F4',
        ),
      ],
      total: 1,
    );
  }

  @override
  Future<IngestConnection> createIngestConnection(
    IngestConnection connection,
  ) async {
    calls.add('create ${connection.id}');
    return connection;
  }

  @override
  Future<IngestConnection> updateIngestConnection(
    IngestConnection connection,
  ) async {
    calls.add('update ${connection.id}');
    return connection;
  }

  @override
  Future<void> deleteIngestConnection(String id) async {
    calls.add('delete $id');
  }

  @override
  Future<({int scanned, int updated, int created})> reprocessIngestConnection(
    String id, {
    bool createMissing = false,
  }) async {
    calls.add('reprocess $id $createMissing');
    return (scanned: 3, updated: 2, created: 1);
  }

  @override
  Future<List<String>> probeIngestFolders({
    String? connectionId,
    required String host,
    required int port,
    required bool ssl,
    required String username,
    String? password,
  }) async {
    calls.add('probe $connectionId $host $port $ssl $username $password');
    return ['INBOX'];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
