import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';
import 'admin_sso_section.dart';
import 'admin_users_section.dart';

/// Admin area: server-side runtime settings (SSO, e-mail ingest) and users.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _settings;
  bool _loading = true;
  bool _saving = false;
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
      _settings = await context.read<HivoraRepository>().adminSettings();
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    try {
      _settings =
          await context.read<HivoraRepository>().updateAdminSettings(_settings!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t('admin.saved'))));
      }
    } on ApiFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.navy));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.t(_error!),
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: Text(context.t('common.retry'))),
          ],
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.all(context.pageGutter),
      children: [
        Row(
          children: [
            Expanded(child: SectionHeader(title: context.t('admin.title'))),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(context.t('common.save')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          context.t('admin.subtitle'),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        SoftCard(
          child: AdminSsoSection(settings: _settings!),
        ),
        const SizedBox(height: 16),
        SoftCard(
          child: AdminEmailIngestSection(settings: _settings!),
        ),
        const SizedBox(height: 16),
        const SoftCard(child: AdminUsersSection()),
      ],
    );
  }
}
