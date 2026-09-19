import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/my_absences_cubit.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/models/absence_request_models.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';

/// An [AppConfigBloc] holding one fixed answer about the server, for the
/// screens that ask whether absence management is switched on.
///
/// The real bloc reads `/api/v1/meta` and needs a repository and storage to do
/// it; neither is touched here, because the state never changes. Extending it
/// rather than faking the interface keeps `context.select<AppConfigBloc, …>`
/// working, which is how every screen asks.
class FakeAppConfig extends AppConfigBloc {
  FakeAppConfig({bool absenceManagement = true})
    : _fixed = AppConfigState(
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          featureFlags: {
            PlatformFlags.advancedTimeTracking: true,
            PlatformFlags.absenceManagement: absenceManagement,
          },
        ),
      ),
      super(repository: _UnusedMeta(), storage: _UnusedStorage());

  final AppConfigState _fixed;

  @override
  AppConfigState get state => _fixed;
}

class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A [MyAbsencesCubit] that already knows the reader's absence management: the
/// types, the balances and the requests that wait for a decision.
///
/// The real one reads four routes; a screen test states the answer instead, so
/// a case about a hatched day is one line. [ensureLoaded] counts, so a test can
/// still ask whether a screen asked at all.
class FakeMyAbsencesCubit extends MyAbsencesCubit {
  FakeMyAbsencesCubit({
    List<AbsenceRequest> pending = const [],
    List<AbsenceType> types = const [],
    AbsenceBalances? balances,
    bool managed = true,
    bool keeper = false,
  }) : super(_UnusedAbsences()) {
    emit(
      MyAbsencesState(
        managed: managed,
        loaded: true,
        pending: pending,
        types: types,
        balances: balances,
        keeper: keeper,
      ),
    );
  }

  int loads = 0;

  @override
  Future<void> ensureLoaded({required bool managed}) async {
    loads++;
  }

  @override
  Future<void> changed() async =>
      emit(state.copyWith(revision: state.revision + 1));
}

class _UnusedAbsences implements AbsenceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
