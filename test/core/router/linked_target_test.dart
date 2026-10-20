import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/router/linked_target.dart';

/// The one pattern behind every page a link points into: a target opens once
/// per visit of the link, after the frame, while the page is still there.
void main() {
  testWidgets('once per visit, and again for a new visit', (tester) async {
    final opened = <String>[];
    late LinkedTarget<String> link;
    await tester.pumpWidget(_Host(onState: (state) => link = state.link));

    final first = LinkVisit.next();
    expect(link.take('r7', first), isTrue);
    link.openWhen(ready: false, open: opened.add);
    await tester.pump();
    expect(opened, isEmpty, reason: 'not before the page is ready');
    expect(link.pending, 'r7');

    link.openWhen(ready: true, open: opened.add);
    expect(opened, isEmpty, reason: 'after the frame, not during it');
    await tester.pump();
    expect(opened, ['r7']);
    expect(link.pending, isNull);

    // A rebuild hands in the same link: nothing.
    expect(link.take('r7', first), isFalse);
    link.openWhen(ready: true, open: opened.add);
    await tester.pump();
    expect(opened, ['r7']);

    // The same link chosen again is a visit of its own.
    expect(link.take('r7', LinkVisit.next()), isTrue);
    link.openWhen(ready: true, open: opened.add);
    await tester.pump();
    expect(opened, ['r7', 'r7']);
  });

  testWidgets('no target, a dropped one, or a page gone opens nothing', (
    tester,
  ) async {
    final opened = <String>[];
    late LinkedTarget<String> link;
    await tester.pumpWidget(_Host(onState: (state) => link = state.link));

    expect(link.take(null, LinkVisit.next()), isFalse);
    expect(link.take('', LinkVisit.next()), isFalse);

    link.take('gone', LinkVisit.next());
    link.drop();
    link.openWhen(ready: true, open: opened.add);
    await tester.pump();
    expect(opened, isEmpty);

    link.take('late', LinkVisit.next());
    link.openWhen(ready: true, open: opened.add);
    await tester.pumpWidget(const SizedBox());
    expect(opened, isEmpty);
  });

  test('a visit is read from the route only when it is one', () {
    final visit = LinkVisit.next();
    expect(visit, isNot(LinkVisit.next()));
    expect(visit == visit, isTrue);
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.onState});

  final void Function(_HostState state) onState;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final link = LinkedTarget<String>(this);

  @override
  void initState() {
    super.initState();
    widget.onState(this);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
