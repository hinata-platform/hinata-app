import 'package:flutter/material.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_avatar.dart';

/// Admin user management: list, create, activate/deactivate, promote.
class AdminUsersSection extends StatefulWidget {
  const AdminUsersSection({super.key});

  @override
  State<AdminUsersSection> createState() => _AdminUsersSectionState();
}

class _AdminUsersSectionState extends State<AdminUsersSection> {
  List<Map<String, dynamic>> _users = const [];
  bool _loading = true;
  String? _error;

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
      _users = await context.read<HivoraRepository>().adminUsers();
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(context.t('admin.users'),
                  style:
                      const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            TextButton.icon(
              onPressed: _showCreate,
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: Text(context.t('admin.newUser')),
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child:
                Center(child: HiveLoader()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.t(_error!),
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          for (final user in _users)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppAvatar(
                name: (user['displayName'] as String?) ?? '?',
                radius: 16,
              ),
              title: Text(
                (user['displayName'] as String?) ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Text(
                '${user['email']} · ${((user['roles'] as List<dynamic>?) ?? []).join(', ')}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: context.t(user['active'] == true
                        ? 'admin.deactivate'
                        : 'admin.activate'),
                    icon: Icon(
                      user['active'] == true
                          ? Icons.toggle_on_rounded
                          : Icons.toggle_off_rounded,
                      color: user['active'] == true
                          ? AppColors.success
                          : AppColors.textSecondary,
                      size: 30,
                    ),
                    onPressed: () =>
                        _patch(user, {'active': user['active'] != true}),
                  ),
                  IconButton(
                    tooltip: context.t('admin.toggleAdmin'),
                    icon: Icon(
                      Icons.shield_rounded,
                      color: ((user['roles'] as List<dynamic>?) ?? [])
                              .contains('ADMIN')
                          ? AppColors.navy
                          : AppColors.textSecondary,
                      size: 20,
                    ),
                    onPressed: () => _patch(user, {
                      'admin': !((user['roles'] as List<dynamic>?) ?? [])
                          .contains('ADMIN'),
                    }),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Future<void> _patch(Map<String, dynamic> user, Map<String, dynamic> patch) async {
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
    final repository = context.read<HivoraRepository>();
    final created = await WoltModalSheet.show<bool?>(
      context: context,
      pageListBuilder: (modalContext) => [
        WoltModalSheetPage(
          backgroundColor: AppColors.surface,
          hasTopBarLayer: false,
          child: RepositoryProvider.value(
            value: repository,
            child: const _CreateUserBody(),
          ),
        ),
      ],
    );
    if (created == true) _load();
  }
}

class _CreateUserBody extends StatefulWidget {
  const _CreateUserBody();

  @override
  State<_CreateUserBody> createState() => _CreateUserBodyState();
}

class _CreateUserBodyState extends State<_CreateUserBody> {
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
    for (final controller in [_email, _username, _displayName, _password]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
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
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.t('errors.required')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: context.t('setup.email')),
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
              onChanged: (value) => setState(() => _admin = value),
            ),
            if (_error != null)
              Text(_error!,
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: HiveLoader(
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
