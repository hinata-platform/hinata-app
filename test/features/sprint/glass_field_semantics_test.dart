import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

/// The caption above a [GlassField] is the field's name. Over a text input it
/// used to be a node of its own, and call sites added a second label on the
/// input, so a screen reader said "Job title" and then "Job title, text
/// field". The caption has to be heard once, and as the name of the input.
void main() {
  Future<void> pump(WidgetTester tester, Widget field) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: field),
      ),
    ),
  );

  /// What assistive technology sees: every node that is not merged into a
  /// parent, with the data merged into it from below.
  List<SemanticsData> announcedNodes(WidgetTester tester) {
    final out = <SemanticsData>[];
    void visit(SemanticsNode node) {
      if (!node.isMergedIntoParent) out.add(node.getSemanticsData());
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    final owner = tester.renderObject(find.byType(Scaffold)).owner!;
    visit(owner.semanticsOwner!.rootSemanticsNode!);
    return out;
  }

  List<SemanticsData> naming(WidgetTester tester, String caption) => [
    for (final data in announcedNodes(tester))
      if (data.label.contains(caption)) data,
  ];

  testWidgets('a text input announces its caption once, as a text field', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      GlassField(
        label: 'Job title',
        child: TextField(decoration: glassInputDecoration(hint: 'e.g. Lead')),
      ),
    );

    final nodes = naming(tester, 'Job title');
    expect(nodes, hasLength(1));
    expect(nodes.single.flagsCollection.isTextField, isTrue);
    expect(
      'Job title'.allMatches(nodes.single.label),
      hasLength(1),
      reason: 'the caption is in the name exactly once',
    );
    handle.dispose();
  });

  testWidgets('a wrapped text input opts in and is named once too', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      GlassField(
        label: 'Key',
        isTextInput: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [TextField(decoration: glassInputDecoration())],
        ),
      ),
    );

    final nodes = naming(tester, 'Key');
    expect(nodes, hasLength(1));
    expect(nodes.single.flagsCollection.isTextField, isTrue);
    handle.dispose();
  });

  testWidgets('a non-text child keeps the caption and its own role', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      GlassField(
        label: 'Duration',
        child: GlassSegmented(
          labels: const ['1 week', '2 weeks'],
          selected: 0,
          onChanged: (_) {},
        ),
      ),
    );

    final caption = naming(tester, 'Duration');
    expect(caption, hasLength(1));
    expect(caption.single.flagsCollection.isTextField, isFalse);
    final segment = naming(tester, '1 week').single;
    expect(segment.flagsCollection.isButton, isTrue);
    expect(segment.label, isNot(contains('Duration')));
    handle.dispose();
  });
}
