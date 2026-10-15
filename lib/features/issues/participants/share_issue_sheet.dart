import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/blocs/person_picker_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/issue_detail.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/issue_repository.dart';
import '../../../core/repositories/user_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveAvatar;
import '../../sprint/modals/glass_modal.dart';
import 'issue_participants_cubit.dart';

/// The first person an assignment was refused for because they cannot open the
/// project, from the server's refusal; null for any other failure.
String? refusedAssigneeId(ApiFailure failure) {
  if (failure.details['reason'] != 'assigneeNoAccess') return null;
  final first = (failure.details['userIds'] ?? '').split(',').first.trim();
  return first.isEmpty ? null : first;
}

/// Opens the share dialog for [issue] (HIN-136): search the directory, share
/// with a tap, take people off again.
///
/// Wide windows get it as a glass popover under [anchorRect] (the ⋯ menu);
/// phones, and callers without an anchor, get the adaptive modal, which is a
/// bottom sheet on a phone. [members] are the people the detail names who see
/// the issue anyway; [initialQuery] prefills the search, for the entries that
/// already know whom to share with.
Future<void> showShareIssueSheet(
  BuildContext context, {
  required Issue issue,
  required String projectName,
  required List<DirectoryUser> members,
  String? meId,
  Rect? anchorRect,
  String? initialQuery,
}) {
  // A root-navigator route inherits none of the caller's providers.
  final issues = context.read<IssueRepository>();
  final users = context.read<UserRepository>();
  Widget body(BuildContext _) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => IssueParticipantsCubit(
          issues: issues,
          issueId: issue.id,
          meId: meId,
          members: members,
        )..load(),
      ),
      BlocProvider(create: (_) => PersonPickerCubit(users)),
    ],
    child: ShareIssuePanel(
      issueKey: issue.readableId,
      projectName: projectName,
      initialQuery: initialQuery,
    ),
  );

  final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  if (wide && anchorRect != null) {
    return showGlassAnchoredPopover<void>(
      context,
      anchorRect: anchorRect,
      width: 420,
      minHeight: 320,
      maxHeight: 560,
      builder: body,
    );
  }
  return showGlassModal<void>(context, width: 460, builder: body);
}

/// The dialog's content, in the spec's order: header, search, the people the
/// issue is shared with, the members who see it anyway, and the footer.
class ShareIssuePanel extends StatefulWidget {
  const ShareIssuePanel({
    super.key,
    required this.issueKey,
    required this.projectName,
    this.initialQuery,
  });

  final String issueKey;
  final String projectName;
  final String? initialQuery;

  @override
  State<ShareIssuePanel> createState() => _ShareIssuePanelState();
}

class _ShareIssuePanelState extends State<ShareIssuePanel> {
  static const _debounceDelay = Duration(milliseconds: 180);
  static const _pageSize = 20;

  late final TextEditingController _search = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<DirectoryUser> _results = [];
  final Set<String> _seen = {};
  int _page = 0;
  int _total = 0;
  bool _searching = false;
  bool _exhausted = false;
  String? _searchError;

  /// Drops a debounced answer that lands after a newer search began.
  int _seq = 0;

  String get _query => _search.text.trim();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (_query.isNotEmpty) _runSearch(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    if (_query.isEmpty) {
      setState(() {
        _seq++;
        _results.clear();
        _seen.clear();
        _searching = false;
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(_debounceDelay, () => _runSearch(reset: true));
  }

  void _onScroll() {
    if (!_scroll.hasClients || _query.isEmpty) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 120) {
      _runSearch(reset: false);
    }
  }

  Future<void> _runSearch({required bool reset}) async {
    if (!reset && (_searching || _exhausted || _results.length >= _total)) {
      return;
    }
    final seq = ++_seq;
    final page = reset ? 0 : _page + 1;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final result = await context.read<PersonPickerCubit>().search(
        _query,
        page: page,
        size: _pageSize,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        if (reset) {
          _results.clear();
          _seen.clear();
        }
        for (final user in result.items) {
          if (_seen.add(user.id)) _results.add(user);
        }
        _page = page;
        _total = result.total;
        _exhausted = result.items.length < _pageSize;
        _searching = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _searching = false;
        _searchError = failure.message;
      });
    }
  }

  Future<void> _add(DirectoryUser user) async {
    final cubit = context.read<IssueParticipantsCubit>();
    final name = user.displayName.isEmpty ? user.username : user.displayName;
    final outcome = await cubit.add(user);
    if (!mounted) return;
    switch (outcome) {
      case AddOutcome.added:
        showGlassToast(
          context,
          context.t('issues.participants.added', variables: {'name': name}),
          kind: GlassToastKind.success,
        );
      case AddOutcome.alreadyMember:
        showGlassToast(
          context,
          context.t(
            'issues.participants.alreadyMember',
            variables: {'name': name},
          ),
        );
      case AddOutcome.alreadyShared:
        break;
      case AddOutcome.failed:
        showGlassErrorToast(
          context,
          context.t(cubit.state.errorKey ?? 'errors.unexpected'),
        );
    }
  }

  Future<void> _remove(IssueParticipant person) async {
    final cubit = context.read<IssueParticipantsCubit>();
    final removed = await cubit.remove(person.id);
    if (!mounted) return;
    if (removed) {
      showGlassToast(
        context,
        context.t(
          'issues.participants.removed',
          variables: {'name': person.displayName},
        ),
      );
    } else {
      showGlassErrorToast(
        context,
        context.t(cubit.state.errorKey ?? 'errors.unexpected'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = context.t(
      'issues.participants.title',
      variables: {'key': widget.issueKey},
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassModalHeader(
            icon: LucideIcons.share2,
            title: title,
            subtitle: context.t(
              'issues.participants.subtitle',
              variables: {'project': widget.projectName},
            ),
            subtitleMaxLines: 3,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: _SearchPill(
              controller: _search,
              autofocus: widget.initialQuery == null,
              onChanged: _onQueryChanged,
            ),
          ),
          Flexible(
            child: CustomScrollView(
              controller: _scroll,
              shrinkWrap: true,
              slivers: [
                if (_query.isNotEmpty) ..._resultSlivers(context),
                ..._participantSlivers(context),
                ..._memberSlivers(context),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            ),
          ),
          _Footer(),
        ],
      ),
    );
  }

  List<Widget> _resultSlivers(BuildContext context) {
    final full = context.select<IssueParticipantsCubit, bool>(
      (cubit) => cubit.state.isFull,
    );
    Widget? status;
    if (_searchError != null && _results.isEmpty) {
      status = _Note(context.t(_searchError!), color: AppColors.dangerInk);
    } else if (_searching && _results.isEmpty) {
      status = const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: HiveLoader(size: 18)),
      );
    } else if (_results.isEmpty) {
      status = _Note(context.t('issues.participants.noResults'));
    } else if (full) {
      status = _Note(
        context.t(
          'issues.participants.full',
          variables: {'max': IssueParticipantsCubit.maxParticipants},
        ),
        color: AppColors.dangerInk,
      );
    }
    return [
      if (status != null)
        SliverToBoxAdapter(child: Semantics(liveRegion: true, child: status)),
      SliverList.builder(
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final user = _results[index];
          return _ResultRow(user: user, onTap: full ? null : () => _add(user));
        },
      ),
      if (_searching && _results.isNotEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(child: HiveLoader(size: 15)),
          ),
        ),
    ];
  }

  List<Widget> _participantSlivers(BuildContext context) {
    final state = context.watch<IssueParticipantsCubit>().state;
    return [
      SliverToBoxAdapter(
        child: _SectionLabel(
          context.t(
            'issues.participants.section',
            variables: {
              'count': state.participants.length,
              'max': IssueParticipantsCubit.maxParticipants,
            },
          ),
        ),
      ),
      if (state.loading && state.participants.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: HiveLoader(size: 16)),
          ),
        )
      else if (state.participants.isEmpty)
        SliverToBoxAdapter(child: _Note(context.t('issues.participants.empty')))
      else
        SliverList.builder(
          itemCount: state.participants.length,
          itemBuilder: (context, index) {
            final person = state.participants[index];
            return _ParticipantRow(
              person: person,
              addedByName: _nameOf(state, person.addedById),
              busy: state.busy.contains(person.id),
              onRemove: () => _remove(person),
            );
          },
        ),
    ];
  }

  String? _nameOf(IssueParticipantsState state, String? id) {
    if (id == null) return null;
    for (final m in state.members) {
      if (m.id == id) return m.displayName;
    }
    return null;
  }

  List<Widget> _memberSlivers(BuildContext context) {
    final members = context.select<IssueParticipantsCubit, List<DirectoryUser>>(
      (cubit) => cubit.state.members,
    );
    if (members.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: _SectionLabel(context.t('issues.participants.membersSection')),
      ),
      SliverList.builder(
        itemCount: members.length,
        itemBuilder: (context, index) => _MemberRow(user: members[index]),
      ),
    ];
  }
}

/// The search field as an inset pill on the glass, with a label that stays
/// announced while text is typed.
class _SearchPill extends StatelessWidget {
  const _SearchPill({
    required this.controller,
    required this.autofocus,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool autofocus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = context.t('issues.participants.search');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 9),
          Expanded(
            child: Semantics(
              label: label,
              textField: true,
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: AppType.label),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: label,
                  hintStyle: TextStyle(
                    fontSize: AppType.label,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppType.caption,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: AppColors.inkSoft,
        ),
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: AppType.label,
        height: 1.35,
        color: color ?? AppColors.textSecondary,
      ),
    ),
  );
}

/// One row of the people list: avatar, name and a second line, and whatever
/// sits on the right. At least 48 points high at every text size.
class _PersonLine extends StatelessWidget {
  const _PersonLine({
    required this.name,
    this.avatarUrl,
    this.pronouns,
    this.detail,
    this.trailing,
  });

  final String name;
  final String? avatarUrl;
  final String? pronouns;
  final String? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    final trailing = this.trailing;
    return LayoutBuilder(
      builder: (context, constraints) => _line(
        context,
        detail,
        trailing,
        maxTrailing: constraints.maxWidth * 0.42,
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String? detail,
    Widget? trailing, {
    required double maxTrailing,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Row(
          children: [
            HiveAvatar(
              name: name,
              imageUrl: avatarUrl,
              pronouns: pronouns,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.caption,
                        color: AppColors.inkSoft,
                      ),
                    ),
                ],
              ),
            ),
            // Capped, so a long label at twice the text size shortens
            // instead of pushing the row past the edge, and held to the end.
            if (trailing != null) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTrailing),
                child: trailing,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.user, required this.onTap});

  final DirectoryUser user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isEmpty ? user.username : user.displayName;
    // The row's own tap is handed to the node that replaces its semantics,
    // or a screen reader would announce a button that does nothing.
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: context.t(
        'issues.participants.shareWith',
        variables: {'name': name},
      ),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: _PersonLine(
          name: name,
          avatarUrl: user.avatarUrl,
          pronouns: user.pronouns,
          detail: user.title,
          trailing: Icon(
            LucideIcons.userPlus,
            size: 18,
            color: onTap == null ? AppColors.inkFaint : AppColors.accentInk,
          ),
        ),
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.person,
    required this.addedByName,
    required this.busy,
    required this.onRemove,
  });

  final IssueParticipant person;
  final String? addedByName;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final addedAt = person.addedAt;
    final detail = addedAt == null
        ? null
        : context.t(
            'issues.participants.addedBy',
            variables: {
              'name': addedByName ?? context.t('issues.participants.aMember'),
              'when': MaterialLocalizations.of(
                context,
              ).formatShortDate(addedAt.toLocal()),
            },
          );
    return _PersonLine(
      name: person.displayName,
      avatarUrl: person.avatarUrl,
      pronouns: person.pronouns,
      detail: detail,
      trailing: busy
          ? const SizedBox(
              width: 48,
              height: 48,
              child: Center(child: HiveLoader(size: 16)),
            )
          : OutlinedButton(
              onPressed: onRemove,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              // The visible word is "Remove"; a screen reader hears whom.
              child: Text(
                context.t('issues.participants.remove'),
                semanticsLabel: context.t(
                  'issues.participants.removeOf',
                  variables: {'name': person.displayName},
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.user});

  final DirectoryUser user;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isEmpty ? user.username : user.displayName;
    return MergeSemantics(
      child: _PersonLine(
        name: name,
        avatarUrl: user.avatarUrl,
        pronouns: user.pronouns,
        detail: user.title,
        trailing: Text(
          context.t('issues.participants.member'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppType.caption, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding:
        const EdgeInsets.fromLTRB(22, 12, 18, 14) +
        EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            context.t('issues.participants.footer'),
            style: TextStyle(
              fontSize: AppType.caption,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          flex: 2,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
              child: Text(
                context.t('issues.participants.done'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
