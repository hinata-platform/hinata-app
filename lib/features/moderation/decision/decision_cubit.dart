import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/models/person_profile.dart';
import '../../../core/repositories/moderation_repository.dart';
import '../../../core/repositories/user_repository.dart';
import '../case/case_detail_cubit.dart' show movedMeanwhile;

/// What still keeps a decision from going out, each said beside its field.
enum DecisionProblem { outcome, measure, scope, reference, facts, suspension }

/// What a removal can take of each kind of content, in the order offered.
List<RemovalScope> scopesOf(ContentKind kind) => switch (kind) {
  ContentKind.issue => const [
    RemovalScope.title,
    RemovalScope.description,
    RemovalScope.whole,
  ],
  ContentKind.comment || ContentKind.attachment => const [RemovalScope.whole],
  ContentKind.article => const [RemovalScope.revert, RemovalScope.whole],
  ContentKind.person => const [
    RemovalScope.avatar,
    RemovalScope.profileText,
    RemovalScope.whole,
  ],
  ContentKind.other => const [],
};

/// The outcomes a case of [kind] offers: something else has no content to
/// act on, only to be dealt with.
List<CaseOutcome> outcomesOf(ContentKind kind) => kind == ContentKind.other
    ? const [CaseOutcome.noViolation, CaseOutcome.handled]
    : const [
        CaseOutcome.noViolation,
        CaseOutcome.unfounded,
        CaseOutcome.action,
      ];

class DecisionState extends Equatable {
  const DecisionState({
    this.outcome,
    this.remove = false,
    this.scope,
    this.suspend = false,
    this.duration = SuspensionLength.days7,
    this.ground = DecisionGround.rules,
    this.rule,
    this.ruleText = '',
    this.lawReference = '',
    this.facts = '',
    this.message = '',
    this.internalNote = '',
    this.lawEnforcement = false,
    this.deceptiveCommercial = false,
    this.responsibleId,
    this.rules,
    this.responsible,
    this.previewBase,
    this.previewLoading = false,
    this.previewFailed = false,
    this.sending = false,
    this.showProblems = false,
    this.errorKey,
    this.closedWith,
  });

  final CaseOutcome? outcome;
  final bool remove;
  final RemovalScope? scope;
  final bool suspend;
  final SuspensionLength duration;
  final DecisionGround ground;

  /// The built-in house rule picked, when the rules in force are built in.
  final HouseRule? rule;

  /// The rule in words, when an instance has its own rules.
  final String ruleText;
  final String lawReference;
  final String facts;
  final String message;
  final String internalNote;
  final bool lawEnforcement;
  final bool deceptiveCommercial;

  /// Whom the statement is about; null lets the server pick who wrote it last.
  final String? responsibleId;
  final ModerationRules? rules;

  /// The person the decision is about, for whether they can be suspended.
  final PersonProfile? responsible;

  /// The statement as the server last worded it, with marks where the free
  /// texts go.
  final Statement? previewBase;
  final bool previewLoading;
  final bool previewFailed;
  final bool sending;

  /// Problems are shown once sending was tried, not while still filling in.
  final bool showProblems;
  final String? errorKey;

  /// Set once the dialog is done: what to tell the reader on the case.
  final String? closedWith;

  bool get acting => outcome == CaseOutcome.action;

  /// The rules in force are the built-in ones, which are picked from a list.
  bool get pickRule => rules?.builtIn ?? true;

  /// Somebody with an administrator's role is never suspended.
  bool get responsibleIsAdmin => responsible?.isAdmin ?? false;

  /// Suspending a moderator or an organisation admin waits for a second
  /// person (HIN-172).
  bool get needsSecondPerson =>
      (responsible?.isModerator ?? false) || (responsible?.isOrgAdmin ?? false);

  /// The preview as the person will read it, with what is typed right now.
  Statement? get preview {
    final base = previewBase;
    if (base == null) return null;
    return base.withTexts(
      facts: _orNull(facts),
      messageToAuthor: _orNull(message),
      groundText: base.groundText
          ?.replaceAll(DecisionCubit.lawMark, lawReference.trim())
          .replaceAll(DecisionCubit.ruleMark, ruleText.trim()),
    );
  }

  DecisionState copyWith({
    CaseOutcome? outcome,
    bool? remove,
    RemovalScope? scope,
    bool clearScope = false,
    bool? suspend,
    SuspensionLength? duration,
    DecisionGround? ground,
    HouseRule? rule,
    String? ruleText,
    String? lawReference,
    String? facts,
    String? message,
    String? internalNote,
    bool? lawEnforcement,
    bool? deceptiveCommercial,
    String? responsibleId,
    ModerationRules? rules,
    PersonProfile? responsible,
    bool clearResponsible = false,
    Statement? previewBase,
    bool clearPreview = false,
    bool? previewLoading,
    bool? previewFailed,
    bool? sending,
    bool? showProblems,
    String? errorKey,
    String? closedWith,
  }) => DecisionState(
    outcome: outcome ?? this.outcome,
    remove: remove ?? this.remove,
    scope: clearScope ? null : scope ?? this.scope,
    suspend: suspend ?? this.suspend,
    duration: duration ?? this.duration,
    ground: ground ?? this.ground,
    rule: rule ?? this.rule,
    ruleText: ruleText ?? this.ruleText,
    lawReference: lawReference ?? this.lawReference,
    facts: facts ?? this.facts,
    message: message ?? this.message,
    internalNote: internalNote ?? this.internalNote,
    lawEnforcement: lawEnforcement ?? this.lawEnforcement,
    deceptiveCommercial: deceptiveCommercial ?? this.deceptiveCommercial,
    responsibleId: responsibleId ?? this.responsibleId,
    rules: rules ?? this.rules,
    responsible: clearResponsible ? null : responsible ?? this.responsible,
    previewBase: clearPreview ? null : previewBase ?? this.previewBase,
    previewLoading: previewLoading ?? this.previewLoading,
    previewFailed: previewFailed ?? this.previewFailed,
    sending: sending ?? this.sending,
    showProblems: showProblems ?? this.showProblems,
    // A refusal is said once.
    errorKey: errorKey,
    closedWith: closedWith ?? this.closedWith,
  );

  @override
  List<Object?> get props => [
    outcome,
    remove,
    scope,
    suspend,
    duration,
    ground,
    rule,
    ruleText,
    lawReference,
    facts,
    message,
    internalNote,
    lawEnforcement,
    deceptiveCommercial,
    responsibleId,
    rules,
    responsible,
    previewBase,
    previewLoading,
    previewFailed,
    sending,
    showProblems,
    errorKey,
    closedWith,
  ];
}

/// Deciding a case (HIN-174): the outcome, what an action takes, the ground,
/// what was found, and the statement worded as the person will read it before
/// it goes out.
///
/// The preview asks the server only when something structured changes: the
/// outcome, the scope, the length, the ground, the rule, the person, a switch.
/// What is typed (the facts, the law, the message) goes into the last answer
/// here, so typing costs no requests from the shared budget of 300 a minute.
/// Only the newest answer counts.
class DecisionCubit extends Cubit<DecisionState> {
  DecisionCubit(
    this._moderation,
    this._users, {
    required this.detail,
    bool suspendPerson = false,
  }) : super(
         DecisionState(
           outcome: suspendPerson ? CaseOutcome.action : null,
           suspend: suspendPerson,
           responsibleId: detail.evidence?.suggestedResponsible,
         ),
       );

  final ModerationRepository _moderation;
  final UserRepository _users;
  final CaseDetail detail;

  /// Where the free texts go in a preview; never shown, always replaced.
  static const factsMark = '[[hinata.preview.facts]]';
  static const lawMark = '[[hinata.preview.law]]';
  static const ruleMark = '[[hinata.preview.rule]]';

  int _previewToken = 0;
  int _personToken = 0;
  Object? _previewKey;

  ContentKind get kind => detail.summary.kind;

  /// The case's category, unless the rule picked is about another.
  ReportCategory get category {
    final reported = detail.summary.category;
    final rule = state.rule;
    final rules = state.rules;
    if (state.ground != DecisionGround.rules || rule == null || rules == null) {
      return reported;
    }
    if (rules.categoryRules[reported] == rule.number) return reported;
    for (final category in ReportCategory.values) {
      if (rules.categoryRules[category] == rule.number) return category;
    }
    return reported;
  }

  /// Content from a mail or a smart commit has nobody with an account behind
  /// it to suspend.
  bool get canSuspend {
    final origin = detail.evidence?.origin;
    return state.responsible != null &&
        !state.responsibleIsAdmin &&
        origin != ContentOrigin.email &&
        origin != ContentOrigin.git;
  }

  /// Everybody who wrote the content, when there is a choice to make.
  List<String> get contributors => detail.evidence?.contributorIds ?? const [];

  Set<DecisionProblem> get problems {
    final s = state;
    final outcome = s.outcome;
    if (outcome == null) return const {DecisionProblem.outcome};
    return {
      if (outcome == CaseOutcome.action && !s.remove && !s.suspend)
        DecisionProblem.measure,
      if (s.acting && s.remove && s.scope == null) DecisionProblem.scope,
      if (s.acting && _reference().isEmpty) DecisionProblem.reference,
      if (outcome != CaseOutcome.noViolation &&
          s.facts.trim().length < caseNoteMin)
        DecisionProblem.facts,
      if (s.acting && s.suspend && !canSuspend) DecisionProblem.suspension,
    };
  }

  /// Reads the rules and the person the decision is about.
  Future<void> start() async {
    await Future.wait([_loadRules(), _loadResponsible()]);
  }

  Future<void> _loadRules() async {
    try {
      final rules = await _moderation.rules();
      if (isClosed) return;
      final reported = rules.ruleFor(detail.summary.category);
      emit(state.copyWith(rules: rules, rule: state.rule ?? reported));
      _maybePreview();
    } catch (_) {
      // Without the list the rule is written out by hand.
      if (isClosed) return;
      emit(state.copyWith(rules: const ModerationRules(builtIn: false)));
    }
  }

  Future<void> _loadResponsible() async {
    final id = state.responsibleId;
    final token = ++_personToken;
    if (id == null) return;
    try {
      final person = await _users.profile(id);
      if (isClosed || token != _personToken) return;
      emit(state.copyWith(responsible: person));
      _maybePreview();
    } catch (_) {
      // Unknown or gone: nobody to suspend.
    }
  }

  void choose(CaseOutcome outcome) {
    final acting = outcome == CaseOutcome.action;
    final scopes = scopesOf(kind);
    emit(
      state.copyWith(
        outcome: outcome,
        // An action takes the content unless it only suspends; a comment or
        // a file has one thing to take.
        remove: acting ? (state.suspend ? state.remove : true) : false,
        scope: acting && scopes.length == 1 ? scopes.first : null,
        clearScope: !acting,
        suspend: acting && state.suspend,
      ),
    );
    _maybePreview();
  }

  void setRemove(bool remove) {
    final scopes = scopesOf(kind);
    emit(
      state.copyWith(
        remove: remove,
        scope: remove && scopes.length == 1 ? scopes.first : null,
        clearScope: !remove,
      ),
    );
    _maybePreview();
  }

  void setScope(RemovalScope scope) {
    emit(state.copyWith(scope: scope));
    _maybePreview();
  }

  void setSuspend(bool suspend) {
    emit(state.copyWith(suspend: suspend && canSuspend));
    _maybePreview();
  }

  void setDuration(SuspensionLength duration) {
    emit(state.copyWith(duration: duration));
    _maybePreview();
  }

  void setGround(DecisionGround ground) {
    emit(state.copyWith(ground: ground));
    _maybePreview();
  }

  void chooseRule(HouseRule rule) {
    emit(state.copyWith(rule: rule));
    _maybePreview();
  }

  void chooseResponsible(String id) {
    if (id == state.responsibleId) return;
    emit(
      state.copyWith(responsibleId: id, clearResponsible: true, suspend: false),
    );
    _maybePreview();
    unawaited(_loadResponsible());
  }

  void setLawEnforcement(bool value) {
    emit(state.copyWith(lawEnforcement: value));
    _maybePreview();
  }

  void setDeceptiveCommercial(bool value) {
    emit(state.copyWith(deceptiveCommercial: value));
    _maybePreview();
  }

  // Free texts: the preview takes them as they are, without a request.
  void setFacts(String text) => emit(state.copyWith(facts: text));
  void setMessage(String text) => emit(state.copyWith(message: text));
  void setInternalNote(String text) => emit(state.copyWith(internalNote: text));
  void setLawReference(String text) => emit(state.copyWith(lawReference: text));
  void setRuleText(String text) => emit(state.copyWith(ruleText: text));

  String _reference() => switch (state.ground) {
    DecisionGround.law => state.lawReference.trim(),
    DecisionGround.rules =>
      state.pickRule
          ? (state.rule == null ? '' : ruleReferenceOf(state.rule!))
          : state.ruleText.trim(),
  };

  /// How a picked rule is named in the statement, the same in every language.
  static String ruleReferenceOf(HouseRule rule) =>
      '${rule.number}. ${rule.title}';

  /// Whether a preview can be worded at all: an action, with what it takes
  /// and the rule it rests on known.
  bool get _previewable {
    final s = state;
    if (!s.acting) return false;
    if (!s.remove && !s.suspend) return false;
    if (s.remove && s.scope == null) return false;
    if (s.ground == DecisionGround.rules && s.pickRule && s.rule == null) {
      return false;
    }
    return true;
  }

  /// What a preview depends on that typing does not change.
  Object get _structure => (
    state.outcome,
    state.remove ? state.scope : null,
    state.suspend ? state.duration : null,
    state.ground,
    state.pickRule ? state.rule?.number : null,
    state.responsibleId,
    state.lawEnforcement,
    state.deceptiveCommercial,
  );

  void _maybePreview() {
    if (!_previewable) {
      _previewKey = null;
      _previewToken++;
      if (state.previewBase != null || state.previewLoading) {
        emit(state.copyWith(clearPreview: true, previewLoading: false));
      }
      return;
    }
    final key = _structure;
    if (key == _previewKey) return;
    _previewKey = key;
    unawaited(_preview());
  }

  Future<void> _preview() async {
    final token = ++_previewToken;
    emit(state.copyWith(previewLoading: true, previewFailed: false));
    try {
      final statement = await _moderation.statementPreview(
        detail.id,
        _draft(preview: true),
      );
      if (isClosed || token != _previewToken) return;
      emit(state.copyWith(previewBase: statement, previewLoading: false));
    } catch (_) {
      if (isClosed || token != _previewToken) return;
      // The next structured change asks again.
      _previewKey = null;
      emit(state.copyWith(previewLoading: false, previewFailed: true));
    }
  }

  DecisionDraft _draft({required bool preview}) {
    final s = state;
    final outcome = s.outcome!;
    final acting = s.acting;
    final rules = s.ground == DecisionGround.rules;
    return DecisionDraft(
      rev: detail.summary.rev,
      outcome: outcome,
      removal: acting && s.remove ? s.scope : null,
      ground: outcome.acts ? s.ground : null,
      category: outcome.acts ? category : null,
      facts: preview ? factsMark : s.facts,
      ruleReference: !outcome.acts || !rules
          ? null
          : s.pickRule
          ? (s.rule == null ? null : ruleReferenceOf(s.rule!))
          : (preview ? ruleMark : s.ruleText),
      lawReference: !outcome.acts || rules
          ? null
          : (preview ? lawMark : s.lawReference),
      responsibleId: acting ? s.responsibleId : null,
      deceptiveCommercial:
          acting && s.deceptiveCommercial && category == ReportCategory.spam,
      messageToAuthor: preview || !acting ? '' : s.message,
      internalNote: preview ? '' : s.internalNote,
      lawEnforcementNotified: s.lawEnforcement,
      suspension: acting && s.suspend ? s.duration : null,
    );
  }

  /// Sends the decision. Problems are shown instead while any are left.
  Future<void> submit() async {
    if (state.sending) return;
    if (problems.isNotEmpty) {
      emit(state.copyWith(showProblems: true));
      return;
    }
    emit(state.copyWith(sending: true, showProblems: true));
    try {
      await _moderation.decide(detail.id, _draft(preview: false));
      if (isClosed) return;
      emit(
        state.copyWith(sending: false, closedWith: 'moderation.decision.sent'),
      );
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      final moved = movedMeanwhile(failure);
      emit(
        moved == null
            ? state.copyWith(sending: false, errorKey: failure.message)
            : state.copyWith(sending: false, closedWith: moved),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(sending: false, errorKey: 'errors.unexpected'));
    }
  }
}

String? _orNull(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}
