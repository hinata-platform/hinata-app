import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/blocs/auth_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/admin_user_models.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_bulk_bar.dart' show GlassBulkBarDock;
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/user_pronouns.dart';
import '../../shell/page_chrome.dart';
import '../../sprint/modals/glass_modal.dart'
    show showGlassToast, GlassToastKind;
import '../../../core/widgets/glass_filter_bar.dart';
import 'user_management_cubit.dart';
import 'user_management_modals.dart';
import 'user_management_widgets.dart';
import '../../../core/widgets/hive_widgets.dart'
    show backChevron, forwardChevron;
import '../../../core/theme/app_type.dart';

part 'user_management_screen.rows.dart';

/// Docked-toolbar height on compact: one row, tall enough for the search field
/// the chips give way to. One and not two, because the blurred band above a
/// page holds the app bar's title row and exactly one more.
const double _kUmDockHeight = kGlassDockRow;

/// Lets the admin shell's app-bar action open the invite dialog of the board
/// in its pane: on a wide window the board is a section of the admin area and
/// publishes no app bar of its own.
class UserInviteController {
  Future<void> Function()? _invite;

  /// Opens the invite dialog of the board this controller is attached to.
  void invite() => _invite?.call();
}

/// Admin **User management** board: a paginated directory of every platform
/// user with search, role/status/origin filters, sortable columns, a per-user
/// detail drawer, bulk actions and the full account lifecycle. Admin-gated.
///
/// A section of the admin area, the way the audit log is one: on compact it
/// owns its own [PageChrome] (title, back, docked filters, Invite); on a wide
/// window it lives in the admin rail layout's pane, with its filter row above
/// the directory and Invite in the admin shell's app bar via
/// [inviteController].
class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({
    super.key,
    this.focusUserId,
    this.onBack,
    this.inviteController,
  });

  /// When set (e.g. from an admin approval deep-link `?user=<id>`), the matching
  /// user's detail drawer is opened automatically once the board has loaded.
  final String? focusUserId;

  /// Compact only: the back handler of the section's own [PageChrome].
  final VoidCallback? onBack;

  /// Wide only: how the admin shell's Invite action reaches this board.
  final UserInviteController? inviteController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => UserManagementCubit(context.read<AdminRepository>()),
    child: _UserManagementBoard(
      focusUserId: focusUserId,
      onBack: onBack,
      inviteController: inviteController,
    ),
  );
}

class _UserManagementBoard extends StatefulWidget {
  const _UserManagementBoard({
    this.focusUserId,
    this.onBack,
    this.inviteController,
  });

  final String? focusUserId;
  final VoidCallback? onBack;
  final UserInviteController? inviteController;

  @override
  State<_UserManagementBoard> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<_UserManagementBoard> {
  AdminUserPage? _page;
  bool _loading = true;
  String? _error;

  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  /// Whether the phone's one docked row is showing the search field instead of
  /// the filter chips. See [GlassSearchDock].
  bool _searching = false;
  Timer? _debounce;
  AdminRole? _roleF;
  UserStatus? _statusF;
  UserOrigin? _originF;
  UserSortKey _sortKey = UserSortKey.lastActive;
  bool _desc = true;
  int _pageNum = 1;
  int _perPage = 10;

  // Bumped on every load so a slower earlier request (rapid pager / sort / typed
  // search) can't land after a newer one and show the wrong page/filter.
  int _loadGen = 0;

  final Set<String> _sel = {};

  /// Every [AdminUser] we've seen — current page items plus any directly-fetched
  /// deep-link focus user. Confirm modals resolve their affected users from here
  /// so an off-page/drawer user still carries its real name/role (and the
  /// type-DELETE safeguard) into the dialog instead of degrading to an empty list.
  final Map<String, AdminUser> _known = {};

  /// Guards the one-shot deep-link drawer open so filter/page reloads don't
  /// keep re-opening it.
  bool _focusHandled = false;

  UserManagementCubit get _users => context.read<UserManagementCubit>();
  String? get _currentUserId => context.read<AuthBloc>().state.user?.id;

  @override
  void initState() {
    super.initState();
    widget.inviteController?._invite = _invite;
    _load();
  }

  @override
  void didUpdateWidget(covariant _UserManagementBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inviteController != widget.inviteController) {
      oldWidget.inviteController?._invite = null;
      widget.inviteController?._invite = _invite;
    }
    // A new deep link while the board is already open: open that user too.
    if (oldWidget.focusUserId != widget.focusUserId) {
      _focusHandled = false;
      if (!_loading) _openFocusedUser();
    }
  }

  /// Opens the drawer for [UserManagementScreen.focusUserId] once, fetching the
  /// user directly so it works regardless of the current filters or page.
  Future<void> _openFocusedUser() async {
    final id = widget.focusUserId;
    if (id == null || id.isEmpty || _focusHandled) return;
    _focusHandled = true;
    try {
      final user = await _users.user(id);
      if (!mounted) return;
      _known[user.id] = user;
      _actions.openDrawer(user);
    } on ApiFailure {
      // User was deleted/not found — silently stay on the board.
    }
  }

  @override
  void dispose() {
    widget.inviteController?._invite = null;
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _users.users(
        query: _query,
        role: _roleF,
        status: _statusF,
        origin: _originF,
        sort: _sortKey,
        desc: _desc,
        page: _pageNum,
        perPage: _perPage,
      );
      // Drop a response that a newer load has already superseded.
      if (!mounted || gen != _loadGen) return;
      for (final u in page.items) {
        _known[u.id] = u;
      }
      setState(() {
        _page = page;
        _pageNum = page.page;
        _loading = false;
      });
      _openFocusedUser();
    } on ApiFailure catch (failure) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  void _resetAndReload() {
    // Replacing the result set (filter/sort/search/per-page/KPI) strands the
    // per-page selection off-page, so clear it — same rationale as _goToPage.
    setState(() {
      _pageNum = 1;
      _sel.clear();
    });
    _load();
  }

  /// Navigates to [page], clearing the selection — it's per-page, so carrying it
  /// across navigation would strand off-page ids that no bulk action can reach
  /// and resurrect stale checkmarks on return.
  void _goToPage(int page) {
    setState(() {
      _pageNum = page;
      _sel.clear();
    });
    _load();
  }

  void _onSearch(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), _resetAndReload);
  }

  void _toast(String msg) {
    if (!mounted) return;
    showGlassToast(context, context.t(msg), kind: GlassToastKind.success);
  }

  void _toastRaw(String msg, {GlassToastKind kind = GlassToastKind.error}) {
    if (!mounted) return;
    // context.t is idempotent for already-localized text but maps a fallback
    // key like 'errors.unexpected' (an ApiFailure.message) to real copy.
    showGlassToast(context, context.t(msg), kind: kind);
  }

  Future<void> _run(
    Future<void> Function() action,
    String successKey, {
    bool clearSel = false,
  }) async {
    try {
      await action();
      if (clearSel) _sel.clear();
      _toast(successKey);
      await _load();
    } on ApiFailure catch (failure) {
      _toastRaw(failure.message);
    }
  }

  // ── Actions bundle ─────────────────────────────────────────────────────
  UserActions get _actions {
    late final UserActions actions;
    return actions = UserActions(
      currentUserId: _currentUserId,
      isLastActiveAdmin: (u) => _page?.isLastActiveAdmin(u) ?? false,
      nameById: (id) =>
          _page?.items.where((u) => u.id == id).map((u) => u.name).firstOrNull,
      openDrawer: (u) => showUserDrawer(
        context,
        user: u,
        actions: actions,
        phone: context.isCompact,
      ),
      openEdit: (u) async {
        final result = await showEditModal(context, u);
        if (result == null) return;
        await _run(
          () => _users.updateDetails(
            u.id,
            displayName: result.name,
            title: result.title,
            email: result.email,
          ),
          'admin.um.toastProfileUpdated',
        );
      },
      activate: (ids) => _run(
        () => _users.setStatus(ids, UserStatus.active),
        ids.length == 1
            ? 'admin.um.toastActivated'
            : 'admin.um.toastActivatedMany',
        clearSel: true,
      ),
      approve: (ids) =>
          _run(() => _users.approve(ids), 'admin.um.approved', clearSel: true),
      openDeactivate: (ids) async {
        final users = _usersFor(ids);
        if (!await showDeactivateModal(context, users)) return;
        await _run(
          () => _users.setStatus(ids, UserStatus.disabled),
          'admin.um.toastDeactivated',
          clearSel: true,
        );
      },
      setRole: (ids, role) => _run(
        () => _users.setRole(ids, role),
        role == AdminRole.admin
            ? 'admin.um.toastPromoted'
            : 'admin.um.toastDemoted',
        clearSel: true,
      ),
      setOrgAdmin: (ids, orgAdmin) async {
        final users = _usersFor(ids);
        if (!await confirmOrgAdminChange(context, users, grant: orgAdmin)) {
          return false;
        }
        if (!mounted) return false;
        try {
          await _users.setOrgAdmin(ids, orgAdmin);
        } on ApiFailure catch (failure) {
          _toastRaw(failure.message);
          return false;
        }
        _sel.clear();
        _toast(
          orgAdmin
              ? 'admin.um.toastOrgAdminGranted'
              : 'admin.um.toastOrgAdminRevoked',
        );
        await _load();
        return true;
      },
      openDemote: (ids) async {
        final users = _usersFor(ids);
        if (!await showRevokeAdminModal(context, users)) return;
        await _run(
          () => _users.setRole(ids, AdminRole.user),
          'admin.um.toastDemoted',
          clearSel: true,
        );
      },
      openResend: (ids) async {
        final users = _usersFor(ids);
        if (!await showResendModal(context, users)) return;
        await _run(
          () => _users.resendInvites(ids),
          'admin.um.toastInviteResent',
          clearSel: true,
        );
      },
      openReset: (ids) async {
        final users = _usersFor(ids);
        if (!await showResetModal(context, users)) return;
        await _run(
          () => _users.sendPasswordReset(ids),
          'admin.um.toastResetSent',
          clearSel: true,
        );
      },
      revokeSessions: (ids) => _run(
        () => _users.revokeSessions(ids),
        'admin.um.toastSessionsRevoked',
        clearSel: true,
      ),
      openDelete: (ids) async {
        final users = _usersFor(ids);
        if (!await showDeleteModal(context, users)) return;
        await _run(
          () => _users.delete(ids),
          'admin.um.toastDeleted',
          clearSel: true,
        );
      },
    );
  }

  List<AdminUser> _usersFor(List<String> ids) =>
      ids.map((id) => _known[id]).whereType<AdminUser>().toList();

  Future<void> _invite() async {
    final result = await showInviteModal(context);
    if (result == null) return;
    try {
      final sent = await _users.invite(
        emails: result.emails,
        role: result.role,
        message: result.message,
      );
      if (!mounted) return;
      _toastRaw(
        context.t('admin.um.toastInvited', variables: {'n': '$sent'}),
        kind: GlassToastKind.success,
      );
      setState(() {
        _statusF = UserStatus.invited;
        _roleF = null;
        _pageNum = 1;
      });
      await _load();
    } on ApiFailure catch (failure) {
      _toastRaw(failure.message);
    }
  }

  // ── Filters ────────────────────────────────────────────────────────────
  void _setRoleFilter(AdminRole? role) {
    setState(() {
      _roleF = role;
      _statusF = null;
    });
    _resetAndReload();
  }

  void _setStatusFilter(UserStatus? status) {
    setState(() {
      _statusF = status;
      _roleF = null;
    });
    _resetAndReload();
  }

  void _setOriginFilter(UserOrigin? origin) {
    setState(() => _originF = origin);
    _resetAndReload();
  }

  void _sortBy(UserSortKey key) {
    setState(() {
      if (_sortKey == key) {
        _desc = !_desc;
      } else {
        _sortKey = key;
        _desc = key != UserSortKey.name;
      }
      _sel.clear();
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final board = Stack(
      children: [
        _body(context, compact: compact),
        if (_sel.isNotEmpty) _bulkBar(context),
      ],
    );
    // Wide: a section in the admin rail layout, whose PageChrome carries the
    // title and Invite; the filter row stays in-pane above the directory, as
    // the audit log's does.
    if (!compact) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _dockedToolbar(context, compact: false),
          ),
          Expanded(child: board),
        ],
      );
    }
    // Compact: title, back, Invite and the search/filter row all ride in the
    // shell's glass app bar (via PageChrome); the body draws no chrome.
    return PageChrome(
      title: context.t('admin.um.title'),
      onBack: widget.onBack,
      actions: [
        PageAction(
          icon: LucideIcons.userPlus,
          label: context.t('admin.um.inviteUsers'),
          onTap: (_) => _invite(),
          primary: true,
        ),
      ],
      bottom: _dockedToolbar(context, compact: true),
      bottomHeight: _kUmDockHeight,
      child: board,
    );
  }

  Widget _body(BuildContext context, {required bool compact}) {
    if (_loading && _page == null) {
      return const Center(child: HiveLoader());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(_error!),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }
    final page = _page!;
    // Compact scrolls under the glass app bar and spans the page; wide sits in
    // the admin pane, which already clears the bar and keeps the gutters.
    final gutter = compact ? context.pageGutter : 0.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        gutter,
        compact ? 14 + context.topGutter : 0,
        gutter,
        16 + context.bottomGutter + (_sel.isNotEmpty ? 64 : 0),
      ),
      children: [
        _kpis(context, page.counts),
        const SizedBox(height: 14),
        _directory(context, page),
        if (page.total > 0) ...[
          const SizedBox(height: 14),
          _pager(context, page),
        ],
      ],
    );
  }

  // ── KPI strip ──────────────────────────────────────────────────────────
  Widget _kpis(BuildContext context, AdminUserCounts c) {
    final cards = [
      UmKpiCard(
        icon: LucideIcons.users,
        iconBg: AppColors.canvas2,
        iconFg: AppColors.ink,
        value: '${c.total}',
        label: context.t('admin.um.kpiTotal'),
        active: _statusF == null && _roleF == null,
        onTap: () {
          setState(() {
            _statusF = null;
            _roleF = null;
          });
          _resetAndReload();
        },
      ),
      UmKpiCard(
        icon: LucideIcons.shieldCheck,
        iconBg: AppColors.accentSoft,
        iconFg: AppColors.accentStrong,
        value: '${c.admins}',
        label: context.t('admin.um.kpiAdmins'),
        active: _roleF == AdminRole.admin,
        onTap: () =>
            _setRoleFilter(_roleF == AdminRole.admin ? null : AdminRole.admin),
      ),
      UmKpiCard(
        icon: LucideIcons.circleCheck,
        iconBg: AppColors.success.withValues(alpha: 0.14),
        iconFg: AppColors.success,
        value: '${c.active}',
        label: context.t('admin.um.kpiActive'),
        active: _statusF == UserStatus.active,
        onTap: () => _setStatusFilter(
          _statusF == UserStatus.active ? null : UserStatus.active,
        ),
      ),
      UmKpiCard(
        icon: LucideIcons.mail,
        iconBg: AppColors.warning.withValues(alpha: 0.16),
        iconFg: AppColors.warning,
        value: '${c.invited}',
        label: context.t('admin.um.kpiInvites'),
        active: _statusF == UserStatus.invited,
        trailing: c.expiredInvites > 0
            ? Text(
                ' · ${context.t('admin.um.expiredCount', variables: {'n': '${c.expiredInvites}'})}',
                style: TextStyle(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dangerInk,
                ),
              )
            : null,
        onTap: () => _setStatusFilter(
          _statusF == UserStatus.invited ? null : UserStatus.invited,
        ),
      ),
      // Only surfaced when the admin-approval flag has produced pending sign-ups.
      if (c.pendingApproval > 0)
        UmKpiCard(
          icon: LucideIcons.clock,
          iconBg: const Color(0x14673AB7),
          iconFg: const Color(0xFF673AB7),
          value: '${c.pendingApproval}',
          label: context.t('admin.um.statusPending'),
          active: _statusF == UserStatus.pendingApproval,
          onTap: () => _setStatusFilter(
            _statusF == UserStatus.pendingApproval
                ? null
                : UserStatus.pendingApproval,
          ),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 720 ? 4 : 2;
        const gap = 12.0;
        final tileW = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in cards) SizedBox(width: tileW, child: c)],
        );
      },
    );
  }

  // ── Docked toolbar (search + filters, in the glass app bar) ──────────────
  /// Search + Role/Status/Origin filter chips, rendered as real glass components
  /// docked into the ProgressiveBlur app bar. Stacked (search over a scrollable
  /// chip row) on compact; a single row on wide.
  Widget _dockedToolbar(BuildContext context, {required bool compact}) {
    final search = GlassSearchField(
      hint: context.t('admin.um.searchHint'),
      controller: _searchCtrl,
      onChanged: _onSearch,
    );
    final roleChip = GlassFilterChip<AdminRole?>(
      icon: LucideIcons.shield,
      label: context.t('admin.um.filterRole'),
      value: _roleF,
      options: [
        (null, context.t('admin.um.allRoles')),
        (AdminRole.admin, context.t('admin.um.roleAdmin')),
        (AdminRole.user, context.t('admin.um.roleUser')),
      ],
      onChanged: _setRoleFilter,
    );
    final statusChip = GlassFilterChip<UserStatus?>(
      icon: LucideIcons.circleDot,
      label: context.t('admin.um.filterStatus'),
      value: _statusF,
      options: [
        (null, context.t('admin.um.anyStatus')),
        (UserStatus.active, context.t('admin.um.statusActive')),
        (UserStatus.disabled, context.t('admin.um.statusDisabled')),
        (UserStatus.invited, context.t('admin.um.statusInvited')),
        (UserStatus.pendingApproval, context.t('admin.um.statusPending')),
      ],
      onChanged: _setStatusFilter,
    );
    final originChip = GlassFilterChip<UserOrigin?>(
      icon: LucideIcons.keyRound,
      label: context.t('admin.um.filterOrigin'),
      value: _originF,
      options: [
        (null, context.t('admin.um.allOrigins')),
        (UserOrigin.local, originLabel(context, UserOrigin.local)),
        (UserOrigin.oidc, '${originLabel(context, UserOrigin.oidc)} (SSO)'),
        (UserOrigin.saml, '${originLabel(context, UserOrigin.saml)} (SSO)'),
        (UserOrigin.ldap, '${originLabel(context, UserOrigin.ldap)} (SSO)'),
      ],
      onChanged: _setOriginFilter,
    );

    final gutter = context.pageGutter;
    final chipRow = Row(
      children: [
        if (compact) ...[
          GlassSearchButton(
            tooltip: context.t('admin.um.searchHint'),
            active: _query.isNotEmpty,
            onTap: () => setState(() => _searching = true),
          ),
          const SizedBox(width: 8),
        ],
        roleChip,
        const SizedBox(width: 8),
        statusChip,
        const SizedBox(width: 8),
        originChip,
      ],
    );

    if (compact) {
      // One line, because that is all a page gets: the app bar's own title row
      // plus one docked row. The search used to take a row of its own above the
      // chips, which made three lines of chrome before the first person — so it
      // is a pill in the row now, and takes the row over only while somebody is
      // typing in it.
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: Align(
          child: GlassSearchDock(
            searching: _searching,
            controller: _searchCtrl,
            hint: context.t('admin.um.searchHint'),
            onChanged: _onSearch,
            onClose: () => setState(() => _searching = false),
            controls: SizedBox(
              height: kGlassControlHeight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // The gutter is spent above; inside the scroller it would clip
                // the last chip instead of letting it come into view.
                clipBehavior: Clip.none,
                child: chipRow,
              ),
            ),
          ),
        ),
      );
    }
    // Wide: a single row — bounded search + inline chips.
    return Row(
      children: [
        SizedBox(width: 300, child: search),
        const SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: chipRow,
          ),
        ),
      ],
    );
  }

  // ── Directory (table ⇄ cards) ────────────────────────────────────────────
  Widget _directory(BuildContext context, AdminUserPage page) {
    if (page.items.isEmpty) {
      return HiveEmptyState(
        title: context.t('admin.um.emptyTitle'),
        message: context.t('admin.um.emptyMessage'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        if (!wide) {
          return Column(
            children: [
              for (final u in page.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _UserCard(
                    user: u,
                    actions: _actions,
                    selected: _sel.contains(u.id),
                    onToggle: () => _toggleOne(u.id),
                    isMe: u.id == _currentUserId,
                  ),
                ),
            ],
          );
        }
        final showOrigin = constraints.maxWidth >= 920;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _tableHeader(context, page, showOrigin),
              for (final u in page.items)
                _UserTableRow(
                  user: u,
                  actions: _actions,
                  selected: _sel.contains(u.id),
                  onToggle: () => _toggleOne(u.id),
                  showOrigin: showOrigin,
                  isMe: u.id == _currentUserId,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tableHeader(
    BuildContext context,
    AdminUserPage page,
    bool showOrigin,
  ) {
    final pageIds = page.items.map((u) => u.id).toList();
    final allSel = pageIds.isNotEmpty && pageIds.every(_sel.contains);
    final someSel = pageIds.any(_sel.contains) && !allSel;
    Widget th(String key, UserSortKey? sort, int flex, {bool show = true}) {
      if (!show) return const SizedBox.shrink();
      final active = sort != null && _sortKey == sort;
      return Expanded(
        flex: flex,
        child: Semantics(
          button: sort != null,
          selected: active,
          child: InkWell(
            onTap: sort == null ? null : () => _sortBy(sort),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      key.toUpperCase(),
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                  if (active)
                    Icon(
                      _desc ? LucideIcons.arrowDown : LucideIcons.arrowUp,
                      size: 12,
                      color: AppColors.inkSoft,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          _Checkbox(
            checked: allSel,
            mixed: someSel,
            label: context.t('admin.um.selectPage'),
            onTap: () => _togglePage(pageIds),
          ),
          // 10 dp of gap, 6 of them inside the checkbox's hit area.
          const SizedBox(width: 4),
          th(context.t('admin.um.colUser'), UserSortKey.name, 3),
          th(context.t('admin.um.colRole'), UserSortKey.role, 2),
          if (showOrigin)
            th(context.t('admin.um.colOrigin'), UserSortKey.origin, 2),
          th(context.t('admin.um.colStatus'), UserSortKey.status, 2),
          th(context.t('admin.um.colLastActive'), UserSortKey.lastActive, 2),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  // ── Pagination ───────────────────────────────────────────────────────────
  Widget _pager(BuildContext context, AdminUserPage page) {
    final total = page.total;
    final pages = (total / _perPage).ceil().clamp(1, 9999);
    final start = (_pageNum - 1) * _perPage;
    final end = (start + _perPage).clamp(0, total);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      children: [
        Text(
          context.t(
            'admin.um.showingRange',
            variables: {
              'from': '${total == 0 ? 0 : start + 1}',
              'to': '$end',
              'total': '$total',
            },
          ),
          style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t('admin.um.rowsPerPage'),
              style: TextStyle(
                fontSize: AppType.label,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(width: 8),
            GlassPopupMenu<int>(
              value: _perPage,
              width: 120,
              onSelected: (v) {
                setState(() => _perPage = v);
                _resetAndReload();
              },
              items: const [
                GlassMenuItem<int>(value: 10, label: '10'),
                GlassMenuItem<int>(value: 25, label: '25'),
                GlassMenuItem<int>(value: 50, label: '50'),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_perPage',
                      style: TextStyle(
                        fontSize: AppType.label,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      LucideIcons.chevronDown,
                      size: 15,
                      color: AppColors.inkSoft,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _PagerButton(
              icon: backChevron(context),
              tooltip: context.t('common.pagination.previous'),
              enabled: _pageNum > 1,
              onTap: () => _goToPage(_pageNum - 1),
            ),
            for (final p in _pageList(_pageNum, pages))
              p == -1
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('…'),
                    )
                  : _PageNumber(
                      n: p,
                      active: p == _pageNum,
                      onTap: () => _goToPage(p),
                    ),
            _PagerButton(
              icon: forwardChevron(context),
              tooltip: context.t('common.pagination.next'),
              enabled: _pageNum < pages,
              onTap: () => _goToPage(_pageNum + 1),
            ),
          ],
        ),
      ],
    );
  }

  /// Compact pager list `[1 … 4 5 6 … 12]`; -1 marks an ellipsis.
  List<int> _pageList(int cur, int total) {
    if (total <= 7) return [for (var i = 1; i <= total; i++) i];
    final out = <int>[1];
    final lo = (cur - 1).clamp(2, total - 1);
    final hi = (cur + 1).clamp(2, total - 1);
    if (lo > 2) out.add(-1);
    for (var i = lo; i <= hi; i++) {
      out.add(i);
    }
    if (hi < total - 1) out.add(-1);
    out.add(total);
    return out;
  }

  // ── Bulk bar ───────────────────────────────────────────────────────────
  Widget _bulkBar(BuildContext context) {
    final selected =
        _page?.items.where((u) => _sel.contains(u.id)).toList() ?? [];
    if (selected.isEmpty) return const SizedBox.shrink();
    // Docked above the floating nav (or the safe area without one); the glass
    // bar scrolls its action strip internally, so it only needs the gutters.
    return GlassBulkBarDock(
      child: BulkActionBar(
        selected: selected,
        actions: _actions,
        onClear: () => setState(_sel.clear),
      ),
    );
  }

  // ── Selection helpers ────────────────────────────────────────────────────
  void _toggleOne(String id) => setState(() {
    _sel.contains(id) ? _sel.remove(id) : _sel.add(id);
  });

  void _togglePage(List<String> ids) => setState(() {
    final all = ids.every(_sel.contains);
    if (all) {
      _sel.removeAll(ids);
    } else {
      _sel.addAll(ids);
    }
  });
}
