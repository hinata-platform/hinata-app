import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/issues/comments/glass_comment_composer.dart';
import 'package:hinata/features/issues/comments/voice/voice_recorder.dart';

/// A voice message whose upload fails stays in the composer to send again
/// (HIN-173), instead of going down with the request.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  testWidgets('a voice message that did not go out waits to be sent again', (
    tester,
  ) async {
    final sent = <VoiceRecording>[];
    var answer = false;
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: GlassCommentComposer(
              controller: controller,
              focusNode: focus,
              onSubmitText: (_) {},
              onAttach: (_) {},
              recorder: _FakeRecorder.new,
              onSendVoice: (recording) async {
                sent.add(recording);
                return answer;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('comments.composer.record'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('comments.composer.sendVoice'));
    await tester.pump();
    await tester.pump();

    expect(sent, hasLength(1));
    expect(find.text('comments.composer.voiceNotSent'), findsOneWidget);

    answer = true;
    await tester.tap(find.bySemanticsLabel('comments.composer.retryVoice'));
    await tester.pump();
    await tester.pump();

    expect(sent, hasLength(2));
    expect(identical(sent.first, sent.last), isTrue);
    expect(find.text('comments.composer.voiceNotSent'), findsNothing);
  });
}

/// A microphone that records two seconds of silence, without a device.
class _FakeRecorder implements VoiceRecorder {
  @override
  bool get isRecording => false;

  @override
  Stream<double> get liveAmplitude => const Stream.empty();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> start() async => true;

  @override
  Future<VoiceRecording?> stop() async => VoiceRecording(
    bytes: Uint8List.fromList(const [1, 2, 3]),
    mime: 'audio/mp4',
    durationMs: 2000,
    peaks: const [1, 2, 3],
  );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
