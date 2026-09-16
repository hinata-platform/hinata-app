import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/features/admin/sections/admin_time_tags_card.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Opening a tag dialog and closing it again without saving.
///
/// It crashed. The field's controller was disposed on the modal's
/// `whenComplete`, which fires when the route is *popped* — and the route then
/// spends its exit transition rebuilding, with a controller that is already
/// gone. "A TextEditingController was used after being disposed", a red screen
/// over the whole app, and both the add and the rename dialog taken out by it.
///
/// Cancel is the path nobody writes a test for, and it is the one every user
/// takes. So: open it, dismiss it, let the transition run to the end.
void main() {
  Widget host() => RepositoryProvider<TimeRepository>.value(
    value: _FakeTagRepository(),
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Center(child: SizedBox(width: 700, child: AdminTimeTagsCard())),
      ),
    ),
  );

  void wideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Dismisses the top route the way the scrim and the close button do.
  Future<void> dismiss(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    // Long enough for the whole exit transition: the rebuild that used the
    // disposed controller happened *during* it, not at the pop.
    await tester.pumpAndSettle();
  }

  testWidgets('the add dialog survives being dismissed', (tester) async {
    wideSurface(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await tester.pumpAndSettle();
    expect(find.text('common.name'), findsOneWidget);

    await dismiss(tester);

    expect(find.text('common.name'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rename dialog survives being dismissed', (tester) async {
    wideSurface(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.pencil).first);
    await tester.pumpAndSettle();
    // It opens on the tag's current name, which is the point of renaming.
    expect(find.widgetWithText(TextField, 'Meeting'), findsOneWidget);

    await dismiss(tester);

    expect(find.text('common.name'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FakeTagRepository implements TimeRepository {
  @override
  Future<PageResult<TimeTag>> tags({
    String? query,
    int page = 0,
    int size = 50,
    bool withUsage = false,
  }) async => (
    items: const [TimeTag(id: 't1', name: 'Meeting', hue: 250, entries: 1)],
    total: 1,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
