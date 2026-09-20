import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/glass_filter_bar.dart';
import 'package:hinata/core/widgets/glass_panel.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The switcher three pages of the time module and the Gantt chart all wear.
///
/// Its compact shape used to *ask* for 44 points while the docked row it sits
/// in gives [kGlassControlHeight] — and a control that asks for more than it is
/// given is not granted it, it is squeezed. The chips came out 26 points tall,
/// their 18-point icon boxes were cut to 12, and the glyphs drifted below the
/// middle of a pill that still looked the right shape. So the bar states its
/// own height, and the chips take it rather than padding themselves to one.
void main() {
  Future<Size> measure(
    WidgetTester tester, {
    required bool compact,
    double? band,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // A docked toolbar row: a tight height the bar has to live inside.
            height: band,
            child: Align(
              // Loose constraints, the way `PageHead.actions` and a docked
              // toolbar row both hand them over: nobody tells the bar how tall
              // to be, so what it comes out as is what it asked for.
              alignment: Alignment.topLeft,
              child: GlassSwitchBar(
                compact: compact,
                maxWidth: 300,
                chips: [
                  GlassSwitchChip(
                    label: 'Tag',
                    icon: LucideIcons.calendar,
                    active: true,
                    iconOnly: compact,
                    onTap: () {},
                  ),
                  const SizedBox(width: 2),
                  GlassSwitchChip(
                    label: 'Woche',
                    icon: LucideIcons.calendarRange,
                    active: false,
                    iconOnly: compact,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(GlassSwitchBar));
  }

  testWidgets('the compact bar is exactly a docked control tall', (
    tester,
  ) async {
    expect((await measure(tester, compact: true)).height, kGlassControlHeight);
  });

  testWidgets('the wide bar is a search field tall', (tester) async {
    expect((await measure(tester, compact: false)).height, kGlassPillHeight);
  });

  testWidgets('an icon keeps its full size inside a docked row', (
    tester,
  ) async {
    // The case that went wrong: the bar inside a band exactly as tall as a
    // docked control. A bar that asks for more is squeezed, and everything
    // inside it with it.
    await measure(tester, compact: true, band: kGlassControlHeight);

    // The laid-out box, not the size the chip asked for: `Icon.size` is the
    // constructor argument and reads 18 whether or not the bar was squeezed.
    // What went wrong is that the box around it came out 18×12.
    final icons = find.byType(Icon);
    expect(icons, findsWidgets);
    for (var i = 0; i < icons.evaluate().length; i++) {
      expect(
        tester.getSize(icons.at(i)),
        const Size(18, 18),
        reason: 'icon $i',
      );
    }
  });
  testWidgets('inline drops the lens and keeps the shape', (tester) async {
    // A switcher inside a sheet or a popover sits on a surface that is already
    // glass, and Apple's own guidance is not to layer one on another. The
    // inline form is the same pill with a flat backing: same height, same
    // chips, no floating glass surface and no shadow.
    Future<Size> pump({required bool inline}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: GlassSwitchBar(
                inline: inline,
                maxWidth: 300,
                chips: const [
                  GlassSwitchChip(label: 'Tage', active: true),
                  SizedBox(width: 2),
                  GlassSwitchChip(label: 'Wochen', active: false),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(GlassSwitchBar));
    }

    final glass = await pump(inline: false);
    expect(find.byType(GlassFloatingSurface), findsOneWidget);

    final inline = await pump(inline: true);
    expect(find.byType(GlassFloatingSurface), findsNothing);

    // The one thing that must not move: a control that changed height between
    // the two forms would make every row it sits in jump.
    expect(inline.height, glass.height);
    expect(inline.width, glass.width);

    // Both labels are still there, and the chips still answer.
    expect(find.text('Tage'), findsOneWidget);
    expect(find.text('Wochen'), findsOneWidget);
  });
}
