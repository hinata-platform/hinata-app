import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/team_models.dart';
import '../../../core/repositories/team_repository.dart';

/// What the report filter sheet asks the server: the teams it can narrow to.
///
/// Holds no state: the sheet keeps the question it is building. Failures pass
/// through as the repository's `ApiFailure`.
class ReportFilterCubit extends Cubit<void> {
  ReportFilterCubit(this._teams) : super(null);

  final TeamRepository _teams;

  Future<List<Team>> teams() => _teams.teams();
}
