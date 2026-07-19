import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/team_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../deletion/delete_flows.dart';
import 'team_modal_kit.dart';
import 'team_widgets.dart';

export 'team_member_modals.dart';
export 'team_project_modal.dart';

/// Create-team modal. Returns the created [Team] (so the caller can open it).
Future<Team?> showCreateTeamModal(BuildContext context) {
  final repo = context.read<TeamRepository>();
  return showTeamModal<Team>(context, _TeamFormBody(repo: repo), width: 580);
}

/// Edit-team modal. Returns true if the team was saved.
Future<bool?> showEditTeamModal(BuildContext context, Team team) {
  final repo = context.read<TeamRepository>();
  return showTeamModal<bool>(
    context,
    _TeamFormBody(repo: repo, existing: team),
    width: 580,
  );
}

/// Delete-team modal: warns about the access members lose, then streams the
/// cascade over SSE. Returns true if deleted.
Future<bool?> showDeleteTeamModal(BuildContext context, Team team) {
  return showDeleteTeamFlow(context, teamId: team.id, teamName: team.name);
}

class _TeamFormBody extends StatefulWidget {
  const _TeamFormBody({required this.repo, this.existing});

  final TeamRepository repo;
  final Team? existing;

  @override
  State<_TeamFormBody> createState() => _TeamFormBodyState();
}

class _TeamFormBodyState extends State<_TeamFormBody> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _key = TextEditingController(
    text: widget.existing?.key ?? '',
  );
  late final TextEditingController _desc = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late int _hue = widget.existing?.colorHue ?? 70;
  late String _icon = widget.existing?.icon ?? 'hexagon';
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _desc.dispose();
    super.dispose();
  }

  String get _effectiveKey {
    final typed = _key.text.trim().toUpperCase();
    if (typed.isNotEmpty) return typed;
    final from = _name.text.trim();
    return from.isEmpty
        ? ''
        : from.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.t('errors.required'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await widget.repo.updateTeam(widget.existing!.id, {
          'name': name,
          'key': _effectiveKey.isEmpty ? widget.existing!.key : _effectiveKey,
          'description': _desc.text.trim(),
          'colorHue': _hue,
          'icon': _icon,
        });
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final created = await widget.repo.createTeam(
          name: name,
          key: _effectiveKey.isEmpty
              ? name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase()
              : _effectiveKey,
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          colorHue: _hue,
          icon: _icon,
        );
        if (mounted) Navigator.of(context).pop(created);
      }
    } on ApiFailure catch (failure) {
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = teamHueColor(_hue);
    return ModalShell(
      icon: _isEdit ? LucideIcons.slidersHorizontal : LucideIcons.usersRound,
      title: context.t(_isEdit ? 'teams.editTitle' : 'teams.createTitle'),
      subtitle: context.t(
        _isEdit ? 'teams.editSubtitle' : 'teams.createSubtitle',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Identity row: live glyph + name + key.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.soft(color),
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: Icon(teamIcon(_icon), size: 26, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FieldLabel(context.t('teams.name')),
                    TextField(
                      controller: _name,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: teamFieldDecoration(
                        context,
                        hint: context.t('teams.namePlaceholder'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FieldLabel(context.t('teams.key')),
                    TextField(
                      controller: _key,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      maxLength: 5,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                      style: const TextStyle(fontFamily: AppTheme.fontMono),
                      decoration: teamFieldDecoration(context, hint: 'CORE'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FieldLabel(context.t('teams.description'), optional: true),
          TextField(
            controller: _desc,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 4,
            decoration: teamFieldDecoration(
              context,
              hint: context.t('teams.descriptionPlaceholder'),
            ),
          ),
          const SizedBox(height: 18),
          FieldLabel(context.t('teams.colorLabel')),
          ColorPicker(hue: _hue, onChanged: (h) => setState(() => _hue = h)),
          const SizedBox(height: 18),
          FieldLabel(context.t('teams.iconLabel')),
          IconPicker(
            selected: _icon,
            onChanged: (i) => setState(() => _icon = i),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
          ],
        ],
      ),
      footer: ModalFooter(
        primaryLabel: context.t(_isEdit ? 'common.save' : 'teams.createCta'),
        primaryIcon: _isEdit ? LucideIcons.check : LucideIcons.check,
        busy: _busy,
        onPrimary: _name.text.trim().isEmpty ? null : _submit,
      ),
    );
  }
}
