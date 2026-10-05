// What a screen reader gets from the controls every page is built from
// (HIN-110, phase 5 of the flutter-ui-design skill).
//
// Static analysis sees that a Semantics node exists; it cannot see what a
// screen reader announces, nor whether the node can be activated. A control
// that announces as a button and does nothing when activated passes every
// review and fails every reader, so this walks the tree the reader gets and
// performs the tap the reader would.
//
// It does not replace a pass with VoiceOver or TalkBack on a device; it keeps
// the mechanical failures out of CI so that pass can spend its time on
// phrasing and flow.

import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/core/theme/glass_chrome.dart';
import 'package:hinata/core/widgets/folded_hint.dart';
import 'package:hinata/core/widgets/glass_filter_bar.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/core/widgets/hive_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Every node a reader can reach.
Iterable<SemanticsNode> _walk(SemanticsNode node) sync* {
  yield node;
  final children = <SemanticsNode>[];
  node.visitChildren((child) {
    children.add(child);
    return true;
  });
  for (final child in children) {
    yield* _walk(child);
  }
}

void main() {
  final taps = <String>[];

  Widget gallery(Brightness brightness) => MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            PageHead(
              title: 'Projects',
              actions: [
                PrimaryButton(
                  icon: LucideIcons.plus,
                  label: 'New project',
                  onPressed: () => taps.add('primary'),
                ),
              ],
            ),
            GlassSearchButton(
              tooltip: 'Search projects',
              onTap: () => taps.add('search'),
            ),
            GlassFilterPill(
              icon: LucideIcons.calendar,
              label: 'Any time',
              active: false,
              onTap: (_) => taps.add('filter'),
            ),
            GlassScopePill(
              icon: LucideIcons.folder,
              label: 'Active',
              active: false,
              onTap: () => taps.add('scope'),
            ),
            GlassCircleButton(
              icon: LucideIcons.bell,
              tooltip: 'Notifications',
              onTap: () => taps.add('circle'),
            ),
            const FoldedHint(
              'A long hint that folds to one line and opens in full on demand.',
            ),
            HiveEmptyState(
              title: 'No boards yet',
              message: 'Boards gather the issues of one or more projects.',
              action: FilledButton(
                onPressed: () => taps.add('empty'),
                child: const Text('New board'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  setUp(taps.clear);

  for (final brightness in Brightness.values) {
    testWidgets('every control has a name and does what it says when a '
        'screen reader activates it ($brightness)', (tester) async {
      AppColors.brightness = brightness;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(gallery(brightness));
      await tester.pumpAndSettle();

      // The pipeline owner of the view the gallery is drawn in holds its tree.
      final owner = tester
          .renderObject(find.byType(Scaffold))
          .owner!
          .semanticsOwner!;
      final failures = <String>[];
      final controls = <SemanticsNode>[];
      for (final node in _walk(owner.rootSemanticsNode!)) {
        final data = node.getSemanticsData();
        final isButton = data.flagsCollection.isButton;
        final canTap = data.hasAction(SemanticsAction.tap);
        if (!isButton && !canTap) continue;
        final name = '${data.label}${data.tooltip}'.trim();
        if (name.isEmpty) {
          failures.add('unnamed control at ${node.rect}');
        }
        // The failure that hides best: an ExcludeSemantics between the node
        // and its tappable swallows the action.
        if (isButton &&
            !canTap &&
            data.flagsCollection.isEnabled == Tristate.isTrue) {
          failures.add('"$name" announces as a button but cannot be tapped');
        }
        if (canTap) controls.add(node);
      }
      expect(failures, isEmpty, reason: failures.join('\n'));

      // Activate each one the way a reader does, through the semantics tree.
      for (final node in controls) {
        owner.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        // Close whatever a control opened, so the next one is reachable.
        if (tester.any(find.byType(ModalBarrier).hitTestable())) {
          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();
        }
      }
      expect(
        taps,
        containsAll([
          'primary',
          'search',
          'filter',
          'scope',
          'circle',
          'empty',
        ]),
      );
      // Not in a tearDown: the binding checks for live handles before those
      // run.
      handle.dispose();
    });
  }

  testWidgets('every control is a target a finger can hit', (tester) async {
    AppColors.brightness = Brightness.light;
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(gallery(Brightness.light));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    // 44 pt, the iOS minimum: the glass pills draw at 36 pt inside a 44 pt
    // docked row and answer on all of it.
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('text keeps its contrast in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      AppColors.brightness = brightness;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(gallery(brightness));
      await tester.pumpAndSettle();
      // A floor, not a proof: it cannot see text over glass or images. The
      // token pairs are measured with check_contrast.py as well.
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    }
  });
}
