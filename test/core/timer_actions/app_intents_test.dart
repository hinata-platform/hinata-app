import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/timer_actions/app_intent_action.dart';
import 'package:hinata/core/timer_actions/intent_project_snapshot.dart';
import 'package:hinata/core/timer_actions/timer_background_action.dart';
import 'package:hinata/core/timer_surfaces/adapters/app_intents_surface.dart';
import 'package:hinata/core/timer_surfaces/timer_surface.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

/// Siri, Shortcuts and the controls (HIN-105): what reaches the Dart action,
/// what the device keeps for the intents, and when the controls read again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a request from the runner', () {
    test(
      'names one of three commands; anything else fails without acting',
      () async {
        final calls = <TimerBackgroundCommand>[];
        Future<TimerBackgroundOutcome> run(
          TimerBackgroundCommand command, {
          String? description,
          String? projectId,
        }) async {
          calls.add(command);
          return TimerBackgroundOutcome.done;
        }

        expect(await handleAppIntent({'command': 'stop'}, run: run), 'done');
        expect(
          await handleAppIntent({'command': 'discard'}, run: run),
          'failed',
        );
        expect(await handleAppIntent('stop', run: run), 'failed');
        expect(calls, [TimerBackgroundCommand.stop]);
      },
    );

    test('hands a start its trimmed description and project, and the '
        'outcome back by name', () async {
      String? sent;
      String? project;
      final answer = await handleAppIntent(
        {
          'command': 'start',
          'description': '  Review  ',
          'projectId': 'project-1',
        },
        run: (command, {String? description, String? projectId}) async {
          sent = description;
          project = projectId;
          return TimerBackgroundOutcome.alreadyRunning;
        },
      );

      expect(answer, 'alreadyRunning');
      expect(sent, 'Review');
      expect(project, 'project-1');
    });

    test('an empty description is none, a long one is cut', () {
      expect(
        AppIntentRequest.fromArguments({
          'command': 'start',
          'description': '   ',
        })!.description,
        isNull,
      );
      expect(
        AppIntentRequest.fromArguments({
          'command': 'start',
          'description': 'x' * 900,
        })!.description,
        hasLength(AppIntentRequest.descriptionMax),
      );
    });
  });

  group('the project snapshot', () {
    late _FakeChannel channel;

    setUp(() => channel = _FakeChannel());

    test('keeps id and name of at most 200 projects, without templates, read '
        'in pages the server hands out', () async {
      final projects = _Projects(total: 340);
      await IntentProjectSnapshot(projects, channel: channel).refresh();

      final written = channel.projects.single!;
      expect(written, hasLength(IntentProjectSnapshot.limit));
      expect(projects.pages, [0, 1, 2]);
      expect(written.any((p) => p.name.startsWith('Template')), isFalse);
      expect(written.first, (id: 'p0', name: 'Project 0'));
      // Nothing of a project travels but these two fields.
      expect(
        jsonEncode(written.map((p) => {'id': p.id, 'name': p.name}).toList()),
        isNot(contains('KEY')),
      );
    });

    test('reads again only once it is older than its age', () async {
      var now = DateTime(2026, 10, 16, 9);
      final projects = _Projects(total: 3);
      final snapshot = IntentProjectSnapshot(
        projects,
        channel: channel,
        clock: () => now,
      );

      await snapshot.refresh();
      await snapshot.refresh();
      expect(projects.pages, [0]);

      now = now.add(const Duration(minutes: 16));
      await snapshot.refresh();
      expect(projects.pages, [0, 0]);
    });

    test('an answer still on its way after a sign-out is dropped', () async {
      final projects = _Projects(total: 3, hold: Completer<void>());
      final snapshot = IntentProjectSnapshot(projects, channel: channel);

      final refresh = snapshot.refresh();
      snapshot.invalidate();
      projects.hold!.complete();
      await refresh;

      expect(channel.projects, isEmpty);
    });

    test('a failed read writes nothing', () async {
      final projects = _Projects(total: 3, fail: true);
      await IntentProjectSnapshot(projects, channel: channel).refresh();
      expect(channel.projects, isEmpty);
    });
  });

  group('the surface', () {
    late _FakeChannel channel;
    late AppIntentsSurface surface;
    late _Host host;

    setUp(() async {
      channel = _FakeChannel(pending: '/time/focus');
      surface = AppIntentsSurface(channel: channel);
      host = _Host();
      await surface.init(host);
    });

    test('opens the route of an intent that launched the app, and every '
        'later one', () {
      expect(host.routes, ['/time/focus']);
      channel.open('/time/focus');
      expect(host.routes, ['/time/focus', '/time/focus']);
    });

    test(
      'reloads the controls on a start and a stop, not on every state',
      () async {
        const running = TimerSurfaceState(running: true, runningSurface: true);
        const idle = TimerSurfaceState.idle;

        await surface.apply(running);
        await surface.apply(running);
        await surface.apply(idle);

        expect(channel.reloads, 2);
      },
    );

    test('signing out removes the projects and resets the controls', () async {
      await surface.clear();

      expect(channel.projects, [null]);
      expect(channel.reloads, 1);
    });
  });

  test('the strings of the intents and the phrases speak all nine '
      'languages, and every phrase names the app', () {
    const languages = ['en', 'de', 'es', 'fr', 'ru', 'zh', 'ja', 'hi', 'ar'];
    final intents =
        (jsonDecode(File('ios/Shared/AppIntents.xcstrings').readAsStringSync())
                as Map<String, dynamic>)['strings']
            as Map<String, dynamic>;
    String intent(String key, String language) =>
        ((((intents[key] as Map<String, dynamic>)['localizations']
                        as Map<String, dynamic>)[language]
                    as Map<String, dynamic>?)?['stringUnit']
                as Map<String, dynamic>?)?['value']
            as String? ??
        '';
    // AppShortcuts.xcstrings needs iOS 17 for the whole runner, which still
    // starts at iOS 15; the phrases are classic .strings files.
    Map<String, String> phrases(String language) => {
      for (final m
          in RegExp(
            r'^"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$',
            multiLine: true,
          ).allMatches(
            File(
              'ios/Runner/$language.lproj/AppShortcuts.strings',
            ).readAsStringSync(),
          ))
        m.group(1)!: m.group(2)!,
    };
    Set<String> placeholders(String text) => RegExp(
      r'\$\{\w+\}|%\d\$@',
    ).allMatches(text).map((m) => m.group(0)!).toSet();

    final english = phrases('en');
    expect(english, hasLength(inInclusiveRange(1, 10 * 3)));
    for (final language in languages) {
      for (final key in intents.keys) {
        final text = intent(key, language);
        expect(text, isNotEmpty, reason: '$key in $language');
        expect(text, isNot(contains('—')), reason: '$key in $language');
        expect(
          placeholders(text),
          placeholders(intent(key, 'en')),
          reason: '$key in $language',
        );
      }
      final translated = phrases(language);
      expect(translated.keys.toSet(), english.keys.toSet(), reason: language);
      for (final MapEntry(:key, :value) in translated.entries) {
        expect(key, contains(r'${applicationName}'));
        expect(
          placeholders(value),
          placeholders(key),
          reason: '$key in $language',
        );
      }
    }
    // Every phrase in the Swift code has its translations.
    final provider = File(
      'ios/Runner/HinataAppShortcuts.swift',
    ).readAsStringSync();
    final spoken = RegExp(r'^\s*"(.*)",?$', multiLine: true)
        .allMatches(provider)
        .map(
          (m) => m
              .group(1)!
              .replaceAll(r'\(.applicationName)', r'${applicationName}')
              .replaceAll(r'\(\.$project)', r'${project}'),
        );
    expect(spoken.toSet(), english.keys.toSet());
    // Every key the Swift code reads is in the catalog.
    final swift = [
      'ios/Shared/TimerIntents.swift',
      'ios/HinataWidgets/TimerControls.swift',
      'ios/Runner/HinataAppShortcuts.swift',
    ].map((path) => File(path).readAsStringSync()).join();
    final used = RegExp(
      r'''(?:intentText\(|LocalizedStringResource\()\s*(?:isOn \? )?"([a-z][\w.]+)"''',
    ).allMatches(swift).map((m) => m.group(1)!);
    for (final key in {
      ...used,
      'control.toggle.on',
      'control.toggle.off',
      'status.elapsed',
      'status.remaining',
    }) {
      expect(intents, contains(key), reason: key);
    }
  });
}

class _FakeChannel extends AppIntentsChannel {
  _FakeChannel({this.pending});

  String? pending;
  final List<List<IntentProject>?> projects = [];
  int reloads = 0;
  void Function(String route)? _open;

  void open(String route) => _open?.call(route);

  @override
  Future<void> reloadControls() async => reloads++;

  @override
  Future<void> setProjects(List<IntentProject>? projects) async =>
      this.projects.add(projects);

  @override
  Future<String?> takePendingRoute() async {
    final route = pending;
    pending = null;
    return route;
  }

  @override
  void onOpenRoute(void Function(String route) handler) => _open = handler;
}

class _Projects implements ProjectRepository {
  _Projects({required this.total, this.hold, this.fail = false});

  final int total;
  final Completer<void>? hold;
  final bool fail;
  final List<int> pages = [];

  @override
  Future<({List<Project> projects, int total})> searchProjects({
    String? query,
    int page = 0,
    int size = 25,
    bool archived = false,
  }) async {
    pages.add(page);
    await hold?.future;
    if (fail) throw PlatformException(code: 'offline');
    final from = page * size;
    final to = (from + size).clamp(0, total);
    return (
      projects: [
        for (var i = from; i < to; i++)
          // Every tenth one is a template, which never starts a timer.
          i % 10 == 9
              ? Project(
                  id: 't$i',
                  key: 'KEY$i',
                  name: 'Template $i',
                  template: true,
                )
              : Project(id: 'p$i', key: 'KEY$i', name: 'Project $i'),
      ],
      total: total,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Host implements TimerSurfaceHost {
  final List<String> routes = [];

  @override
  void openRoute(String route) => routes.add(route);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
