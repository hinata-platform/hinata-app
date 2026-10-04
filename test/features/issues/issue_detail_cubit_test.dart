import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/issue_detail.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/issue_detail_cubit.dart';
import 'package:hinata/features/knowledge/data/knowledge_models.dart'
    show KbArticle;

import 'recording_fakes.dart';

void main() {
  late FakeIssueRepository issues;
  late FakeCommentRepository comments;
  late FakeProjectRepository projects;
  late FakeUserRepository users;
  late FakeMediaRepository media;
  late FakeKnowledgeRepository knowledge;
  late IssueDetailCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    comments = FakeCommentRepository();
    projects = FakeProjectRepository();
    users = FakeUserRepository();
    media = FakeMediaRepository();
    knowledge = FakeKnowledgeRepository();
    cubit = IssueDetailCubit(
      issues: issues,
      comments: comments,
      projects: projects,
      users: users,
      media: media,
      knowledge: knowledge,
    );
  });

  tearDown(() => cubit.close());

  const comment = IssueComment(id: 'c1', authorId: 'u1', text: 'Hello');
  final file = MultipartFile.fromBytes(const [1, 2], filename: 'a.png');

  test('the issue and the issues around it', () async {
    final issue = testIssue();
    final detail = IssueDetail(
      issue: issue,
      project: null,
      comments: const [],
      commentsTotal: 0,
      pinnedComments: const [],
      activity: const [],
      activityTotal: 0,
      workItems: const [],
      workItemsTotal: 0,
      hierarchy: IssueHierarchy.empty,
      sprints: const [],
      users: const [],
      canDelete: false,
    );
    await expectForwarded(
      issues,
      #issueDetail,
      () => Future.value(detail),
      () => cubit.issueDetail('i1', commentSize: 20, commentSort: 'oldest'),
      positional: ['i1'],
      named: {#commentSize: 20, #commentSort: 'oldest'},
    );
    await expectForwarded(
      issues,
      #issue,
      () => Future.value(issue),
      () => cubit.issue('i1'),
      positional: ['i1'],
    );
    await expectForwarded(
      issues,
      #updateIssue,
      () => Future.value(issue),
      () => cubit.updateIssue('i2', const {'state': 'DONE'}),
      positional: [
        'i2',
        {'state': 'DONE'},
      ],
    );
    await expectForwarded(
      issues,
      #createIssue,
      () => Future.value(issue),
      () => cubit.createIssue(const {'type': 'SUBTASK'}),
      positional: [
        {'type': 'SUBTASK'},
      ],
    );
    await expectForwarded(
      issues,
      #archiveIssue,
      () => Future.value(issue),
      () => cubit.archiveIssue('i1'),
      positional: ['i1'],
    );
    await expectForwarded(
      issues,
      #unarchiveIssue,
      () => Future.value(issue),
      () => cubit.unarchiveIssue('i1'),
      positional: ['i1'],
    );
    await expectForwarded(
      issues,
      #deleteIssue,
      () => Future<void>.value(),
      () => cubit.deleteIssue('i1'),
      positional: ['i1'],
    );
    await expectForwarded(
      issues,
      #issueActivity,
      () => Future.value((items: const <IssueActivity>[], total: 0)),
      () => cubit.issueActivity('i1', page: 2),
      positional: ['i1'],
      named: {#page: 2},
    );
    await expectForwarded(
      issues,
      #issueHierarchy,
      () => Future.value(IssueHierarchy.empty),
      () => cubit.issueHierarchy('i1'),
      positional: ['i1'],
    );
    await expectForwarded(
      issues,
      #uploadAttachment,
      () => Future.value(issue),
      () => cubit.uploadAttachment('i1', file),
      positional: ['i1', file],
    );
    await expectForwarded(
      issues,
      #resolveIssues,
      () => Future.value([issue]),
      () => cubit.resolveIssues(const ['HIN-1']),
      positional: [
        ['HIN-1'],
      ],
    );
    await expectForwarded(
      issues,
      #mentionSearch,
      () => Future.value(const <IssueRef>[]),
      () => cubit.mentionSearch(projectId: 'p1', query: 'lo'),
      named: {#projectId: 'p1', #query: 'lo'},
    );
    await expectForwarded(
      issues,
      #issues,
      () => Future.value((issues: [issue], total: 1)),
      () => cubit.searchIssues('HIN-1', size: 20),
      named: {#query: 'HIN-1', #size: 20},
    );
    issues.answers[#apiBaseUrl] = (_) => 'https://track.example';
    expect(cubit.apiBaseUrl, 'https://track.example');
  });

  test('the work log', () async {
    await expectForwarded(
      issues,
      #workItemsPage,
      () => Future.value((items: const [testWorkItem], total: 1)),
      () => cubit.workItemsPage('i1', page: 0, size: 8),
      positional: ['i1'],
      named: {#page: 0, #size: 8},
    );
    await expectForwarded(
      issues,
      #deleteWorkItem,
      () => Future<void>.value(),
      () => cubit.deleteWorkItem('w1'),
      positional: ['w1'],
    );
  });

  test('the comments', () async {
    final token = CancelToken();
    await expectForwarded(
      comments,
      #commentEventStream,
      () => Future.value(const Stream<List<int>>.empty()),
      () => cubit.commentEventStream('i1', cancelToken: token),
      positional: ['i1'],
      named: {#cancelToken: token},
    );
    await expectForwarded(
      comments,
      #comments,
      () => Future.value((items: const [comment], total: 1)),
      () => cubit.comments('i1', page: 1, size: 30, sort: 'oldest'),
      positional: ['i1'],
      named: {#page: 1, #size: 30, #sort: 'oldest'},
    );
    await expectForwarded(
      comments,
      #pinnedComments,
      () => Future.value(const [comment]),
      () => cubit.pinnedComments('i1'),
      positional: ['i1'],
    );
    await expectForwarded(
      comments,
      #commentReplies,
      () => Future.value((items: const [comment], total: 1)),
      () => cubit.commentReplies('i1', 'c0', page: 1, size: 10),
      positional: ['i1', 'c0'],
      named: {#page: 1, #size: 10},
    );
    await expectForwarded(
      comments,
      #addComment,
      () => Future.value(comment),
      () => cubit.addComment('i1', 'Hello', replyToId: 'c0', doc: '{}'),
      positional: ['i1', 'Hello'],
      named: {#replyToId: 'c0', #doc: '{}'},
    );
    await expectForwarded(
      comments,
      #addVoiceComment,
      () => Future.value(comment),
      () => cubit.addVoiceComment(
        'i1',
        bytes: const [1],
        mime: 'audio/mp4',
        durationMs: 1200,
        peaks: const [3, 4],
        replyToId: 'c0',
      ),
      positional: ['i1'],
      named: {
        #bytes: [1],
        #mime: 'audio/mp4',
        #durationMs: 1200,
        #peaks: [3, 4],
        #replyToId: 'c0',
      },
    );
    await expectForwarded(
      comments,
      #voiceCommentAudio,
      () => Future.value((bytes: const [1], contentType: 'audio/mp4')),
      () => cubit.voiceCommentAudio('i1', 'c1'),
      positional: ['i1', 'c1'],
    );
    await expectForwarded(
      comments,
      #editComment,
      () => Future.value(comment),
      () => cubit.editComment('i1', 'c1', 'Edited'),
      positional: ['i1', 'c1', 'Edited'],
    );
    await expectForwarded(
      comments,
      #deleteComment,
      () => Future<void>.value(),
      () => cubit.deleteComment('i1', 'c1'),
      positional: ['i1', 'c1'],
    );
    await expectForwarded(
      comments,
      #reactToComment,
      () => Future.value(comment),
      () => cubit.reactToComment('i1', 'c1', '👍'),
      positional: ['i1', 'c1', '👍'],
    );
    await expectForwarded(
      comments,
      #pinComment,
      () => Future.value(comment),
      () => cubit.pinComment('i1', 'c1', true),
      positional: ['i1', 'c1', true],
    );
    await expectForwarded(
      media,
      #uploadMedia,
      () => Future.value((url: '/api/v1/media/m1', blurHash: null)),
      () => cubit.uploadMedia(file),
      positional: [file],
    );
  });

  test('around the issue', () async {
    await expectForwarded(
      users,
      #users,
      () => Future.value(const <DirectoryUser>[]),
      cubit.users,
    );
    await expectForwarded(
      projects,
      #deleteProjectLabel,
      () => Future<void>.value(),
      () => cubit.deleteProjectLabel('p1', 'ux'),
      positional: ['p1', 'ux'],
    );
    const offset = RelativeDate(amount: 1);
    await expectForwarded(
      projects,
      #resolveOffset,
      () => Future<DateTime?>.value(null),
      () => cubit.resolveOffset('p1', offset: offset),
      positional: ['p1'],
      named: {#offset: offset},
    );
  });

  test('documented-in seeds the article cache first', () async {
    knowledge.answers[#init] = (_) => Future<void>.value();
    knowledge.answers[#articlesReferencingIssue] = (_) =>
        Future.value(const <KbArticle>[]);
    expect(await cubit.documentedIn('HIN-1'), isEmpty);
    expect(knowledge.calls.map((c) => c.memberName), [
      #init,
      #articlesReferencingIssue,
    ]);
    expect(knowledge.calls.last.positionalArguments, ['HIN-1']);
  });

  test('exports through the repository', () async {
    final bytes = Uint8List.fromList(const [37, 80, 68, 70]);
    issues.answers[#export] = (_) => Future.value(bytes);
    expect(await cubit.export('i1', 'pdf'), same(bytes));
    expect(issues.calls.single.positionalArguments, ['i1', 'pdf']);
  });

  test('passes a refusal on unchanged', () async {
    await expectFailurePassedOn<IssueComment>(
      comments,
      #addComment,
      () => cubit.addComment('i1', 'Hello'),
    );
    await expectFailurePassedOn<Issue>(
      issues,
      #updateIssue,
      () => cubit.updateIssue('i1', const {}),
    );
  });
}
