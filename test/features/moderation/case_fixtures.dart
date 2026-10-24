import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/core/models/moderation_models.dart';

/// Cases as the moderation page meets them (HIN-174), shared by its tests.
final reportedAt = DateTime.utc(2026, 10, 22, 9, 14);

CaseSummary caseRow({
  String id = 'k1',
  CaseState state = CaseState.open,
  ContentKind kind = ContentKind.comment,
  List<ReportCategory> categories = const [ReportCategory.harassment],
  Set<ReportSource> sources = const {ReportSource.member},
  int reportCount = 2,
  DateTime? firstReportedAt,
  String? location = 'MESSE-14 · Standaufbau Halle 4',
  String? listExcerpt = 'Du bist echt zu blöd für diesen Job.',
  PersonRef? assignee,
  bool reportedByMe = false,
  bool overdue = false,
  CaseOutcome? outcome,
  int rev = 3,
}) => CaseSummary(
  id: id,
  state: state,
  kind: kind,
  categories: categories,
  sources: sources,
  reportCount: reportCount,
  firstReportedAt: firstReportedAt ?? reportedAt,
  location: location,
  listExcerpt: listExcerpt,
  assignee: assignee,
  reportedByMe: reportedByMe,
  overdue: overdue,
  outcome: outcome,
  rev: rev,
);

const jonas = 'jonas';

CaseContent comment({
  String hash = 'a',
  List<CaseMedia> media = const [],
  List<String> contributors = const [jonas],
}) => CaseContent(
  kind: ContentKind.comment,
  id: 'c1',
  parentId: 'i1',
  contributorIds: contributors,
  lastEditorId: contributors.isEmpty ? null : contributors.first,
  excerpt: 'Du bist echt zu blöd für diesen Job. Halt dich da raus.',
  context: 'Lena Vogt: Kannst du die Paletten bestellen?',
  location: 'MESSE-14',
  media: media,
  createdAt: DateTime.utc(2026, 10, 21, 16, 2),
  contentHash: hash,
);

CaseDetail caseDetail({
  CaseSummary? summary,
  CaseContent? evidence,
  String? currentHash,
  bool withheld = false,
  EvidenceReveal? reveal,
  List<CaseReport>? reports,
  int? reportTotal,
  List<CaseEvent> history = const [],
  CaseDecision? decision,
  CaseAppeal? appeal,
  bool removalIncomplete = false,
  List<OtherUse> otherUses = const [],
  bool noCurrent = false,
  bool takeOverAllowed = false,
}) {
  final shown =
      reports ??
      [
        CaseReport(
          id: 'r1',
          number: 1,
          category: ReportCategory.harassment,
          explanation: 'Das geht seit Wochen so.',
          createdAt: reportedAt,
        ),
      ];
  return CaseDetail(
    summary: summary ?? caseRow(),
    evidence: withheld ? null : evidence ?? comment(),
    currentHash: withheld || noCurrent
        ? null
        : currentHash ?? (evidence ?? comment()).contentHash,
    evidenceWithheld: withheld,
    evidenceReveal: reveal,
    reports: shown,
    reportTotal: reportTotal ?? shown.length,
    history: history,
    takeOverAllowed: takeOverAllowed,
    decision: decision,
    appeal: appeal,
    removalIncomplete: removalIncomplete,
    otherUses: otherUses,
  );
}
