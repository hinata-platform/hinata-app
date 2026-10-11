import 'package:equatable/equatable.dart';

import '../../core/models/work_models.dart';

enum KnowledgeStatus { loading, ready, failure }

/// What the knowledge screen renders from.
///
/// The pages and spaces themselves stay in the shared [KnowledgeRepository]
/// cache, which every view reads synchronously while it builds. [revision]
/// moves on every change to that cache, so a view rebuilds exactly when what
/// it reads may have changed.
class KnowledgeState extends Equatable {
  const KnowledgeState({
    this.status = KnowledgeStatus.loading,
    this.revision = 0,
    this.issuesByReadable = const {},
    this.userNames = const {},
  });

  final KnowledgeStatus status;
  final int revision;

  /// Every issue the reader sees, by every readable id it ever had, so a
  /// smart link to a moved issue keeps resolving.
  final Map<String, Issue> issuesByReadable;

  /// Member names by id, for smart links and the `@` menu.
  final Map<String, String> userNames;

  KnowledgeState copyWith({
    KnowledgeStatus? status,
    int? revision,
    Map<String, Issue>? issuesByReadable,
    Map<String, String>? userNames,
  }) => KnowledgeState(
    status: status ?? this.status,
    revision: revision ?? this.revision,
    issuesByReadable: issuesByReadable ?? this.issuesByReadable,
    userNames: userNames ?? this.userNames,
  );

  @override
  List<Object?> get props => [status, revision, issuesByReadable, userNames];
}
