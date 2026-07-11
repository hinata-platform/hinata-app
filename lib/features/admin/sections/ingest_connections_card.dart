import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/ingest_models.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/hue_colors.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../sprint/modals/glass_modal.dart';
import '../admin_form_helpers.dart';
import 'ingest_connection_editor.dart';

/// E-mail-to-ticket connection management: any number of IMAP mailbox/folder
/// connections, each feeding a different project. Replaces the former single
/// fixed mailbox config.
class IngestConnectionsCard extends StatefulWidget {
  const IngestConnectionsCard({super.key});

  @override
  State<IngestConnectionsCard> createState() => _IngestConnectionsCardState();
}

class _IngestConnectionsCardState extends State<IngestConnectionsCard> {
  AdminRepository get _repo => context.read<AdminRepository>();

  List<IngestConnection> _connections = [];

  /// Resolved project labels ("KEY · Name") per project id, for the tiles.
  final Map<String, IngestProjectOption> _projects = {};
  bool _loading = true;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final connections = await _repo.ingestConnections();
      await _resolveProjects(connections);
      if (!mounted) return;
      setState(() {
        _connections = connections;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  /// Best-effort: map the referenced project ids to display options so tiles
  /// can show "KEY · Name" instead of a raw id.
  Future<void> _resolveProjects(List<IngestConnection> connections) async {
    final missing = connections
        .map((c) => c.projectId)
        .whereType<String>()
        .where((id) => id.isNotEmpty && !_projects.containsKey(id))
        .toSet();
    if (missing.isEmpty) return;
    try {
      var page = 0;
      while (missing.isNotEmpty) {
        final result = await _repo.ingestProjectOptions(page: page, size: 100);
        if (result.items.isEmpty) break;
        for (final option in result.items) {
          _projects[option.id] = option;
          missing.remove(option.id);
        }
        page++;
        if (page * 100 >= result.total) break;
      }
    } on ApiFailure {
      // Tiles fall back to the raw id — never block the list on this.
    }
  }

  Future<void> _toggle(IngestConnection connection, bool enabled) async {
    final index = _connections.indexOf(connection);
    setState(() =>
        _connections[index] = connection.copyWith(enabled: enabled));
    try {
      final saved = await _repo
          .updateIngestConnection(connection.copyWith(enabled: enabled));
      if (!mounted) return;
      setState(() => _connections[index] = saved);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _connections[index] = connection);
      _showError(failure);
    }
  }

  Future<void> _edit([IngestConnection? connection]) async {
    final result = await showIngestConnectionEditor(
      context,
      connection: connection,
      initialProject: connection?.projectId != null
          ? _projects[connection!.projectId]
          : null,
    );
    if (result == null || !mounted) return;
    _projects[result.project.id] = result.project;
    setState(() {
      final index =
          _connections.indexWhere((c) => c.id == result.connection.id);
      if (index >= 0) {
        _connections[index] = result.connection;
      } else {
        _connections = [..._connections, result.connection];
      }
    });
  }

  Future<void> _delete(IngestConnection connection) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('admin.ingest.deleteTitle'),
      message: context.t('admin.ingest.deleteBody',
          variables: {'name': connection.label}),
      confirmLabel: context.t('common.delete'),
      destructive: true,
      confirmIcon: LucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repo.deleteIngestConnection(connection.id!);
      if (!mounted) return;
      setState(() => _connections =
          _connections.where((c) => c.id != connection.id).toList());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      _showError(failure);
    }
  }

  void _showError(ApiFailure failure) {
    showGlassErrorToast(context, context.t(failure.message));
  }

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      icon: LucideIcons.inbox,
      title: context.t('admin.emailIngest'),
      subtitle: context.t('admin.emailIngestHint'),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: HiveLoader(size: 28)),
          )
        else if (_errorKey != null)
          HiveEmptyState(
            card: false,
            title: context.t(_errorKey!),
            action: OutlinedButton(
              onPressed: _load,
              child: Text(context.t('common.retry')),
            ),
          )
        else if (_connections.isEmpty)
          HiveEmptyState(
            card: false,
            title: context.t('admin.ingest.emptyTitle'),
            message: context.t('admin.ingest.emptyMessage'),
            action: OutlinedButton.icon(
              onPressed: _edit,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(context.t('admin.ingest.addConnection')),
            ),
          )
        else ...[
          for (final connection in _connections)
            _ConnectionTile(
              connection: connection,
              project: connection.projectId != null
                  ? _projects[connection.projectId]
                  : null,
              onToggle: (v) => _toggle(connection, v),
              onEdit: () => _edit(connection),
              onDelete: () => _delete(connection),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _edit,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(context.t('admin.ingest.addConnection')),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.connection,
    required this.project,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final IngestConnection connection;
  final IngestProjectOption? project;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final enabled = connection.enabled;
    final projectLabel = project != null
        ? '${project!.key} · ${project!.name}'
        : (connection.projectId ?? context.t('admin.ingest.noProject'));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: enabled ? AppColors.accentLine : AppColors.hairline2),
      ),
      child: Row(
        children: [
          HiveSwitch(value: enabled, onChanged: onToggle),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  connection.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: enabled ? AppColors.ink : AppColors.inkSoft,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MetaChip(
                        icon: LucideIcons.server,
                        text: '${connection.host}:${connection.port}'),
                    _MetaChip(
                        icon: LucideIcons.folder, text: connection.folder),
                    _MetaChip(
                      icon: LucideIcons.squareKanban,
                      text: projectLabel,
                      color: project != null
                          ? colorFromHex(project!.color)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.t('common.edit'),
            icon: Icon(LucideIcons.pencil, size: 16, color: AppColors.inkSoft),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: context.t('common.delete'),
            icon: Icon(LucideIcons.trash2, size: 16, color: AppColors.inkSoft),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color ?? AppColors.inkFaint),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
