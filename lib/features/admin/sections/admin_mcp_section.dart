import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../admin_form_helpers.dart';

/// Admin → MCP (Model Context Protocol) server.
///
/// Configures the embedded MCP server that Personal Access Tokens authenticate
/// against. Values live in the shared admin-settings draft under the `mcp` key
/// and are persisted by the shell's Save button. Both settings are nullable —
/// leaving them unset falls back to the server's environment default:
///   • `enabled` — master switch for the MCP surface (and the PAT settings entry).
///   • `maxPatsPerUser` — cap on how many active tokens each user may hold.
class AdminMcpSection extends StatefulWidget {
  const AdminMcpSection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  @override
  State<AdminMcpSection> createState() => _AdminMcpSectionState();
}

class _AdminMcpSectionState extends State<AdminMcpSection> {
  Map<String, dynamic> get _mcp =>
      (widget.settings['mcp'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  late final TextEditingController _maxPats = TextEditingController(
    text: (_mcp['maxPatsPerUser'] as num?)?.toString() ?? '',
  );

  @override
  void dispose() {
    _maxPats.dispose();
    super.dispose();
  }

  void _onMaxPatsChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      // Cleared → inherit the server env default (nullable).
      _mcp['maxPatsPerUser'] = null;
      return;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed != null) _mcp['maxPatsPerUser'] = parsed < 0 ? 0 : parsed;
  }

  @override
  Widget build(BuildContext context) {
    final serverName = (_mcp['serverName'] as String?)?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminNote(text: context.t('admin.mcpHint')),
        const SizedBox(height: 16),

        // ── Server info (read-only) ───────────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.plug,
          title: context.t('admin.mcpServerTitle'),
          subtitle: context.t('admin.mcpServerHint'),
          children: [
            _ReadOnlyRow(
              label: context.t('admin.mcpServerName'),
              value: (serverName != null && serverName.isNotEmpty)
                  ? serverName
                  : context.t('admin.mcpServerNameFallback'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Access & limits ───────────────────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.keyRound,
          title: context.t('admin.mcpAccessTitle'),
          subtitle: context.t('admin.mcpAccessHint'),
          children: [
            AdminToggle(
              label: context.t('admin.mcpEnabledTitle'),
              subtitle: context.t('admin.mcpEnabledHint'),
              value: _mcp['enabled'] == true,
              onChanged: (v) => setState(() => _mcp['enabled'] = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _maxPats,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 14, color: AppColors.ink),
              decoration: adminInputDecoration(
                context,
                label: context.t('admin.mcpMaxPats'),
                helper: context.t('admin.mcpMaxPatsHint'),
                suffix: context.t('admin.mcpMaxPatsSuffix'),
              ),
              onChanged: _onMaxPatsChanged,
            ),
          ],
        ),
      ],
    );
  }
}

/// A read-only label/value line for server-provided info.
class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFamily: AppTheme.fontMono,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
