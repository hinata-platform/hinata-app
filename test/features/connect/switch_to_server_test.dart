import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/connect/server_switcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Choosing a saved server on the connect screen: the one that just failed
/// tries again instead of doing nothing, so nobody is stuck on a server that
/// was down for a moment.
void main() {
  Future<(AppStorage, _RecordingConfig, BuildContext)> pump(
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    await storage.setServerUrl('https://down.example');
    final config = _RecordingConfig();
    addTearDown(config.close);
    late BuildContext context;
    await tester.pumpWidget(
      RepositoryProvider<AppStorage>.value(
        value: storage,
        child: BlocProvider<AppConfigBloc>.value(
          value: config,
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return (storage, config, context);
  }

  testWidgets('the current server tries again when asked to', (tester) async {
    final (_, config, context) = await pump(tester);

    await switchToServer(context, 'https://down.example', retry: true);
    await tester.pump();

    expect(config.events, [isA<AppConfigStarted>()]);
  });

  testWidgets('elsewhere the current server is left alone', (tester) async {
    final (_, config, context) = await pump(tester);

    await switchToServer(context, 'https://down.example');
    await tester.pump();

    expect(config.events, isEmpty);
  });
}

class _RecordingConfig extends Bloc<AppConfigEvent, AppConfigState>
    implements AppConfigBloc {
  _RecordingConfig() : super(const AppConfigState()) {
    on<AppConfigEvent>((event, _) => events.add(event));
  }

  final List<AppConfigEvent> events = [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
