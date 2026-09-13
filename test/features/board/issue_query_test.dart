/// The one search rule both boards filter their cards by.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/board/board_filter.dart';

void main() {
  const issue = Issue(
    id: 'i1',
    projectId: 'p1',
    readableId: 'MOB-12',
    title: 'Fix the login screen',
    state: 'OPEN',
    tags: ['Auth'],
  );

  test('a blank search holds every issue', () {
    expect(issueMatchesQuery(issue, ''), isTrue);
    expect(issueMatchesQuery(issue, '   '), isTrue);
  });

  test('the key, the title and a label all answer, whatever the case', () {
    expect(issueMatchesQuery(issue, 'mob-12'), isTrue);
    expect(issueMatchesQuery(issue, 'LOGIN'), isTrue);
    expect(issueMatchesQuery(issue, 'auth'), isTrue);
  });

  test('words found nowhere on the issue do not', () {
    expect(issueMatchesQuery(issue, 'release'), isFalse);
  });
}
