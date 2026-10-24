import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/blocks/hidden_content_cubit.dart';
import 'package:hinata/features/issues/comments/comment_thread.dart';

import '../../support/recording_fake.dart';
import 'block_fakes.dart';

/// A comment by somebody the reader blocks folds into one quiet line, and a
/// tap shows it for the session (HIN-168).
///
/// Widget tests render raw i18n keys, so the assertions look for keys.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  const jonas = IssueComment(
    id: 'c1',
    authorId: 'jonas',
    text: 'Stand B12 ist abgenommen.',
  );
  const lena = IssueComment(
    id: 'c2',
    authorId: 'lena',
    text: 'Danke, ich sage der Spedition Bescheid.',
  );

  Future<void> pump(
    WidgetTester tester,
    List<IssueComment> comments, {
    HiddenContentCubit? hidden,
    CommentInteractions interactions = _interactions,
  }) async {
    final thread = MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              for (final comment in comments)
                CommentBubbleRow(comment: comment, interactions: interactions),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      hidden == null
          ? thread
          : BlocProvider<HiddenContentCubit>.value(
              value: hidden,
              child: thread,
            ),
    );
  }

  testWidgets('folds what a blocked person wrote and nothing else', (
    tester,
  ) async {
    final hidden = await hiddenContent(
      FakeAccountRepository(),
      blocked: {'jonas'},
    );
    addTearDown(hidden.close);
    await pump(tester, [jonas, lena], hidden: hidden);

    expect(find.text('Stand B12 ist abgenommen.'), findsNothing);
    expect(find.text('blocks.folded'), findsOneWidget);
    expect(
      find.text('Danke, ich sage der Spedition Bescheid.'),
      findsOneWidget,
    );
  });

  testWidgets('"Anzeigen" shows it, and only that one', (tester) async {
    const again = IssueComment(id: 'c3', authorId: 'jonas', text: 'Noch was.');
    final hidden = await hiddenContent(
      FakeAccountRepository(),
      blocked: {'jonas'},
    );
    addTearDown(hidden.close);
    await pump(tester, [jonas, again], hidden: hidden);
    expect(find.text('blocks.folded'), findsNWidgets(2));

    await tester.tap(find.text('blocks.show').first);
    await tester.pump();

    expect(find.text('Stand B12 ist abgenommen.'), findsOneWidget);
    expect(find.text('Noch was.'), findsNothing);
    expect(find.text('blocks.folded'), findsOneWidget);
  });

  testWidgets('a block that lands folds the comment at once', (tester) async {
    final account = FakeAccountRepository()..answer<void>(#block, null);
    final hidden = await hiddenContent(account);
    addTearDown(hidden.close);
    await pump(tester, [jonas], hidden: hidden);
    expect(find.text('Stand B12 ist abgenommen.'), findsOneWidget);

    await hidden.block('jonas');
    await tester.pump();

    expect(find.text('Stand B12 ist abgenommen.'), findsNothing);
    expect(find.text('blocks.folded'), findsOneWidget);
  });

  group('the comment menu', () {
    /// Runs [body] with the menu's overflow reports set aside. Its rows are
    /// sized for words, and the raw keys a widget test renders overflow them;
    /// that says nothing about blocking. Every other error still fails.
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

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('comments.more'));
      await tester.pumpAndSettle();
    }

    testWidgets("offers blocking the author of somebody else's comment", (
      tester,
    ) async {
      _blockedFrom.clear();
      final hidden = await hiddenContent(FakeAccountRepository());
      addTearDown(hidden.close);
      await withMenu(() async {
        await pump(tester, [lena], hidden: hidden, interactions: _canBlock);
        await openMenu(tester);
        await tester.tap(find.text('blocks.action'));
        await tester.pumpAndSettle();
      });
      expect(_blockedFrom, ['c2']);
    });

    testWidgets("offers nothing to block on one's own comment", (tester) async {
      final hidden = await hiddenContent(FakeAccountRepository());
      addTearDown(hidden.close);
      await withMenu(() async {
        await pump(tester, [lena], hidden: hidden, interactions: _ownComments);
        await openMenu(tester);
      });
      expect(find.text('blocks.action'), findsNothing);
      expect(find.text('common.delete'), findsOneWidget);
    });

    testWidgets('offers nothing where the server does not know blocking', (
      tester,
    ) async {
      final hidden = await hiddenContent(FakeAccountRepository());
      addTearDown(hidden.close);
      await withMenu(() async {
        await pump(tester, [lena], hidden: hidden);
        await openMenu(tester);
      });
      expect(find.text('blocks.action'), findsNothing);
      expect(find.text('comments.copy'), findsOneWidget);
    });

    testWidgets('a folded comment shown anyway is not blocked twice', (
      tester,
    ) async {
      final hidden = await hiddenContent(
        FakeAccountRepository(),
        blocked: {'jonas'},
      );
      addTearDown(hidden.close);
      await withMenu(() async {
        await pump(tester, [jonas], hidden: hidden, interactions: _canBlock);
        await tester.tap(find.text('blocks.show'));
        await tester.pump();
        await openMenu(tester);
      });
      expect(find.text('blocks.action'), findsNothing);
      expect(find.text('comments.copy'), findsOneWidget);
    });
  });

  testWidgets('without the app around it nothing folds', (tester) async {
    await pump(tester, [jonas]);
    expect(find.text('Stand B12 ist abgenommen.'), findsOneWidget);
    expect(find.text('blocks.folded'), findsNothing);
  });

  testWidgets('the folded line holds at 390 points and text at 200 %', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hidden = await hiddenContent(
      FakeAccountRepository(),
      blocked: {'jonas'},
    );
    addTearDown(hidden.close);
    await tester.pumpWidget(
      BlocProvider<HiddenContentCubit>.value(
        value: hidden,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: CommentBubbleRow(comment: jonas, interactions: _interactions),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final button = tester.getSize(
      find.widgetWithText(TextButton, 'blocks.show'),
    );
    expect(button.height, greaterThanOrEqualTo(48));
  });
}

void _ignore(IssueComment _) {}

/// The comments the menu asked to block the author of.
final _blockedFrom = <String>[];
void _block(IssueComment comment) => _blockedFrom.add(comment.id);

const _canBlock = CommentInteractions(
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
  onBlockAuthor: _block,
);

const _ownComments = CommentInteractions(
  meId: 'lena',
  nameFor: _name,
  avatarFor: _none,
  pronounsFor: _none,
  loadVoice: _voice,
  canManage: _mine,
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
  onBlockAuthor: _block,
);

const _interactions = CommentInteractions(
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
);

String _name(String id) => id == 'jonas' ? 'Jonas Becker' : 'Lena Vogt';
String? _none(String _) => null;
bool _notMine(IssueComment _) => false;
bool _mine(IssueComment _) => true;
void _react(IssueComment _, String _) {}
void _jump(String _) {}
ReplyThread _thread(String _) => const ReplyThread();
Future<Never> Function() _voice(IssueComment _) =>
    () => throw UnimplementedError();
