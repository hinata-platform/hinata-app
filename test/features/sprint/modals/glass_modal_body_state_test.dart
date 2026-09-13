/// A glass modal mounts its body once, however its glass changes on the way in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

void main() {
  testWidgets('the body keeps its state while the modal opens', (tester) async {
    // The materialize transition changes the widgets around the glass content
    // while it runs. A body that was unmounted each time lost its state and
    // loaded its data again: the privacy sheet read its notice three times.
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var mounts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGlassModal<void>(
                context,
                builder: (_) => _CountsMounts(onMount: () => mounts++),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('body'), findsOneWidget);
    expect(mounts, 1);
  });
}

class _CountsMounts extends StatefulWidget {
  const _CountsMounts({required this.onMount});

  final VoidCallback onMount;

  @override
  State<_CountsMounts> createState() => _CountsMountsState();
}

class _CountsMountsState extends State<_CountsMounts> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('body');
}
