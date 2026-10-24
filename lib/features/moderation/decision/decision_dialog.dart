import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/models/person_profile.dart';
import '../../../core/repositories/moderation_repository.dart';
import '../../../core/repositories/user_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/util/dates.dart';
import '../../../core/widgets/glass_switch_chip.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../account/account_widgets.dart' show AccountNote, AccountNoteTone;
import '../../sprint/modals/glass_modal.dart';
import '../case/case_detail_cubit.dart' show CaseNotice;
import '../case/case_dialogs.dart' show noteCounter;
import '../case/case_sections.dart' show removalScopeWord;
import '../report/report_reasons.dart' show reportCategoryTitle;
import '../widgets/case_look.dart';
import '../widgets/statement_view.dart';
import 'decision_cubit.dart';

/// The longest message to the person a decision is about.
const messageMax = 1000;

/// Opens the decision on case [detail] (HIN-174): two columns on a wide
/// window with the statement beside the form, a sheet on a phone. Answers
/// what to tell the reader on the case once it closed: sent, or decided or
/// changed by somebody else meanwhile; null when cancelled.
///
/// With [suspendPerson] it opens on "Maßnahme · Konto sperren", for a case
/// just opened from a person's profile; [person] is that profile, which is
/// then not read again.
Future<CaseNotice?> showDecisionDialog(
  BuildContext context,
  CaseDetail detail, {
  bool suspendPerson = false,
  String facts = '',
  PersonProfile? person,
}) {
  final moderation = context.read<ModerationRepository>();
  final users = context.read<UserRepository>();
  return showGlassModal<CaseNotice>(
    context,
    width: 860,
    builder: (_) => BlocProvider(
      create: (_) => DecisionCubit(
        moderation,
        users,
        detail: detail,
        suspendPerson: suspendPerson,
        facts: facts,
        person: person,
      )..start(),
      child: const DecisionDialog(),
    ),
  );
}

class DecisionDialog extends StatefulWidget {
  const DecisionDialog({super.key});

  @override
  State<DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<DecisionDialog> {
  /// Wide enough for the form and the statement side by side.
  static const double _twoColumns = 760;

  /// Whether [current] changes more of the form than what is typed.
  ///
  /// The fields keep their own text, and the preview follows it on its own
  /// ([_Preview]). Of the text the form itself shows only whether there is an
  /// internal note and, once sending was tried, the problems left.
  static bool _formChanged(DecisionState previous, DecisionState current) =>
      current.showProblems ||
      previous.internalNote.trim().isEmpty !=
          current.internalNote.trim().isEmpty ||
      previous.copyWith(
            facts: current.facts,
            message: current.message,
            internalNote: current.internalNote,
            lawReference: current.lawReference,
            ruleText: current.ruleText,
            errorKey: current.errorKey,
          ) !=
          current;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DecisionCubit, DecisionState>(
        listenWhen: (previous, current) =>
            previous.closedWith == null && current.closedWith != null,
        listener: (context, state) =>
            Navigator.of(context).pop(state.closedWith),
        buildWhen: _formChanged,
        builder: (context, state) {
          final cubit = context.read<DecisionCubit>();
          final detail = cubit.detail;
          final kind = contentKindWord(context, detail.summary.kind);
          final location = detail.summary.location;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassModalHeader(
                icon: LucideIcons.gavel,
                title: context.t('moderation.decision.title'),
                subtitle: [
                  reportCategoryTitle(context, cubit.category),
                  if (location == null)
                    kind
                  else
                    context.t(
                      'moderation.decision.kindIn',
                      variables: {'kind': kind, 'where': location},
                    ),
                ].join(' · '),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final form = _Form(state: state);
                      const preview = _Preview();
                      if (constraints.maxWidth >= _twoColumns) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: form),
                            const SizedBox(width: 20),
                            const Expanded(child: preview),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [form, const SizedBox(height: 16), preview],
                      );
                    },
                  ),
                ),
              ),
              GlassModalFooter(
                confirmLabel: context.t('moderation.decision.send'),
                confirmIcon: LucideIcons.send,
                busy: state.sending,
                onConfirm: () => unawaited(cubit.submit()),
              ),
            ],
          );
        },
      );
}

/// The person the statement goes to, where the decision knows who it is.
String? _personName(DecisionState state) => state.responsible?.displayName;

class _Form extends StatelessWidget {
  const _Form({required this.state});

  final DecisionState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DecisionCubit>();
    final problems = state.showProblems
        ? cubit.problems
        : const <DecisionProblem>{};
    final outcome = state.outcome;
    final error = state.errorKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in outcomesOf(cubit.kind)) ...[
          _OutcomeOption(
            outcome: option,
            person: _personName(state),
            selected: option == outcome,
            onTap: () => cubit.choose(option),
          ),
          const SizedBox(height: 8),
        ],
        if (problems.contains(DecisionProblem.outcome))
          _Problem(context.t('moderation.decision.problem.outcome')),
        if (state.acting) _Measures(state: state, problems: problems),
        if (outcome != null && outcome.acts) ...[
          const SizedBox(height: 12),
          _Ground(state: state, problems: problems),
        ],
        if (outcome != null) ...[
          const SizedBox(height: 12),
          _FactsField(state: state, problems: problems),
        ],
        if (state.acting) ...[
          const SizedBox(height: 4),
          _TextField(
            label: _personName(state) == null
                ? context.t('moderation.decision.messageToAnyone')
                : context.t(
                    'moderation.decision.messageTo',
                    variables: {'name': _personName(state)!},
                  ),
            initial: state.message,
            max: messageMax,
            lines: 2,
            onChanged: cubit.setMessage,
          ),
        ],
        if (outcome != null) ...[
          const SizedBox(height: 4),
          _MoreDetails(state: state),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: AccountNote(
              text: context.t(error),
              icon: LucideIcons.triangleAlert,
              tone: AccountNoteTone.danger,
            ),
          ),
        ],
      ],
    );
  }
}

/// One outcome as a row to choose, with what it means.
class _OutcomeOption extends StatelessWidget {
  const _OutcomeOption({
    required this.outcome,
    required this.person,
    required this.selected,
    required this.onTap,
  });

  final CaseOutcome outcome;

  /// Who gets the statement, by name; null while nobody is known.
  final String? person;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final icon = switch (outcome) {
      CaseOutcome.noViolation => LucideIcons.check,
      CaseOutcome.unfounded => LucideIcons.circleSlash,
      CaseOutcome.action => LucideIcons.gavel,
      CaseOutcome.handled => LucideIcons.clipboardCheck,
    };
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Material(
        color: selected
            ? AppColors.accentSoft.withValues(alpha: dark ? .4 : .7)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.accentStrong : AppColors.hairline,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t(
                          'moderation.decision.outcome.${outcome.name}',
                        ),
                        style: TextStyle(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        outcome == CaseOutcome.action && person == null
                            ? context.t(
                                'moderation.decision.outcomeHint.actionAnyone',
                              )
                            : context.t(
                                'moderation.decision.outcomeHint.${outcome.name}',
                                variables: {'name': person ?? ''},
                              ),
                        style: TextStyle(
                          fontSize: AppType.label,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? LucideIcons.circleDot : LucideIcons.circle,
                  size: 18,
                  color: selected ? AppColors.accentInk : AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What an action does: takes the content, how much of it, and suspends the
/// person, for how long, with what that means.
class _Measures extends StatelessWidget {
  const _Measures({required this.state, required this.problems});

  final DecisionState state;
  final Set<DecisionProblem> problems;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DecisionCubit>();
    final scopes = scopesOf(cubit.kind);
    final canSuspend = cubit.canSuspend;
    // Suspending needs the person known, so the name is there whenever these
    // lines are.
    final name = _personName(state) ?? '';
    final until = state.duration.duration == null
        ? null
        : DateTime.now().add(state.duration.duration!);
    final suspendHint = state.responsibleIsAdmin
        ? 'moderation.decision.suspendAdmin'
        : canSuspend
        ? 'moderation.decision.suspendHint'
        : state.responsible == null && cubit.contributors.isNotEmpty
        ? 'moderation.decision.suspendLoading'
        : 'moderation.decision.suspendNobody';
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 18, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scopes.isNotEmpty) ...[
            GlassOptionRow(
              title: context.t('moderation.decision.remove'),
              subtitle: state.remove && state.scope != null
                  ? removalScopeWord(context, cubit.kind, state.scope!)
                  : context.t('moderation.decision.removeHint'),
              value: state.remove,
              onChanged: cubit.setRemove,
            ),
            if (state.remove && scopes.length > 1) ...[
              InlineSwitchBar(
                chips: [
                  for (final scope in scopes)
                    GlassSwitchChip(
                      label: context.t(
                        'moderation.decision.scopeChip.${cubit.kind.name}.${scope.name}',
                      ),
                      active: scope == state.scope,
                      onTap: () => cubit.setScope(scope),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (problems.contains(DecisionProblem.scope))
              _Problem(context.t('moderation.decision.problem.scope')),
          ],
          GlassOptionRow(
            title: context.t('moderation.decision.suspend'),
            subtitle: context.t(suspendHint),
            value: state.suspend,
            onChanged: canSuspend ? cubit.setSuspend : null,
          ),
          if (state.suspend) ...[
            Text(
              context.t('moderation.decision.howLong'),
              style: TextStyle(
                fontSize: AppType.label,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 8),
            InlineSwitchBar(
              chips: [
                for (final length in SuspensionLength.values)
                  GlassSwitchChip(
                    label: context.t(
                      'moderation.suspension.length.${length.name}',
                    ),
                    active: length == state.duration,
                    onTap: () => cubit.setDuration(length),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            CaseInfoLine(
              icon: LucideIcons.logOut,
              text: context.t(
                'moderation.decision.suspendSignOut',
                variables: {'name': name},
              ),
            ),
            CaseInfoLine(
              icon: LucideIcons.mail,
              text: context.t(
                'moderation.decision.suspendMail',
                variables: {'name': name},
              ),
            ),
            CaseInfoLine(
              icon: LucideIcons.calendarClock,
              text: until == null
                  ? context.t('moderation.decision.suspendIndefinite')
                  : context.t(
                      'moderation.decision.suspendEnds',
                      variables: {'date': recentMoment(context, until)},
                    ),
            ),
            if (state.needsSecondPerson)
              CaseInfoLine(
                icon: LucideIcons.usersRound,
                text: context.t('moderation.decision.secondPerson'),
              ),
          ],
          if (problems.contains(DecisionProblem.measure))
            _Problem(context.t('moderation.decision.problem.measure')),
          if (problems.contains(DecisionProblem.suspension))
            _Problem(context.t('moderation.decision.problem.suspension')),
        ],
      ),
    );
  }
}

/// What the decision rests on: a house rule, picked or written out, or the
/// law with its provision.
class _Ground extends StatelessWidget {
  const _Ground({required this.state, required this.problems});

  final DecisionState state;
  final Set<DecisionProblem> problems;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DecisionCubit>();
    final law = state.ground == DecisionGround.law;
    return GlassField(
      label: context.t('moderation.decision.ground'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineSwitchBar(
            chips: [
              for (final ground in DecisionGround.values)
                GlassSwitchChip(
                  label: context.t(
                    'moderation.decision.groundChip.${ground.name}',
                  ),
                  active: ground == state.ground,
                  onTap: () => cubit.setGround(ground),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (law)
            _TextField(
              label: context.t('moderation.decision.law'),
              hint: context.t('moderation.decision.lawHint'),
              initial: state.lawReference,
              max: 200,
              onChanged: cubit.setLawReference,
            )
          else if (state.pickRule)
            _RuleField(state: state)
          else
            _TextField(
              label: context.t('moderation.decision.rule'),
              hint: context.t('moderation.decision.ruleHint'),
              initial: state.ruleText,
              max: 200,
              onChanged: cubit.setRuleText,
            ),
          if (problems.contains(DecisionProblem.reference))
            _Problem(
              context.t(
                law
                    ? 'moderation.decision.problem.law'
                    : 'moderation.decision.problem.rule',
              ),
            ),
        ],
      ),
    );
  }
}

/// The house rule picked, opening the list with a search beside it.
class _RuleField extends StatelessWidget {
  const _RuleField({required this.state});

  final DecisionState state;

  @override
  Widget build(BuildContext context) {
    final rule = state.rule;
    return GlassChoiceField(
      label: context.t('moderation.decision.rule'),
      value: rule == null
          ? context.t('moderation.decision.pickRule')
          : ruleLabel(context, rule),
      chosen: rule != null,
      onOpen: (anchor) => unawaited(_pick(context, anchor)),
    );
  }

  Future<void> _pick(BuildContext context, Rect? anchor) async {
    final cubit = context.read<DecisionCubit>();
    final rules = state.rules?.rules ?? const <HouseRule>[];
    final view = View.of(context);
    final wide =
        view.physicalSize.width / view.devicePixelRatio >=
        kGlassPopoverBreakpoint;
    Widget list(BuildContext context) =>
        _RuleList(rules: rules, chosen: state.rule);
    final picked = wide && anchor != null
        ? await showGlassAnchoredPopover<HouseRule>(
            context,
            anchorRect: anchor,
            width: 380,
            builder: list,
          )
        : await showGlassModal<HouseRule>(
            context,
            width: 420,
            // Never a sheet on a sheet: on a phone the decision is one.
            adaptive: false,
            builder: list,
          );
    if (picked != null) cubit.chooseRule(picked);
  }
}

/// A house rule as the decision names it: Hausregel 2: Kein Herabsetzen anderer.
String ruleLabel(BuildContext context, HouseRule rule) => context.t(
  'moderation.decision.ruleLabel',
  variables: {'number': '${rule.number}', 'title': rule.title},
);

class _RuleList extends StatefulWidget {
  const _RuleList({required this.rules, required this.chosen});

  final List<HouseRule> rules;
  final HouseRule? chosen;

  @override
  State<_RuleList> createState() => _RuleListState();
}

class _RuleListState extends State<_RuleList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final rule in widget.rules)
        if (query.isEmpty ||
            '${rule.number}' == query ||
            rule.title.toLowerCase().contains(query))
          rule,
    ];
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: GlassField(
              label: context.t('moderation.decision.searchRules'),
              child: TextField(
                autofocus: true,
                onChanged: (text) => setState(() => _query = text),
                decoration: glassInputDecoration(),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              children: [
                for (final rule in shown)
                  ListTile(
                    minTileHeight: 48,
                    selected: rule == widget.chosen,
                    title: Text(ruleLabel(context, rule)),
                    trailing: rule == widget.chosen
                        ? const Icon(LucideIcons.check, size: 16)
                        : null,
                    onTap: () => Navigator.of(context).pop(rule),
                  ),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      context.t('moderation.decision.noRule'),
                      style: TextStyle(color: AppColors.inkSoft),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FactsField extends StatelessWidget {
  const _FactsField({required this.state, required this.problems});

  final DecisionState state;
  final Set<DecisionProblem> problems;

  @override
  Widget build(BuildContext context) {
    final required = state.outcome != CaseOutcome.noViolation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TextField(
          label: context.t(
            required
                ? 'moderation.decision.factsRequired'
                : 'moderation.decision.factsOptional',
          ),
          hint: context.t('moderation.decision.factsHint'),
          initial: state.facts,
          max: caseNoteMax,
          lines: 3,
          onChanged: context.read<DecisionCubit>().setFacts,
        ),
        if (problems.contains(DecisionProblem.facts))
          _Problem(
            context.t(
              'moderation.decision.problem.facts',
              variables: {'min': '$caseNoteMin'},
            ),
          ),
      ],
    );
  }
}

/// "Weitere Angaben", closed, its head telling what it holds.
class _MoreDetails extends StatefulWidget {
  const _MoreDetails({required this.state});

  final DecisionState state;

  @override
  State<_MoreDetails> createState() => _MoreDetailsState();
}

class _MoreDetailsState extends State<_MoreDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cubit = context.read<DecisionCubit>();
    final contributors = cubit.contributors;
    final spam = state.acting && cubit.category == ReportCategory.spam;
    final summary = [
      if (contributors.length > 1 && state.responsible != null)
        context.t(
          'moderation.decision.responsibleIs',
          variables: {'name': state.responsible!.displayName},
        ),
      context.t(
        state.lawEnforcement
            ? 'moderation.decision.lawEnforcementYes'
            : 'moderation.decision.lawEnforcementNo',
      ),
      context.t(
        state.internalNote.trim().isEmpty
            ? 'moderation.decision.noInternalNote'
            : 'moderation.decision.withInternalNote',
      ),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl + 4),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl + 4),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  Icon(
                    _open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                    size: 16,
                    color: AppColors.inkSoft,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('moderation.decision.more'),
                          style: TextStyle(
                            fontSize: AppType.label,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          summary,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (contributors.length > 1 && state.acting)
                  _ResponsiblePicker(state: state),
                GlassOptionRow(
                  title: context.t('moderation.decision.lawEnforcement'),
                  subtitle: context.t('moderation.decision.lawEnforcementHint'),
                  value: state.lawEnforcement,
                  onChanged: cubit.setLawEnforcement,
                ),
                if (spam)
                  GlassOptionRow(
                    title: context.t('moderation.decision.deceptive'),
                    subtitle: context.t('moderation.decision.deceptiveHint'),
                    value: state.deceptiveCommercial,
                    onChanged: cubit.setDeceptiveCommercial,
                  ),
                _TextField(
                  label: context.t('moderation.decision.internalNote'),
                  hint: context.t('moderation.decision.internalNoteHint'),
                  initial: state.internalNote,
                  max: caseNoteMax,
                  lines: 2,
                  onChanged: cubit.setInternalNote,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Whom the statement is about, among everybody who wrote the content.
class _ResponsiblePicker extends StatelessWidget {
  const _ResponsiblePicker({required this.state});

  final DecisionState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DecisionCubit>();
    final contributors = cubit.contributors;
    return GlassField(
      label: context.t('moderation.decision.responsible'),
      child: InlineSwitchBar(
        chips: [
          for (var i = 0; i < contributors.length; i++)
            GlassSwitchChip(
              label: contributors[i] == state.responsible?.id
                  ? state.responsible!.displayName
                  : context.t(
                      'moderation.decision.contributor',
                      variables: {'n': '${i + 1}'},
                    ),
              active: contributors[i] == state.responsibleId,
              onTap: contributors[i] == state.responsibleId
                  ? null
                  : () => cubit.chooseResponsible(contributors[i]),
            ),
        ],
      ),
    );
  }
}

/// A text field of the form, kept by its own controller.
class _TextField extends StatefulWidget {
  const _TextField({
    required this.label,
    required this.initial,
    required this.max,
    required this.onChanged,
    this.hint,
    this.lines = 1,
  });

  final String label;
  final String? hint;
  final String initial;
  final int max;
  final int lines;
  final ValueChanged<String> onChanged;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassField(
    wrapCaption: true,
    label: widget.label,
    child: TextField(
      controller: _controller,
      minLines: widget.lines,
      maxLines: widget.lines == 1 ? 1 : widget.lines + 6,
      maxLength: widget.max,
      buildCounter: widget.lines == 1 ? _noCounter : noteCounter,
      onChanged: widget.onChanged,
      decoration: glassInputDecoration(hint: widget.hint),
    ),
  );
}

Widget? _noCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => null;

/// What still keeps the decision from going out, beside its field.
class _Problem extends StatelessWidget {
  const _Problem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.circleAlert, size: 14, color: AppColors.dangerInk),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppType.caption,
                color: AppColors.dangerInk,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The statement as the person will read it, beside or below the form.
/// What the preview shows: it follows the facts and the message as they are
/// typed, and nothing else typed reaches it.
typedef _PreviewView = ({
  CaseOutcome? outcome,
  Statement? statement,
  bool loading,
  bool failed,
  String? person,
});

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final view = context.select<DecisionCubit, _PreviewView>((cubit) {
      final state = cubit.state;
      return (
        outcome: state.outcome,
        statement: state.preview,
        loading: state.previewLoading,
        failed: state.previewFailed,
        person: _personName(state),
      );
    });
    final dark = Theme.of(context).brightness == Brightness.dark;
    final outcome = view.outcome;
    final preview = view.statement;
    final Widget body;
    if (outcome != CaseOutcome.action) {
      body = Text(
        context.t(
          outcome == null
              ? 'moderation.decision.previewNone'
              : 'moderation.decision.previewNoStatement.${outcome.name}',
        ),
        style: TextStyle(
          fontSize: AppType.label,
          height: 1.45,
          color: AppColors.ink,
        ),
      );
    } else if (preview != null) {
      body = StatementView(statement: preview, compact: true);
    } else if (view.loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: HiveLoader(size: 28)),
      );
    } else {
      // Only a failure is announced: the preview follows the fields keystroke
      // by keystroke, and a live region around it would read the whole
      // statement again on each one.
      body = Semantics(
        liveRegion: view.failed,
        child: Text(
          context.t(
            view.failed
                ? 'moderation.decision.previewFailed'
                : 'moderation.decision.previewIncomplete',
          ),
          style: TextStyle(
            fontSize: AppType.label,
            height: 1.45,
            color: AppColors.inkSoft,
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.recess,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: dark ? AppColors.hairline : AppColors.hairline2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(LucideIcons.mailOpen, size: 15, color: AppColors.inkSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    view.person == null
                        ? context.t('moderation.decision.previewTitleAnyone')
                        : context.t(
                            'moderation.decision.previewTitle',
                            variables: {'name': view.person!},
                          ),
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            body,
          ],
        ),
      ),
    );
  }
}
