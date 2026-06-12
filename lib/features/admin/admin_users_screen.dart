import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_avatar.dart';

// ─────────────────────────── User filter ─────────────────────────────────

enum _UserFilter { all, active, admin, inactive }

// ─────────────────────────── Admin Users Screen ──────────────────────────

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Map<String, dynamic>> _allUsers = const [];
  bool _loading = true;
  String? _error;
  String _query = '';
  _UserFilter _filter = _UserFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _allUsers = await context.read<HivoraRepository>().adminUsers();
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _allUsers;
    // Role/status filter
    list = switch (_filter) {
      _UserFilter.all => list,
      _UserFilter.active =>
        list.where((u) => u['active'] == true).toList(),
      _UserFilter.inactive =>
        list.where((u) => u['active'] != true).toList(),
      _UserFilter.admin => list
          .where((u) =>
              ((u['roles'] as List<dynamic>?) ?? []).contains('ADMIN'))
          .toList(),
    };
    // Text search
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((u) =>
              ((u['displayName'] as String?) ?? '')
                  .toLowerCase()
                  .contains(q) ||
              ((u['email'] as String?) ?? '')
                  .toLowerCase()
                  .contains(q) ||
              ((u['username'] as String?) ?? '')
                  .toLowerCase()
                  .contains(q))
          .toList();
    }
    return list;
  }

  Future<void> _patch(
      Map<String, dynamic> user, Map<String, dynamic> patch) async {
    try {
      await context
          .read<HivoraRepository>()
          .adminUpdateUser(user['id'] as String, patch);
      _load();
    } on ApiFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  Future<void> _showCreate() async {
    final repo = context.read<HivoraRepository>();
    final created = await WoltModalSheet.show<bool?>(
      context: context,
      pageListBuilder: (modalCtx) => [
        WoltModalSheetPage(
          backgroundColor: AppColors.surface,
          hasTopBarLayer: false,
          child: RepositoryProvider.value(
            value: repo,
            child: const _CreateUserForm(),
          ),
        ),
      ],
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Header bar ──────────────────────────────────────────
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.pageGutter, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border:
                Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () => context.pop(),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.arrow_back_rounded,
                      size: 20, color: AppColors.inkSoft),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.t('admin.title'),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.inkSoft)),
                  Text(context.t('admin.users'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.ink)),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _showCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: Text(context.t('admin.newUser')),
              ),
            ],
          ),
        ),

        // ── Search + filter bar ──────────────────────────────────
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: context.pageGutter, vertical: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Search field
              SizedBox(
                width: 260,
                height: 40,
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: context.t('admin.searchUsers'),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 18, color: AppColors.inkSoft),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              // Filter chips
              for (final f in _UserFilter.values)
                FilterChip(
                  label: Text(_filterLabel(context, f)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  selectedColor: AppColors.accentSoft,
                  checkmarkColor: AppColors.accentStrong,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: _filter == f
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: _filter == f
                        ? AppColors.accentStrong
                        : AppColors.inkSoft,
                  ),
                  side: BorderSide(
                    color: _filter == f
                        ? AppColors.accentLine
                        : AppColors.hairline,
                  ),
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              // User count
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  context.t('admin.userCount',
                      variables: {'count': '${_filtered.length}'}),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
        ),

        // ── Content ─────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.navy))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(context.t(_error!),
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed: _load,
                              child:
                                  Text(context.t('common.retry'))),
                        ],
                      ),
                    )
                  : _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.people_outline_rounded,
                                  size: 48, color: AppColors.inkFaint),
                              const SizedBox(height: 12),
                              Text(context.t('admin.noUsers'),
                                  style: const TextStyle(
                                      color: AppColors.inkSoft)),
                            ],
                          ),
                        )
                      : ResponsiveBuilder(
                          builder: (context, size) =>
                              size == LayoutSize.compact
                                  ? _UserCardList(
                                      users: _filtered,
                                      onPatch: _patch,
                                    )
                                  : _UserTable(
                                      users: _filtered,
                                      onPatch: _patch,
                                    ),
                        ),
        ),
      ],
    );
  }

  String _filterLabel(BuildContext context, _UserFilter f) =>
      switch (f) {
        _UserFilter.all => context.t('admin.filterAll'),
        _UserFilter.active => context.t('admin.filterActive'),
        _UserFilter.inactive => context.t('admin.filterInactive'),
        _UserFilter.admin => context.t('admin.filterAdmin'),
      };
}

// ─────────────────────────── Desktop table ───────────────────────────────

class _UserTable extends StatelessWidget {
  const _UserTable({required this.users, required this.onPatch});

  final List<Map<String, dynamic>> users;
  final void Function(Map<String, dynamic>, Map<String, dynamic>) onPatch;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          context.pageGutter, 8, context.pageGutter, 8 + context.bottomGutter),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(3),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(1.5),
            4: IntrinsicColumnWidth(),
          },
          children: [
            // Header
            TableRow(
              decoration: const BoxDecoration(
                color: AppColors.surfaceMuted,
                border: Border(
                    bottom: BorderSide(color: AppColors.hairline)),
              ),
              children: [
                _TH(context.t('admin.colUser')),
                _TH(context.t('admin.colEmail')),
                _TH(context.t('admin.colRoles')),
                _TH(context.t('admin.colStatus')),
                _TH(context.t('admin.colActions')),
              ],
            ),
            // Rows
            for (final user in users)
              TableRow(
                decoration: BoxDecoration(
                  border: const Border(
                      bottom: BorderSide(color: AppColors.hairline)),
                  color: user['active'] != true
                      ? const Color(0xFFFAF9F6)
                      : null,
                ),
                children: [
                  // User cell
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        AppAvatar(
                            name:
                                (user['displayName'] as String?) ?? '?',
                            radius: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                (user['displayName'] as String?) ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '@${(user['username'] as String?) ?? ''}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.inkSoft),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Email
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                    child: Text(
                      (user['email'] as String?) ?? '',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Roles
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final role in (user['roles'] as List<dynamic>?) ?? [])
                          _RoleBadge(role as String),
                      ],
                    ),
                  ),
                  // Status
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                    child: _StatusBadge(
                        active: user['active'] == true),
                  ),
                  // Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: _UserActions(user: user, onPatch: onPatch),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TH extends StatelessWidget {
  const _TH(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'IBMPlexMono',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.inkFaint,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─────────────────────────── Mobile card list ─────────────────────────────

class _UserCardList extends StatelessWidget {
  const _UserCardList({required this.users, required this.onPatch});

  final List<Map<String, dynamic>> users;
  final void Function(Map<String, dynamic>, Map<String, dynamic>) onPatch;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.all(context.pageGutter),
      itemCount: users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final user = users[i];
        final isAdmin = ((user['roles'] as List<dynamic>?) ?? [])
            .contains('ADMIN');
        final active = user['active'] == true;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  AppAvatar(
                      name: (user['displayName'] as String?) ?? '?',
                      radius: 22),
                  if (!active)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (user['displayName'] as String?) ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                    Text(
                      (user['email'] as String?) ?? '',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      children: [
                        _StatusBadge(active: active),
                        if (isAdmin)
                          _RoleBadge('ADMIN'),
                      ],
                    ),
                  ],
                ),
              ),
              _UserActions(user: user, onPatch: onPatch),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────── Shared row widgets ───────────────────────────

class _RoleBadge extends StatelessWidget {
  const _RoleBadge(this.role);
  final String role;

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'ADMIN';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAdmin
            ? AppColors.navy.withValues(alpha: 0.1)
            : AppColors.canvas2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isAdmin
                ? AppColors.navy.withValues(alpha: 0.3)
                : AppColors.hairline),
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isAdmin ? AppColors.navy : AppColors.inkSoft,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active
            ? AppColors.success.withValues(alpha: 0.12)
            : AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: active
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColors.danger.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        active
            ? context.t('admin.statusActive')
            : context.t('admin.statusInactive'),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: active ? AppColors.success : AppColors.danger,
        ),
      ),
    );
  }
}

class _UserActions extends StatelessWidget {
  const _UserActions({required this.user, required this.onPatch});

  final Map<String, dynamic> user;
  final void Function(Map<String, dynamic>, Map<String, dynamic>) onPatch;

  @override
  Widget build(BuildContext context) {
    final active = user['active'] == true;
    final isAdmin =
        ((user['roles'] as List<dynamic>?) ?? []).contains('ADMIN');
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded,
          size: 18, color: AppColors.inkSoft),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 36),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'toggle_active',
          child: Row(
            children: [
              Icon(
                active
                    ? Icons.person_off_rounded
                    : Icons.person_rounded,
                size: 16,
                color:
                    active ? AppColors.danger : AppColors.success,
              ),
              const SizedBox(width: 8),
              Text(
                context.t(active
                    ? 'admin.deactivate'
                    : 'admin.activate'),
                style: TextStyle(
                    color: active
                        ? AppColors.danger
                        : AppColors.success),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle_admin',
          child: Row(
            children: [
              Icon(
                isAdmin
                    ? Icons.shield_rounded
                    : Icons.shield_outlined,
                size: 16,
                color: AppColors.navy,
              ),
              const SizedBox(width: 8),
              Text(
                context.t(isAdmin
                    ? 'admin.removeAdmin'
                    : 'admin.makeAdmin'),
              ),
            ],
          ),
        ),
      ],
      onSelected: (action) {
        switch (action) {
          case 'toggle_active':
            onPatch(user, {'active': !active});
          case 'toggle_admin':
            onPatch(user, {'admin': !isAdmin});
        }
      },
    );
  }
}

// ─────────────────────────── Create user form ─────────────────────────────

class _CreateUserForm extends StatefulWidget {
  const _CreateUserForm();

  @override
  State<_CreateUserForm> createState() => _CreateUserFormState();
}

class _CreateUserFormState extends State<_CreateUserForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  bool _admin = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _username, _displayName, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 32 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t('admin.newUser'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _displayName,
              decoration:
                  InputDecoration(labelText: context.t('setup.displayName')),
              validator: (v) =>
                  (v == null || v.trim().isEmpty)
                      ? context.t('errors.required')
                      : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration:
                  InputDecoration(labelText: context.t('setup.email')),
              validator: (v) => v != null && v.contains('@')
                  ? null
                  : context.t('errors.invalidEmail'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration:
                  InputDecoration(labelText: context.t('setup.username')),
              validator: (v) =>
                  RegExp(r'^[a-zA-Z0-9._-]{3,40}$').hasMatch(v ?? '')
                      ? null
                      : context.t('errors.invalidUsername'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration:
                  InputDecoration(labelText: context.t('setup.password')),
              validator: (v) => (v ?? '').length >= 10
                  ? null
                  : context.t('errors.passwordTooShort'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.t('admin.isAdmin')),
              value: _admin,
              activeTrackColor: AppColors.navy,
              onChanged: (v) => setState(() => _admin = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.danger),
                    textAlign: TextAlign.center),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.t('common.create')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<HivoraRepository>().adminCreateUser({
        'email': _email.text.trim(),
        'username': _username.text.trim(),
        'displayName': _displayName.text.trim(),
        'password': _password.text,
        'admin': _admin,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }
}
