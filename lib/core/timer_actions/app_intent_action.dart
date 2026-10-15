import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'timer_background_action.dart';

/// The channel of the headless engine iOS starts for an App Intent (HIN-105):
/// `HinataIntentEngine` in the runner.
const MethodChannel appIntentChannel = MethodChannel(
  'hinata/app_intents/background',
);

/// One request of Siri, Shortcuts or a control, as the runner hands it over.
class AppIntentRequest {
  const AppIntentRequest(this.command, {this.description, this.projectId});

  /// The longest description an intent may hand over; the app's own field
  /// takes no more.
  static const descriptionMax = 500;

  final TimerBackgroundCommand command;
  final String? description;
  final String? projectId;

  /// Null for anything that is not one of our three commands.
  static AppIntentRequest? fromArguments(Object? arguments) {
    if (arguments is! Map) return null;
    final command = switch (arguments['command']) {
      'start' => TimerBackgroundCommand.start,
      'stop' => TimerBackgroundCommand.stop,
      'advancePhase' => TimerBackgroundCommand.advancePhase,
      _ => null,
    };
    if (command == null) return null;
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    final description = text(arguments['description']);
    return AppIntentRequest(
      command,
      description: description == null
          ? null
          : String.fromCharCodes(description.runes.take(descriptionMax)),
      projectId: text(arguments['projectId']),
    );
  }
}

/// Answers one request with the name of its [TimerBackgroundOutcome]; what
/// Siri says is the runner's.
Future<String> handleAppIntent(
  Object? arguments, {
  Future<TimerBackgroundOutcome> Function(
        TimerBackgroundCommand command, {
        String? description,
        String? projectId,
      })
      run =
      runTimerBackgroundCommand,
}) async {
  final request = AppIntentRequest.fromArguments(arguments);
  if (request == null) return TimerBackgroundOutcome.failed.name;
  final outcome = await run(
    request.command,
    description: request.description,
    projectId: request.projectId,
  );
  return outcome.name;
}

/// The entry point of the headless engine: listens, then tells the runner it
/// is ready. The same action as a widget button, with a start in addition.
@pragma('vm:entry-point')
Future<void> appIntentMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  appIntentChannel.setMethodCallHandler((call) async {
    if (call.method != 'perform') return null;
    return handleAppIntent(call.arguments);
  });
  await appIntentChannel.invokeMethod<void>('ready');
}
