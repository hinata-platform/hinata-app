import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/organization/time_tracking/time_tags_cubit.dart';

/// The organisation's time tags: the catalogue and every change to it.
void main() {
  late _FakeTime time;
  late TimeTagsCubit cubit;

  setUp(() {
    time = _FakeTime();
    cubit = TimeTagsCubit(time);
  });

  tearDown(() => cubit.close());

  test('a page carries the search and asks for the counts', () async {
    final page = await cubit.tags(
      query: 'meet',
      page: 1,
      size: 25,
      withUsage: true,
    );

    expect(page.items.single.name, 'Meeting');
    expect(time.calls.single, 'tags meet 1 25 true');
  });

  test('create, rename and delete', () async {
    expect((await cubit.create('Meeting')).name, 'Meeting');
    expect((await cubit.rename('t1', 'Call')).name, 'Call');
    await cubit.delete('t1');

    expect(time.calls, ['create Meeting', 'update t1 Call', 'delete t1']);
  });

  test('a refusal passes through', () async {
    time.fail = true;

    await expectLater(cubit.delete('t1'), throwsA(isA<ApiFailure>()));
  });
}

class _FakeTime implements TimeRepository {
  bool fail = false;
  final List<String> calls = [];

  @override
  Future<PageResult<TimeTag>> tags({
    String? query,
    int page = 0,
    int size = 50,
    bool withUsage = false,
  }) async {
    calls.add('tags $query $page $size $withUsage');
    return (items: const [TimeTag(id: 't1', name: 'Meeting')], total: 1);
  }

  @override
  Future<TimeTag> createTag(String name, {int? hue}) async {
    calls.add('create $name');
    return TimeTag(id: 't1', name: name);
  }

  @override
  Future<TimeTag> updateTag(String id, {String? name, int? hue}) async {
    calls.add('update $id $name');
    return TimeTag(id: id, name: name ?? '');
  }

  @override
  Future<void> deleteTag(String id) async {
    if (fail) throw ApiFailure('error.time.tagInUse', statusCode: 409);
    calls.add('delete $id');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
