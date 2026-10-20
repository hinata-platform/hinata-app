import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/core/repositories/shift_repository.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:i18next/i18next.dart';

/// A [ShiftRepository] answering from fields the test sets, recording every
/// call by name.
class FakeShiftRepository implements ShiftRepository {
  final List<String> calls = [];

  PageResult<MyShift> mine = (items: const [], total: 0);
  List<PageResult<MyShift>>? minePages;
  MyShift? next;
  ShiftCalendar open = const ShiftCalendar();
  PageResult<ShiftEventSummary> eventPage = (items: const [], total: 0);
  ShiftEventDetail? eventDetail;
  ShiftDetail? shiftDetail;
  ShiftAssignResult? assignResult;
  MyShift? confirmed;
  ShiftAssignResult? releaseResult;
  ShiftPlanners plannerList = const ShiftPlanners();
  Object? failure;

  /// Holds every answer until completed, for loading states.
  Completer<void>? gate;

  String? lastProjectId;
  DateTime? lastFrom;
  DateTime? lastTo;

  Future<T> _answer<T>(String name, T Function() value) async {
    calls.add(name);
    if (gate != null) await gate!.future;
    final f = failure;
    if (f != null) throw f;
    return value();
  }

  @override
  Future<PageResult<MyShift>> myShifts({int page = 0, int size = 25}) =>
      _answer('myShifts:$page', () => minePages?[page] ?? mine);

  @override
  Future<MyShift?> nextShift() => _answer('next', () => next);

  @override
  Future<PageResult<ShiftEventSummary>> events({
    required DateTime from,
    required DateTime to,
    String? projectId,
    int page = 0,
    int size = 25,
  }) {
    lastProjectId = projectId;
    lastFrom = from;
    lastTo = to;
    return _answer('events:${projectId ?? 'all'}:$page', () => eventPage);
  }

  @override
  Future<ShiftEventDetail> event(String id) =>
      _answer('event:$id', () => eventDetail!);

  @override
  Future<ShiftDetail> shift(String id) =>
      _answer('shift:$id', () => shiftDetail!);

  @override
  Future<ShiftCalendar> openShifts({
    required DateTime from,
    required DateTime to,
    int limit = 3,
  }) => _answer('open:$limit', () => open);

  @override
  Future<ShiftAssignResult> selfAssign(String shiftId) =>
      _answer('selfAssign:$shiftId', () => assignResult!);

  @override
  Future<MyShift> confirm(String assignmentId) =>
      _answer('confirm:$assignmentId', () => confirmed!);

  @override
  Future<ShiftAssignResult?> decline(String assignmentId) =>
      _answer('decline:$assignmentId', () => releaseResult);

  @override
  Future<ShiftAssignResult?> release(String assignmentId) =>
      _answer('release:$assignmentId', () => releaseResult);

  @override
  Future<ShiftPlanners> planners(String projectId) =>
      _answer('planners:$projectId', () => plannerList);

  @override
  Future<void> addPlanner(String projectId, String userId) =>
      _answer('addPlanner:$userId', () {});

  @override
  Future<void> removePlanner(String projectId, String userId) =>
      _answer('removePlanner:$userId', () {});
}

/// A refusal as the server sends it: its sentence, and the module's code.
ApiFailure refusal(String code, {int status = 409}) =>
    ApiFailure('Server sentence', statusCode: status, details: {'code': code});

Shift sampleShift({
  String id = 's1',
  String eventId = 'e1',
  String title = 'Kasse',
  int assigned = 1,
  int required = 2,
  int? max,
  bool mine = false,
  ShiftAssignmentStatus? myStatus,
  String? myAssignmentId,
  DateTime? start,
  Duration length = const Duration(hours: 3),
  List<String> assigneeIds = const [],
}) {
  final s = start ?? DateTime(2026, 10, 24, 14);
  return Shift(
    id: id,
    eventId: eventId,
    projectId: 'p1',
    title: title,
    startsAt: s,
    endsAt: s.add(length),
    startsLocal: s,
    endsLocal: s.add(length),
    requiredHelpers: required,
    maxHelpers: max,
    assignedCount: assigned,
    understaffed: assigned < required,
    full: max != null && assigned >= max,
    mine: mine,
    myStatus: myStatus,
    myAssignmentId: myAssignmentId,
    assigneeIds: assigneeIds,
  );
}

const sampleEvent = ShiftEventHead(
  id: 'e1',
  title: 'Sommerfest',
  location: 'Festwiese',
  timezone: 'Europe/Berlin',
);

MyShift sampleMine({
  String assignmentId = 'a1',
  ShiftAssignmentStatus status = ShiftAssignmentStatus.confirmed,
  Shift? shift,
}) => MyShift(
  assignmentId: assignmentId,
  status: status,
  shift:
      shift ??
      sampleShift(mine: true, myStatus: status, myAssignmentId: assignmentId),
  event: sampleEvent,
);

ShiftEventSummary sampleSummary({
  String id = 'e1',
  int taken = 10,
  int required = 14,
  int understaffed = 2,
  bool cancelled = false,
  int mine = 1,
  bool selfAssignable = true,
}) => ShiftEventSummary(
  id: id,
  projectId: 'p1',
  title: 'Sommerfest',
  location: 'Festwiese',
  startsAt: DateTime(2026, 10, 24, 14),
  endsAt: DateTime(2026, 10, 25, 3),
  startsLocal: DateTime(2026, 10, 24, 14),
  endsLocal: DateTime(2026, 10, 25, 3),
  timezone: 'Europe/Berlin',
  placesTaken: taken,
  placesRequired: required,
  shiftsUnderstaffed: understaffed,
  mineCount: mine,
  cancelled: cancelled,
  selfAssignable: selfAssignable,
);

/// The real bundle of [code], handed over synchronously: the asset bundle
/// answers on the real event loop, which a widget test does not run.
class FileI18nSource implements LocalizationDataSource {
  @override
  Future<Map<Locale, Map<String, dynamic>>> load(List<Locale> locales) =>
      SynchronousFuture({
        for (final locale in locales)
          locale: {'common': bundle(locale.languageCode)},
      });

  static final Map<String, Map<String, dynamic>> _cache = {};

  static Map<String, dynamic> bundle(String code) => _cache.putIfAbsent(
    code,
    () =>
        jsonDecode(File('assets/i18n/$code/common.json').readAsStringSync())
            as Map<String, dynamic>,
  );
}

class FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  FakeAuthBloc()
    : super(
        const AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: 'me',
            email: 'me@example.org',
            username: 'me',
            displayName: 'Me',
            roles: {'USER'},
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Pumps [child] in the app's theme with the real [locale] bundle, at
/// [width] and text [scale], with [repository] and [blocs] provided.
Future<void> pumpShiftsUi(
  WidgetTester tester,
  Widget child, {
  required ShiftRepository repository,
  List<BlocProvider> blocs = const [],
  String locale = 'de',
  double width = 390,
  double height = 1600,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepositoryProvider<ShiftRepository>.value(
      value: repository,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(create: (_) => FakeAuthBloc()),
          ...blocs,
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(locale),
          supportedLocales: I18n.supportedLocales,
          localizationsDelegates: [
            I18NextLocalizationDelegate(
              locales: I18n.supportedLocales,
              dataSource: FileI18nSource(),
              options: const I18NextOptions(
                fallbackNamespaces: ['common'],
                escapeValue: false,
              ),
            ),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
