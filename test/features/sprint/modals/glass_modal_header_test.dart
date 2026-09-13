import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets('a long title wraps to a second line instead of being cut', (
    tester,
  ) async {
    const title = 'Which days do you need?';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: GlassModalHeader(
                icon: LucideIcons.calendar,
                title: title,
                subtitle: 'Start and end',
              ),
            ),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    expect(paragraph.didExceedMaxLines, isFalse);
  });
}
