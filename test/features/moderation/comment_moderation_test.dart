import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/blocks/block_actions.dart';
import 'package:hinata/features/blocks/hidden_content_cubit.dart';
import 'package:hinata/features/issues/comments/comment_thread.dart';

import '../../support/recording_fake.dart';

/// A comment and the moderation (HIN-173): reported from its menu, folded
/// for whoever reported it, and a quiet placeholder once removed, with "Why?"
/// for the person who wrote it.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  setUp(() {
    AppColors.brightness = Brightness.light;
    _reported.clear();
  });

  const lena = IssueComment(
    id: 'c2',
    authorId: 'lena',
    text: 'Danke, ich sage der Spedition Bescheid.',
  );
  final removed = IssueComment(
    id: 'c3',
    authorId: 'lena',
    text: 'This content was removed by moderation.',
    moderation: {
      'text': ContentMark(
        state: MarkState.removed,
        caseId: 'k1',
        at: DateTime.utc(2026, 10, 23, 11),
      ),
    },
  );

  Future<HiddenContentCubit> hiddenWith({
    Set<String> reported = const {},
  }) async {
    final moderation = FakeModerationRepository()
      ..answer<Set<String>>(#reportedIds, reported);
    final account = FakeAccountRepository()
      ..answer<Set<String>>(#blockedIds, const {})
      ..answer<void>(#block, null);
    final hidden = HiddenContentCubit(account, moderation, enabled: () => true);
    await hidden.load();
    addTearDown(hidden.close);
    return hidden;
  }

  Future<void> pump(
    WidgetTester tester,
    IssueComment comment, {
    CommentInteractions interactions = _others,
    HiddenContentCubit? hidden,
  }) async {
    final app = MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CommentBubbleRow(comment: comment, interactions: interactions),
        ),
      ),
    );
    await tester.pumpWidget(
      hidden == null
          ? app
          : BlocProvider<HiddenContentCubit>.value(value: hidden, child: app),
    );
  }

  /// The menu's rows are sized for words; the raw keys of a widget test
  /// overflow them, which says nothing about reporting.
  Future<void> withMenu(Future<void> Function() body) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.toString().contains('overflowed')) previous?.call(details);
    };
    try {
      await body();
    } finally {
      FlutterError.onError = previous;
    }
  }

  testWidgets("somebody else's comment can be reported from its menu", (
    tester,
  ) async {
    await withMenu(() async {
      await pump(tester, lena);
      await tester.tap(find.byTooltip('comments.more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('moderation.report.action'));
      await tester.pumpAndSettle();
    });
    expect(_reported, ['c2']);
  });

  testWidgets("one's own comment offers no report", (tester) async {
    await withMenu(() async {
      await pump(tester, lena, interactions: _mine);
      await tester.tap(find.byTooltip('comments.more'));
      await tester.pumpAndSettle();
    });
    expect(find.text('moderation.report.action'), findsNothing);
    expect(find.text('common.delete'), findsOneWidget);
  });

  testWidgets('a removed comment is one quiet line, for everybody else '
      'without why', (tester) async {
    await pump(tester, removed);
    expect(
      find.textContaining('moderation.placeholder.removed'),
      findsOneWidget,
    );
    expect(find.text('This content was removed by moderation.'), findsNothing);
    expect(find.byTooltip('comments.more'), findsNothing);
    expect(find.text('moderation.placeholder.why'), findsNothing);
  });

  testWidgets('the person who wrote it gets why, as a working button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, removed, interactions: _mine);
    expect(
      tester.getSemantics(find.text('moderation.placeholder.why')),
      isSemantics(isButton: true, hasTapAction: true),
    );
    semantics.dispose();
  });

  testWidgets('a written anew comment shows its text again', (tester) async {
    const rewritten = IssueComment(
      id: 'c4',
      authorId: 'lena',
      text: 'Neu geschrieben.',
      moderation: {
        'text': ContentMark(state: MarkState.rewritten, caseId: 'k1'),
      },
    );
    await pump(tester, rewritten);
    expect(find.text('Neu geschrieben.'), findsOneWidget);
    expect(find.textContaining('moderation.placeholder'), findsNothing);
  });

  testWidgets('a comment one reported folds for one, and shows on request', (
    tester,
  ) async {
    final hidden = await hiddenWith(reported: {'c2'});
    await pump(tester, lena, hidden: hidden);
    expect(find.text('moderation.report.folded'), findsOneWidget);
    expect(find.text('Danke, ich sage der Spedition Bescheid.'), findsNothing);

    await tester.tap(find.text('blocks.show'));
    await tester.pump();
    expect(
      find.text('Danke, ich sage der Spedition Bescheid.'),
      findsOneWidget,
    );
  });

  testWidgets('blocking from a comment goes on to report it', (tester) async {
    final hidden = await hiddenWith();
    var reports = 0;
    await tester.pumpWidget(
      BlocProvider<HiddenContentCubit>.value(
        value: hidden,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => confirmBlock(
                  context,
                  personId: 'jonas',
                  name: 'Jonas Becker',
                  reportAfter: () async => reports++,
                ),
                child: const Text('block'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('block'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('blocks.confirm.button'));
    await tester.pumpAndSettle();

    expect(hidden.state.blocked, {'jonas'});
    expect(reports, 1);
  });
}

final _reported = <String>[];

void _report(IssueComment comment, Rect? anchor) => _reported.add(comment.id);
void _ignore(IssueComment _) {}
String _name(String id) => id == 'jonas' ? 'Jonas Becker' : 'Lena Vogt';
String? _none(String _) => null;
bool _notMine(IssueComment _) => false;
bool _ownComment(IssueComment _) => true;
void _react(IssueComment _, String _) {}
void _jump(String _) {}
ReplyThread _thread(String _) => const ReplyThread();
Future<Never> Function() _voice(IssueComment _) =>
    () => throw UnimplementedError();

const _others = CommentInteractions(
  meId: 'me',
  nameFor: _name,
  avatarFor: _none,
  pronounsFor: _none,
  loadVoice: _voice,
  canManage: _notMine,
  onEdit: _ignore,
  onDelete: _ignore,
  onReply: _ignore,
  onReact: _react,
  onCopy: _ignore,
  onCopyLink: _ignore,
  onTogglePin: _ignore,
  onEnterSelection: _ignore,
  onJumpToComment: _jump,
  threadOf: _thread,
  onToggleReplies: _ignore,
  onLoadMoreReplies: _ignore,
  onReport: _report,
);

const _mine = CommentInteractions(
  meId: 'lena',
  nameFor: _name,
  avatarFor: _none,
  pronounsFor: _none,
  loadVoice: _voice,
  canManage: _ownComment,
  onEdit: _ignore,
  onDelete: _ignore,
  onReply: _ignore,
  onReact: _react,
  onCopy: _ignore,
  onCopyLink: _ignore,
  onTogglePin: _ignore,
  onEnterSelection: _ignore,
  onJumpToComment: _jump,
  threadOf: _thread,
  onToggleReplies: _ignore,
  onLoadMoreReplies: _ignore,
  onReport: _report,
);
