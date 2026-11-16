import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';

/// What an issue and a comment made from a mail read from the server
/// (HIN-181): the full document with its layout, not the projection published
/// apps get, and the sender a reader may trust.
void main() {
  test('an issue reads the full document and the sender it may trust', () {
    final issue = Issue.fromJson(const {
      'id': '1',
      'projectId': 'p',
      'readableId': 'IT-157',
      'title': 'Deine eSIM',
      'state': 'Open',
      'descriptionDoc': 'legacy',
      'descriptionLayoutDoc': 'full',
      'externalImageSender': 'vodafone.com',
      'externalImagesTrusted': true,
    });

    expect(issue.descriptionDoc, 'full');
    expect(issue.externalImageSender, 'vodafone.com');
    expect(issue.externalImagesTrusted, isTrue);
  });

  test('an issue says why its sender cannot be trusted', () {
    Issue read(Object? why) => Issue.fromJson({
      'id': '1',
      'projectId': 'p',
      'readableId': 'IT-157',
      'title': 'Deine eSIM',
      'state': 'Open',
      'externalImageTrustUnavailable': ?why,
    });

    expect(
      read('unsigned').externalImageTrustUnavailable,
      ExternalImageTrustUnavailable.unsigned,
    );
    expect(
      read('unverified').externalImageTrustUnavailable,
      ExternalImageTrustUnavailable.unverified,
    );
    // A reason a later server adds still reads as the general one.
    expect(
      read('expired').externalImageTrustUnavailable,
      ExternalImageTrustUnavailable.unverified,
    );
    expect(read(null).externalImageTrustUnavailable, isNull);
  });

  test('a comment reads its full document too', () {
    final comment = IssueComment.fromJson(const {
      'id': 'c1',
      'authorId': 'u1',
      'text': 'Hallo',
      'textDoc': 'legacy',
      'textLayoutDoc': 'full',
    });

    expect(comment.textDoc, 'full');
  });
}
