import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/time_privacy_cubit.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';

/// The cubit behind the privacy sheet and the first-use notice (HIN-89).
///
/// What it has to get right is small and easy to get wrong: a read that fails
/// must say so instead of leaving a sheet spinning, a refresh that fails must not
/// throw away the notice already held, and the first-use offer happens once.
void main() {
  const notice = TimePrivacy(notice: '## Deine Arbeitszeit');

  test('a read that fails answers false and holds nothing', () async {
    final cubit = TimePrivacyCubit(_PrivacyRepository(failures: 1));
    addTearDown(cubit.close);

    expect(await cubit.ensureLoaded(), isFalse);
    expect(cubit.state, isNull);

    expect(await cubit.ensureLoaded(), isTrue);
    expect(cubit.state, notice);
  });

  test('a refresh that fails keeps the notice read before', () async {
    final repository = _PrivacyRepository();
    final cubit = TimePrivacyCubit(repository);
    addTearDown(cubit.close);
    await cubit.ensureLoaded();

    repository.failures = 1;

    expect(await cubit.refresh(), isTrue);
    expect(cubit.state, notice);
  });

  test('calls while a read is on its way join it', () async {
    final repository = _PrivacyRepository();
    final cubit = TimePrivacyCubit(repository);
    addTearDown(cubit.close);

    await Future.wait([
      cubit.ensureLoaded(),
      cubit.ensureLoaded(),
      cubit.refresh(),
    ]);

    expect(repository.reads, 1);
  });

  test('the first-use notice is offered once per session', () async {
    final cubit = TimePrivacyCubit(_PrivacyRepository());
    addTearDown(cubit.close);
    expect(cubit.takeFirstUseOffer(), isFalse, reason: 'nothing read yet');

    await cubit.ensureLoaded();
    expect(cubit.takeFirstUseOffer(), isTrue);
    expect(cubit.takeFirstUseOffer(), isFalse);

    cubit.reset();
    expect(cubit.state, isNull);
    await cubit.ensureLoaded();
    expect(
      cubit.takeFirstUseOffer(),
      isTrue,
      reason: 'the next sign-in may be somebody else',
    );
  });

  test('confirming answers whether the server took it', () async {
    final repository = _PrivacyRepository();
    final cubit = TimePrivacyCubit(repository);
    addTearDown(cubit.close);
    await cubit.ensureLoaded();

    expect(await cubit.acknowledge(), isTrue);
    expect(cubit.state!.acknowledged, isTrue);
    expect(cubit.takeFirstUseOffer(), isFalse);

    repository.failures = 1;
    expect(await cubit.acknowledge(), isFalse);
  });
}

class _PrivacyRepository implements TimeRepository {
  _PrivacyRepository({this.failures = 0});

  /// How many of the next calls fail, as a dropped connection would.
  int failures;
  int reads = 0;

  void _maybeFail() {
    if (failures > 0) {
      failures--;
      throw Exception('offline');
    }
  }

  @override
  Future<TimePrivacy> privacy() async {
    reads++;
    _maybeFail();
    return const TimePrivacy(notice: '## Deine Arbeitszeit');
  }

  @override
  Future<TimePrivacy> acknowledgePrivacy() async {
    _maybeFail();
    return TimePrivacy(
      notice: '## Deine Arbeitszeit',
      acknowledgedAt: DateTime.utc(2026, 9, 13),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
