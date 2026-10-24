import 'package:equatable/equatable.dart';

import '../util/dates.dart';
import 'moderation_models.dart';

/// The one state of a case, as the moderation page words and draws it
/// (HIN-174). The server derives it; the app counts nothing.
enum CaseState {
  open('OPEN'),
  urgent('URGENT'),
  inReview('IN_REVIEW'),

  /// A decision that suspends a person with a role, waiting for a second
  /// person (HIN-172).
  pendingConfirmation('PENDING_CONFIRMATION'),
  appeal('APPEAL'),
  acted('ACTED'),
  noAction('NO_ACTION');

  const CaseState(this.wire);

  final String wire;

  /// Open for a value this app does not know: shown as waiting, which is the
  /// safe side for a list of things to look at.
  static CaseState of(Object? wire) => values.firstWhere(
    (state) => state.wire == wire,
    orElse: () => CaseState.open,
  );

  /// Still waiting for a decision.
  bool get undecided =>
      this == open ||
      this == urgent ||
      this == inReview ||
      this == pendingConfirmation;
}

/// The three lists of the moderation page.
enum CaseView {
  open('OPEN'),
  appeal('APPEAL'),
  done('DONE');

  const CaseView(this.wire);

  final String wire;

  static CaseView? of(Object? wire) {
    for (final view in values) {
      if (view.wire == wire) return view;
    }
    return null;
  }
}

/// Who brought a case: a member, somebody without an account, the text check,
/// or moderation itself.
enum ReportSource {
  member('MEMBER'),
  public('PUBLIC'),
  automated('AUTOMATED'),
  ownInitiative('OWN_INITIATIVE');

  const ReportSource(this.wire);

  final String wire;

  static ReportSource of(Object? wire) => values.firstWhere(
    (source) => source.wire == wire,
    orElse: () => ReportSource.member,
  );
}

/// How content came in. A sender header can be forged and a smart commit
/// stands under whoever connected the repository, so for those the person the
/// content is filed under is not treated as its author.
enum ContentOrigin {
  member('MEMBER'),
  email('EMAIL'),
  git('GIT'),
  mcp('MCP');

  const ContentOrigin(this.wire);

  final String wire;

  static ContentOrigin of(Object? wire) => values.firstWhere(
    (origin) => origin.wire == wire,
    orElse: () => ContentOrigin.member,
  );
}

/// What a moderator decides (HIN-171).
enum CaseOutcome {
  noViolation('NO_VIOLATION'),
  unfounded('UNFOUNDED'),
  action('ACTION'),

  /// Something else, dealt with outside Hinata.
  handled('HANDLED');

  const CaseOutcome(this.wire);

  final String wire;

  static CaseOutcome? of(Object? wire) {
    for (final outcome in values) {
      if (outcome.wire == wire) return outcome;
    }
    return null;
  }

  /// Something was done to content or a person.
  bool get acts => this == action || this == handled;
}

/// What a decision rests on.
enum DecisionGround {
  rules('RULES'),
  law('LAW');

  const DecisionGround(this.wire);

  final String wire;

  static DecisionGround? of(Object? wire) {
    for (final ground in values) {
      if (ground.wire == wire) return ground;
    }
    return null;
  }
}

/// How long a suspension keeps the person out (HIN-172).
enum SuspensionLength {
  days7('DAYS_7', Duration(days: 7)),
  days30('DAYS_30', Duration(days: 30)),
  indefinite('INDEFINITE', null);

  const SuspensionLength(this.wire, this.duration);

  final String wire;

  /// Null for until further notice.
  final Duration? duration;

  static SuspensionLength? of(Object? wire) {
    for (final length in values) {
      if (length.wire == wire) return length;
    }
    return null;
  }
}

/// One step in a case's history.
enum CaseEventKind {
  reported('REPORTED'),
  claimed('CLAIMED'),
  released('RELEASED'),
  reporterRevealed('REPORTER_REVEALED'),
  evidenceRequested('EVIDENCE_REQUESTED'),
  evidenceRevealed('EVIDENCE_REVEALED'),
  decided('DECIDED'),
  appealed('APPEALED'),
  appealDecided('APPEAL_DECIDED'),
  restored('RESTORED'),
  held('HELD'),
  confirmationRequested('CONFIRMATION_REQUESTED'),
  confirmationRejected('CONFIRMATION_REJECTED'),
  suspended('SUSPENDED'),
  suspensionLifted('SUSPENSION_LIFTED');

  const CaseEventKind(this.wire);

  final String wire;

  static CaseEventKind? of(Object? wire) {
    for (final kind in values) {
      if (kind.wire == wire) return kind;
    }
    return null;
  }
}

/// How an appeal came in.
enum AppealVia {
  app('APP'),
  reply('REPLY');

  const AppealVia(this.wire);

  final String wire;

  static AppealVia of(Object? wire) =>
      values.firstWhere((via) => via.wire == wire, orElse: () => AppealVia.app);
}

/// How an appeal is decided.
enum AppealResult {
  uphold('UPHOLD'),
  reverse('REVERSE');

  const AppealResult(this.wire);

  final String wire;
}

/// What putting removed content back came to.
enum RestoreOutcome {
  restored('RESTORED'),

  /// Somebody wrote it anew after the removal; their text stays.
  rewrittenSince('REWRITTEN_SINCE'),

  /// It no longer exists.
  gone('GONE');

  const RestoreOutcome(this.wire);

  final String wire;

  static RestoreOutcome? of(Object? wire) {
    for (final outcome in values) {
      if (outcome.wire == wire) return outcome;
    }
    return null;
  }
}

/// A decided case's content as it stands now, against what was reported.
enum SinceReport { unchanged, changed, deleted }

/// The minimum length of what a moderator found, and of every reason a step
/// after the decision asks for.
const caseNoteMin = 20;

/// The longest any of those may be.
const caseNoteMax = 2000;

/// A person as a case names them.
class PersonRef extends Equatable {
  const PersonRef({required this.id, this.displayName = '', this.avatarUrl});

  final String id;
  final String displayName;
  final String? avatarUrl;

  static PersonRef? fromJson(Object? json) => json is Map<String, dynamic>
      ? PersonRef(
          id: json['id'] as String? ?? '',
          displayName: json['displayName'] as String? ?? '',
          avatarUrl: _blankToNull(json['avatarUrl']),
        )
      : null;

  @override
  List<Object?> get props => [id, displayName, avatarUrl];
}

/// The numbers on the moderation page's pills, without the cases the reader
/// wrote content for.
class ModerationSummary extends Equatable {
  const ModerationSummary({
    this.open = 0,
    this.urgent = 0,
    this.overdue = 0,
    this.appeals = 0,
  });

  final int open;
  final int urgent;
  final int overdue;
  final int appeals;

  factory ModerationSummary.fromJson(Map<String, dynamic> json) =>
      ModerationSummary(
        open: _int(json['open']),
        urgent: _int(json['urgent']),
        overdue: _int(json['overdue']),
        appeals: _int(json['appeals']),
      );

  @override
  List<Object?> get props => [open, urgent, overdue, appeals];
}

/// One row of a list, built from the case alone.
class CaseSummary extends Equatable {
  const CaseSummary({
    required this.id,
    this.state = CaseState.open,
    this.urgent = false,
    this.kind = ContentKind.other,
    this.categories = const [],
    this.sources = const {},
    this.reportCount = 0,
    this.firstReportedAt,
    this.location,
    this.listExcerpt,
    this.assignee,
    this.reportedByMe = false,
    this.outcome,
    this.removed = false,
    this.suspended = false,
    this.rev = 0,
  });

  /// A case answers within a day.
  static const overdueAfter = Duration(hours: 24);

  final String id;
  final CaseState state;
  final bool urgent;
  final ContentKind kind;

  /// In the order the report sheet lists them, so the first is the one the
  /// row names.
  final List<ReportCategory> categories;
  final Set<ReportSource> sources;
  final int reportCount;
  final DateTime? firstReportedAt;
  final String? location;

  /// Null for a sensitive or a public case, and once nothing was wrong.
  final String? listExcerpt;
  final PersonRef? assignee;
  final bool reportedByMe;
  final CaseOutcome? outcome;
  final bool removed;
  final bool suspended;

  /// What every step on the case sends back, so a step on a case that moved
  /// meanwhile is refused.
  final int rev;

  ReportCategory get category =>
      categories.isEmpty ? ReportCategory.other : categories.first;

  /// About sexual content or the safety of children: covered in the list and
  /// its files only on request, or never.
  bool get sensitive =>
      categories.contains(ReportCategory.sexual) ||
      categories.contains(ReportCategory.childSafety);

  bool get childSafety => categories.contains(ReportCategory.childSafety);

  /// Undecided for longer than a day at [now].
  bool overdueAt(DateTime now) =>
      state.undecided &&
      firstReportedAt != null &&
      !now.difference(firstReportedAt!).isNegative &&
      now.difference(firstReportedAt!) >= overdueAfter;

  factory CaseSummary.fromJson(Map<String, dynamic> json) {
    final categories = {
      for (final wire in (json['categories'] as List<dynamic>?) ?? const [])
        ReportCategory.of(wire),
    };
    return CaseSummary(
      id: json['id'] as String? ?? '',
      state: CaseState.of(json['state']),
      urgent: json['urgent'] as bool? ?? false,
      kind: ContentKind.of(json['kind']),
      categories: [
        for (final category in ReportCategory.values)
          if (categories.contains(category)) category,
      ],
      sources: {
        for (final wire in (json['sources'] as List<dynamic>?) ?? const [])
          ReportSource.of(wire),
      },
      reportCount: _int(json['reportCount']),
      firstReportedAt: parseInstant(json['firstReportedAt']),
      location: _blankToNull(json['location']),
      listExcerpt: _blankToNull(json['listExcerpt']),
      assignee: PersonRef.fromJson(json['assignee']),
      reportedByMe: json['reportedByMe'] as bool? ?? false,
      outcome: CaseOutcome.of(json['outcome']),
      removed: json['removed'] as bool? ?? false,
      suspended: json['suspended'] as bool? ?? false,
      rev: _int(json['rev']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    state,
    urgent,
    kind,
    categories,
    sources,
    reportCount,
    firstReportedAt,
    location,
    listExcerpt,
    assignee,
    reportedByMe,
    outcome,
    removed,
    suspended,
    rev,
  ];
}

/// One stored object a content consists of or embeds, addressed by its index
/// in the case's evidence.
class CaseMedia extends Equatable {
  const CaseMedia({this.fileName, this.contentType, this.size = 0});

  final String? fileName;
  final String? contentType;
  final int size;

  bool get image => contentType?.startsWith('image/') ?? false;

  factory CaseMedia.fromJson(Map<String, dynamic> json) => CaseMedia(
    fileName: _blankToNull(json['fileName']),
    contentType: _blankToNull(json['contentType']),
    size: _int(json['size']),
  );

  @override
  List<Object?> get props => [fileName, contentType, size];
}

/// Content as moderation sees it: who wrote it, what it says, where it stands.
class CaseContent extends Equatable {
  const CaseContent({
    this.kind = ContentKind.other,
    this.id,
    this.parentId,
    this.origin = ContentOrigin.member,
    this.externalSender,
    this.contributorIds = const [],
    this.lastEditorId,
    this.title,
    this.excerpt = '',
    this.context,
    this.location,
    this.media = const [],
    this.createdAt,
    this.editedAt,
    this.contentHash,
    this.removed = false,
  });

  final ContentKind kind;
  final String? id;

  /// The issue of a comment or an attachment.
  final String? parentId;
  final ContentOrigin origin;

  /// The sender of content that came in by mail.
  final String? externalSender;

  /// Everyone who wrote the state that is seen.
  final List<String> contributorIds;

  /// Who changed it last: the person the decision is suggested to be about.
  final String? lastEditorId;
  final String? title;

  /// The text, plain, at most 4000 characters.
  final String excerpt;

  /// What it belongs to, such as the comment it answers.
  final String? context;

  /// Where it is found, such as `MESSE-14`.
  final String? location;
  final List<CaseMedia> media;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final String? contentHash;
  final bool removed;

  /// The person a decision is about unless the moderator picks another.
  String? get suggestedResponsible =>
      lastEditorId != null && contributorIds.contains(lastEditorId)
      ? lastEditorId
      : (contributorIds.isEmpty ? null : contributorIds.first);

  static CaseContent? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final ref = json['ref'] is Map<String, dynamic>
        ? json['ref'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return CaseContent(
      kind: ContentKind.of(ref['kind']),
      id: ref['id'] as String?,
      parentId: ref['parentId'] as String?,
      origin: ContentOrigin.of(json['origin']),
      externalSender: _blankToNull(json['externalSender']),
      contributorIds: [
        for (final id in (json['contributorIds'] as List<dynamic>?) ?? const [])
          '$id',
      ],
      lastEditorId: json['lastEditorId'] as String?,
      title: _blankToNull(json['title']),
      excerpt: json['excerpt'] as String? ?? '',
      context: _blankToNull(json['context']),
      location: _blankToNull(json['location']),
      media: [
        for (final media in (json['media'] as List<dynamic>?) ?? const [])
          if (media is Map<String, dynamic>) CaseMedia.fromJson(media),
      ],
      createdAt: parseInstant(json['createdAt']),
      editedAt: parseInstant(json['editedAt']),
      contentHash: json['contentHash'] as String?,
      removed: json['removed'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
    kind,
    id,
    parentId,
    origin,
    externalSender,
    contributorIds,
    lastEditorId,
    title,
    excerpt,
    context,
    location,
    media,
    createdAt,
    editedAt,
    contentHash,
    removed,
  ];
}

/// One report as moderators see it: numbered, by kind of source, covered until
/// somebody uncovers it with a reason.
class CaseReport extends Equatable {
  const CaseReport({
    required this.id,
    this.number = 0,
    this.source = ReportSource.member,
    this.category = ReportCategory.other,
    this.explanation,
    this.createdAt,
    this.reporter,
    this.unfoundedChildSafetyBefore = 0,
  });

  final String id;
  final int number;
  final ReportSource source;
  final ReportCategory category;
  final String? explanation;
  final DateTime? createdAt;

  /// Null until uncovered.
  final PersonRef? reporter;

  /// How many earlier child-safety reports of the same source were decided as
  /// manifestly unfounded; only the number.
  final int unfoundedChildSafetyBefore;

  factory CaseReport.fromJson(Map<String, dynamic> json) => CaseReport(
    id: json['id'] as String? ?? '',
    number: _int(json['number']),
    source: ReportSource.of(json['source']),
    category: ReportCategory.of(json['category']),
    explanation: _blankToNull(json['explanation']),
    createdAt: parseInstant(json['createdAt']),
    reporter: PersonRef.fromJson(json['reporter']),
    unfoundedChildSafetyBefore: _int(json['unfoundedChildSafetyBefore']),
  );

  @override
  List<Object?> get props => [
    id,
    number,
    source,
    category,
    explanation,
    createdAt,
    reporter,
    unfoundedChildSafetyBefore,
  ];
}

/// One step in a case's history; [actorId] is null for the first report.
class CaseEvent extends Equatable {
  const CaseEvent({this.at, this.kind, this.actorId, this.detail});

  final DateTime? at;

  /// Null for a step this app does not know yet, which it leaves out.
  final CaseEventKind? kind;
  final String? actorId;

  /// What the step names, such as the reason given; never content.
  final String? detail;

  factory CaseEvent.fromJson(Map<String, dynamic> json) => CaseEvent(
    at: parseInstant(json['at']),
    kind: CaseEventKind.of(json['kind']),
    actorId: json['actorId'] as String?,
    detail: _blankToNull(json['detail']),
  );

  @override
  List<Object?> get props => [at, kind, actorId, detail];
}

/// What a moderator decided on a case, and why.
class CaseDecision extends Equatable {
  const CaseDecision({
    this.outcome,
    this.removal,
    this.ground,
    this.category,
    this.facts,
    this.ruleReference,
    this.lawReference,
    this.responsibleId,
    this.deceptiveCommercial = false,
    this.messageToAuthor,
    this.internalNote,
    this.lawEnforcementNotified = false,
    this.automatedDetection = false,
    this.decidedBy,
    this.decidedAt,
    this.suspension,
    this.confirmedBy,
  });

  final CaseOutcome? outcome;
  final RemovalScope? removal;
  final DecisionGround? ground;
  final ReportCategory? category;
  final String? facts;
  final String? ruleReference;
  final String? lawReference;
  final String? responsibleId;
  final bool deceptiveCommercial;
  final String? messageToAuthor;
  final String? internalNote;
  final bool lawEnforcementNotified;
  final bool automatedDetection;
  final String? decidedBy;
  final DateTime? decidedAt;
  final SuspensionLength? suspension;
  final String? confirmedBy;

  /// The rule or the law, whichever the decision rests on.
  String? get reference =>
      ground == DecisionGround.law ? lawReference : ruleReference;

  static CaseDecision? fromJson(Object? json) => json is Map<String, dynamic>
      ? CaseDecision(
          outcome: CaseOutcome.of(json['outcome']),
          removal: RemovalScope.of(json['removal']),
          ground: DecisionGround.of(json['ground']),
          category: json['category'] == null
              ? null
              : ReportCategory.of(json['category']),
          facts: _blankToNull(json['facts']),
          ruleReference: _blankToNull(json['ruleReference']),
          lawReference: _blankToNull(json['lawReference']),
          responsibleId: json['responsibleId'] as String?,
          deceptiveCommercial: json['deceptiveCommercial'] as bool? ?? false,
          messageToAuthor: _blankToNull(json['messageToAuthor']),
          internalNote: _blankToNull(json['internalNote']),
          lawEnforcementNotified:
              json['lawEnforcementNotified'] as bool? ?? false,
          automatedDetection: json['automatedDetection'] as bool? ?? false,
          decidedBy: json['decidedBy'] as String?,
          decidedAt: parseInstant(json['decidedAt']),
          suspension: SuspensionLength.of(json['suspension']),
          confirmedBy: json['confirmedBy'] as String?,
        )
      : null;

  @override
  List<Object?> get props => [
    outcome,
    removal,
    ground,
    category,
    facts,
    ruleReference,
    lawReference,
    responsibleId,
    deceptiveCommercial,
    messageToAuthor,
    internalNote,
    lawEnforcementNotified,
    automatedDetection,
    decidedBy,
    decidedAt,
    suspension,
    confirmedBy,
  ];
}

/// The person responsible objecting to a decision.
class CaseAppeal extends Equatable {
  const CaseAppeal({
    this.state,
    this.text = '',
    this.filedAt,
    this.via = AppealVia.app,
    this.decidedBy,
    this.decidedAt,
    this.note,
    this.restored,
  });

  final AppealState? state;
  final String text;
  final DateTime? filedAt;
  final AppealVia via;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? note;
  final RestoreOutcome? restored;

  bool get pending => state == AppealState.pending;

  static CaseAppeal? fromJson(Object? json) => json is Map<String, dynamic>
      ? CaseAppeal(
          state: AppealState.of(json['state']),
          text: json['text'] as String? ?? '',
          filedAt: parseInstant(json['filedAt']),
          via: AppealVia.of(json['via']),
          decidedBy: json['decidedBy'] as String?,
          decidedAt: parseInstant(json['decidedAt']),
          note: _blankToNull(json['note']),
          restored: RestoreOutcome.of(json['restored']),
        )
      : null;

  @override
  List<Object?> get props => [
    state,
    text,
    filedAt,
    via,
    decidedBy,
    decidedAt,
    note,
    restored,
  ];
}

/// A removal undone, after an appeal or by moderation itself.
class CaseRestoration extends Equatable {
  const CaseRestoration({this.at, this.by, this.note, this.outcome});

  final DateTime? at;
  final String? by;
  final String? note;
  final RestoreOutcome? outcome;

  static CaseRestoration? fromJson(Object? json) => json is Map<String, dynamic>
      ? CaseRestoration(
          at: parseInstant(json['at']),
          by: json['by'] as String?,
          note: _blankToNull(json['note']),
          outcome: RestoreOutcome.of(json['outcome']),
        )
      : null;

  @override
  List<Object?> get props => [at, by, note, outcome];
}

/// Opening what somebody without an account reported on internal content: a
/// second person confirms what the first asked for.
class EvidenceReveal extends Equatable {
  const EvidenceReveal({
    this.requestedBy,
    this.requestedAt,
    this.reason,
    this.revealedBy,
    this.revealedAt,
  });

  final String? requestedBy;
  final DateTime? requestedAt;
  final String? reason;
  final String? revealedBy;
  final DateTime? revealedAt;

  bool get revealed => revealedAt != null;

  static EvidenceReveal? fromJson(Object? json) => json is Map<String, dynamic>
      ? EvidenceReveal(
          requestedBy: json['requestedBy'] as String?,
          requestedAt: parseInstant(json['requestedAt']),
          reason: _blankToNull(json['reason']),
          revealedBy: json['revealedBy'] as String?,
          revealedAt: parseInstant(json['revealedAt']),
        )
      : null;

  @override
  List<Object?> get props => [
    requestedBy,
    requestedAt,
    reason,
    revealedBy,
    revealedAt,
  ];
}

/// Other content that showed an image the removal moved out of all of them,
/// for moderation to look at as well (HIN-169).
class OtherUse extends Equatable {
  const OtherUse({required this.kind, this.id, this.parentId, this.location});

  final ContentKind kind;
  final String? id;
  final String? parentId;

  /// The key of the issue it stands in; null for a page or a person.
  final String? location;

  factory OtherUse.fromJson(Map<String, dynamic> json) => OtherUse(
    kind: ContentKind.of(json['kind']),
    id: json['id'] as String?,
    parentId: json['parentId'] as String?,
    location: _blankToNull(json['location']),
  );

  @override
  List<Object?> get props => [kind, id, parentId, location];
}

/// A case opened: what was reported, how it stands now while it is open, and
/// what happened.
class CaseDetail extends Equatable {
  const CaseDetail({
    required this.summary,
    this.evidence,
    this.current,
    this.evidenceWithheld = false,
    this.evidenceReveal,
    this.reports = const [],
    this.reportTotal = 0,
    this.history = const [],
    this.claimedAt,
    this.decision,
    this.appeal,
    this.restoration,
    this.removalIncomplete = false,
    this.otherUses = const [],
  });

  final CaseSummary summary;

  /// What was reported, as it was; null while withheld and once nothing was
  /// wrong.
  final CaseContent? evidence;

  /// How it stands now, while the case is open.
  final CaseContent? current;

  /// Reported without an account on internal content: closed until a second
  /// person opens it.
  final bool evidenceWithheld;
  final EvidenceReveal? evidenceReveal;

  /// The first reports; [reportTotal] counts them all.
  final List<CaseReport> reports;
  final int reportTotal;
  final List<CaseEvent> history;
  final DateTime? claimedAt;
  final CaseDecision? decision;
  final CaseAppeal? appeal;
  final CaseRestoration? restoration;

  /// The decided removal is still being carried out.
  final bool removalIncomplete;
  final List<OtherUse> otherUses;

  String get id => summary.id;

  /// How the content stands against what was reported, while the case is open
  /// and its content can be seen; null otherwise.
  SinceReport? get sinceReport {
    if (!summary.state.undecided ||
        evidenceWithheld ||
        evidence == null ||
        summary.kind == ContentKind.other) {
      return null;
    }
    final now = current;
    if (now == null) return SinceReport.deleted;
    return now.contentHash == evidence!.contentHash
        ? SinceReport.unchanged
        : SinceReport.changed;
  }

  /// Every person the case names by id, to look their names up at once.
  Set<String> get personIds => {
    for (final event in history)
      if (event.actorId != null) event.actorId!,
    ?decision?.decidedBy,
    ?decision?.confirmedBy,
    ?decision?.responsibleId,
    ?appeal?.decidedBy,
    ?restoration?.by,
    ?evidenceReveal?.requestedBy,
    ?evidenceReveal?.revealedBy,
    ...?evidence?.contributorIds,
  };

  CaseDetail copyWith({CaseSummary? summary, List<CaseReport>? reports}) =>
      CaseDetail(
        summary: summary ?? this.summary,
        evidence: evidence,
        current: current,
        evidenceWithheld: evidenceWithheld,
        evidenceReveal: evidenceReveal,
        reports: reports ?? this.reports,
        reportTotal: reportTotal,
        history: history,
        claimedAt: claimedAt,
        decision: decision,
        appeal: appeal,
        restoration: restoration,
        removalIncomplete: removalIncomplete,
        otherUses: otherUses,
      );

  factory CaseDetail.fromJson(Map<String, dynamic> json) => CaseDetail(
    summary: CaseSummary.fromJson(
      json['summary'] as Map<String, dynamic>? ?? const {},
    ),
    evidence: CaseContent.fromJson(json['evidence']),
    current: CaseContent.fromJson(json['current']),
    evidenceWithheld: json['evidenceWithheld'] as bool? ?? false,
    evidenceReveal: EvidenceReveal.fromJson(json['evidenceReveal']),
    reports: [
      for (final report in (json['reports'] as List<dynamic>?) ?? const [])
        if (report is Map<String, dynamic>) CaseReport.fromJson(report),
    ],
    reportTotal: _int(json['reportTotal']),
    history: [
      for (final event in (json['history'] as List<dynamic>?) ?? const [])
        if (event is Map<String, dynamic>) CaseEvent.fromJson(event),
    ],
    claimedAt: parseInstant(json['claimedAt']),
    decision: CaseDecision.fromJson(json['decision']),
    appeal: CaseAppeal.fromJson(json['appeal']),
    restoration: CaseRestoration.fromJson(json['restoration']),
    removalIncomplete: json['removalState'] == 'INCOMPLETE',
    otherUses: [
      for (final use in (json['otherUses'] as List<dynamic>?) ?? const [])
        if (use is Map<String, dynamic>) OtherUse.fromJson(use),
    ],
  );

  @override
  List<Object?> get props => [
    summary,
    evidence,
    current,
    evidenceWithheld,
    evidenceReveal,
    reports,
    reportTotal,
    history,
    claimedAt,
    decision,
    appeal,
    restoration,
    removalIncomplete,
    otherUses,
  ];
}

/// One numbered house rule a decision can rest on.
class HouseRule extends Equatable {
  const HouseRule(this.number, this.title);

  final int number;
  final String title;

  @override
  List<Object?> get props => [number, title];
}

/// The house rules to pick from: the built-in ones the numbers refer to, the
/// version in force, and which rule each category of report is about.
class ModerationRules extends Equatable {
  const ModerationRules({
    this.version,
    this.builtIn = true,
    this.rules = const [],
    this.categoryRules = const {},
  });

  final int? version;

  /// The rules in force are the built-in ones; otherwise an instance's own
  /// text or page, which the numbers do not refer to.
  final bool builtIn;
  final List<HouseRule> rules;
  final Map<ReportCategory, int> categoryRules;

  /// The rule a category of report is about, if it is listed.
  HouseRule? ruleFor(ReportCategory category) {
    final number = categoryRules[category];
    for (final rule in rules) {
      if (rule.number == number) return rule;
    }
    return null;
  }

  factory ModerationRules.fromJson(Map<String, dynamic> json) =>
      ModerationRules(
        version: (json['version'] as num?)?.toInt(),
        builtIn: json['builtIn'] as bool? ?? true,
        rules: [
          for (final rule in (json['rules'] as List<dynamic>?) ?? const [])
            if (rule is Map<String, dynamic>)
              HouseRule(_int(rule['number']), rule['title'] as String? ?? ''),
        ],
        categoryRules: {
          for (final pair in (json['categories'] as List<dynamic>?) ?? const [])
            if (pair is Map<String, dynamic>)
              ReportCategory.of(pair['category']): _int(pair['rule']),
        },
      );

  @override
  List<Object?> get props => [version, builtIn, rules, categoryRules];
}

/// An account moderation suspended, as the list of suspended accounts shows
/// it; [until] null for until further notice.
class SuspendedAccount extends Equatable {
  const SuspendedAccount({
    required this.person,
    this.since,
    this.until,
    this.caseId,
  });

  final PersonRef person;
  final DateTime? since;
  final DateTime? until;
  final String? caseId;

  factory SuspendedAccount.fromJson(Map<String, dynamic> json) =>
      SuspendedAccount(
        person: PersonRef.fromJson(json['person']) ?? const PersonRef(id: ''),
        since: parseInstant(json['since']),
        until: parseInstant(json['until']),
        caseId: json['caseId'] as String?,
      );

  @override
  List<Object?> get props => [person, since, until, caseId];
}

/// A decision as a moderator makes it, sent with the revision they saw.
class DecisionDraft extends Equatable {
  const DecisionDraft({
    required this.rev,
    required this.outcome,
    this.removal,
    this.ground,
    this.category,
    this.facts = '',
    this.ruleReference,
    this.lawReference,
    this.responsibleId,
    this.deceptiveCommercial = false,
    this.messageToAuthor = '',
    this.internalNote = '',
    this.lawEnforcementNotified = false,
    this.suspension,
  });

  final int rev;
  final CaseOutcome outcome;
  final RemovalScope? removal;
  final DecisionGround? ground;
  final ReportCategory? category;
  final String facts;
  final String? ruleReference;
  final String? lawReference;
  final String? responsibleId;
  final bool deceptiveCommercial;
  final String messageToAuthor;
  final String internalNote;
  final bool lawEnforcementNotified;
  final SuspensionLength? suspension;

  Map<String, dynamic> toJson() => {
    'rev': rev,
    'outcome': outcome.wire,
    if (removal != null) 'removal': {'scope': removal!.wire},
    'ground': ?ground?.wire,
    'category': ?category?.wire,
    'facts': ?_trimmed(facts),
    'ruleReference': ?_trimmed(ruleReference),
    'lawReference': ?_trimmed(lawReference),
    'responsibleId': ?responsibleId,
    'deceptiveCommercial': deceptiveCommercial,
    'messageToAuthor': ?_trimmed(messageToAuthor),
    'internalNote': ?_trimmed(internalNote),
    'lawEnforcementNotified': lawEnforcementNotified,
    if (suspension != null) 'suspension': {'duration': suspension!.wire},
  };

  @override
  List<Object?> get props => [
    rev,
    outcome,
    removal,
    ground,
    category,
    facts,
    ruleReference,
    lawReference,
    responsibleId,
    deceptiveCommercial,
    messageToAuthor,
    internalNote,
    lawEnforcementNotified,
    suspension,
  ];
}

String? _trimmed(String? text) {
  final trimmed = text?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _blankToNull(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

int _int(Object? value) => (value as num?)?.toInt() ?? 0;
