import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/moderation_models.dart';

/// The names this app sends and reads for moderation (HIN-173), kept in step
/// with the server by hand: its `ModerationContractTest` holds the very same
/// lists, so a value added on one side fails the other until both agree.
void main() {
  const categories = [
    'HARASSMENT',
    'THREAT',
    'SEXUAL',
    'CHILD_SAFETY',
    'PRIVACY',
    'SPAM',
    'ILLEGAL',
    'OTHER',
  ];
  const kinds = [
    'ISSUE',
    'COMMENT',
    'ATTACHMENT',
    'ARTICLE',
    'PERSON',
    'OTHER',
  ];

  test('the reasons are the server\'s, in its order', () {
    expect([for (final c in ReportCategory.values) c.wire], categories);
  });

  test('the kinds of content are the server\'s', () {
    expect([for (final k in ContentKind.values) k.wire], kinds);
  });

  test('only a removed mark draws the placeholder', () {
    final marks = ContentMark.mapOf({
      'title': {
        'state': 'REMOVED',
        'caseId': 'k1',
        'at': '2026-10-23T09:00:00Z',
      },
      'description': {'state': 'REWRITTEN', 'caseId': 'k1'},
      'file': {'state': 'SOMETHING_NEW'},
      'broken': 'not a mark',
    });

    expect(marks['title']?.removed, isTrue);
    expect(marks['title']?.caseId, 'k1');
    expect(marks['description']?.removed, isFalse);
    // What this app does not know shows the text the server sent.
    expect(marks['file']?.removed, isFalse);
    expect(marks.containsKey('broken'), isFalse);
    expect(ContentMark.mapOf(null), isEmpty);
  });

  test('a notice reads whatever the server leaves out', () {
    final notice = Statement.fromJson(const {
      'caseId': 'k1',
      'measure': 'Gesperrt bis zum 1. November.',
      'scope': null,
      'until': '2026-11-01T00:00:00Z',
      'suspension': 'DAYS_7',
      'ground': 'LAW',
      'appealState': 'PENDING',
    });

    expect(notice.suspends, isTrue);
    // A removal with a suspension until further notice suspends too, though
    // it names no end; a removal alone does not.
    expect(
      Statement.fromJson(const {
        'caseId': 'k1',
        'scope': 'WHOLE',
        'suspension': 'INDEFINITE',
      }).suspends,
      isTrue,
    );
    expect(
      Statement.fromJson(const {'caseId': 'k1', 'scope': 'WHOLE'}).suspends,
      isFalse,
    );
    expect(notice.lawGround, isTrue);
    expect(notice.appealState, AppealState.pending);
    expect(notice.appealable, isFalse);
    expect(notice.headline, isEmpty);
  });
}
