import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/app_config_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/admin_user_models.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveAvatar;
import '../admin_cards.dart';
import '../admin_settings_cubit.dart';
import '../admin_form_helpers.dart';
import 'admin_moderation_cubit.dart';
import 'admin_moderation_entry.dart';
import 'admin_moderation_rules.dart';

/// Admin → Moderation (HIN-26): who comes in without anybody deciding, who
/// moderates, the contact the operator publishes for reports, the house rules
/// and the file types people may upload. The role itself is handed out in
/// user management; the contact, the rules and the file types are saved with
/// the other settings.
class AdminModerationSection extends StatelessWidget {
  const AdminModerationSection({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final Map<String, dynamic> settings;

  /// Saves the settings draft as the Save action does; true once saved.
  final Future<bool> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AdminRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ModeratorsCubit(admin)..load()),
        BlocProvider(create: (_) => AccountEntryCubit(admin)..load()),
        BlocProvider(create: (_) => HouseRulesVersionsCubit(admin)..load()),
      ],
      // A save makes a new version of the rules when they read differently,
      // and may close a way in: both are read again once it is done. Not by
      // comparing the settings: the sections edit the draft in place, so the
      // answer equals what was sent whatever changed.
      child: BlocListener<AdminSettingsCubit, AdminSettingsState>(
        listenWhen: (before, now) => before.saving && !now.saving,
        listener: (context, _) {
          unawaited(context.read<AccountEntryCubit>().load());
          unawaited(context.read<HouseRulesVersionsCubit>().load());
        },
        child: _AdminModerationView(settings: settings, onSave: onSave),
      ),
    );
  }
}

class _AdminModerationView extends StatelessWidget {
  const _AdminModerationView({required this.settings, required this.onSave});

  final Map<String, dynamic> settings;
  final Future<bool> Function() onSave;

  Map<String, dynamic> get _moderation =>
      (settings['moderation'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  String _text(String key) => (_moderation[key] as String?) ?? '';

  /// Blank is no value: the server then falls back to its environment.
  void _put(String key, String value) {
    final text = value.trim();
    _moderation[key] = text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    // What /meta publishes, so the environment's address counts as a contact.
    final contactMissing = context.select<AppConfigBloc, bool>(
      (bloc) => bloc.state.meta?.moderation.contactMissing ?? false,
    );
    final entry = context.watch<AccountEntryCubit>().state;
    return AdminCards(
      note: accountEntryWorthShowing(entry)
          ? AccountEntryNotice(
              entry: entry!,
              settings: settings,
              onSave: onSave,
            )
          : null,
      cards: {
        'moderators': AdminSectionCard(
          icon: LucideIcons.shieldUser,
          title: context.t('admin.moderation.whoTitle'),
          subtitle: context.t('admin.moderation.whoHint'),
          children: const [_Moderators()],
        ),
        'contact': AdminSectionCard(
          icon: LucideIcons.mail,
          title: context.t('admin.moderation.contactTitle'),
          subtitle: context.t('admin.moderation.contactHint'),
          children: [
            if (contactMissing) ...[
              AdminNote(
                text: context.t('admin.moderation.contactMissing'),
                icon: LucideIcons.triangleAlert,
                tone: AdminNoteTone.warning,
              ),
              const SizedBox(height: 12),
            ],
            AdminField(
              label: context.t('admin.moderation.operatorName'),
              initialValue: _text('operatorName'),
              onChanged: (v) => _put('operatorName', v),
            ),
            AdminField(
              label: context.t('admin.moderation.contactEmail'),
              initialValue: _text('contactEmail'),
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => _put('contactEmail', v),
            ),
            AdminField(
              label: context.t('admin.moderation.imprintUrl'),
              hint: 'https://',
              initialValue: _text('imprintUrl'),
              keyboardType: TextInputType.url,
              onChanged: (v) => _put('imprintUrl', v),
            ),
          ],
        ),
        'rules': HouseRulesCard(moderation: _moderation),
        'types': AdminSectionCard(
          icon: LucideIcons.fileCheck,
          title: context.t('admin.moderation.typesTitle'),
          subtitle: context.t('admin.moderation.typesHint'),
          children: [_FileTypes(moderation: _moderation)],
        ),
      },
    );
  }
}

/// The groups of file types an instance can switch off (HIN-177), by the name
/// the server gives them and the key of their words, in the order they are
/// listed. Switching one off only narrows the server's safe list; nothing
/// here can widen it.
const _fileTypeGroups = {
  'IMAGES': 'images',
  'PDF': 'pdf',
  'OFFICE': 'office',
  'TEXT': 'text',
  'ZIP': 'zip',
  'VOICE': 'voice',
};

/// One switch per group, on while the group is allowed. Written into the
/// settings draft the shell saves, under `moderation.uploads.disabledGroups`.
class _FileTypes extends StatefulWidget {
  const _FileTypes({required this.moderation});

  final Map<String, dynamic> moderation;

  @override
  State<_FileTypes> createState() => _FileTypesState();
}

class _FileTypesState extends State<_FileTypes> {
  /// Read without writing: a draft nobody touched stays as the server sent it.
  Set<String> get _disabled {
    final uploads = widget.moderation['uploads'];
    final groups = uploads is Map ? uploads['disabledGroups'] : null;
    return {if (groups is List) ...groups.whereType<String>()};
  }

  void _allow(String group, bool allowed) => setState(() {
    final disabled = _disabled;
    allowed ? disabled.remove(group) : disabled.add(group);
    final uploads =
        (widget.moderation['uploads'] ??= <String, dynamic>{})
            as Map<String, dynamic>;
    // A group a newer server knows and this app does not stays as it is.
    uploads['disabledGroups'] = [
      for (final known in _fileTypeGroups.keys)
        if (disabled.contains(known)) known,
      ...disabled.where((name) => !_fileTypeGroups.containsKey(name)),
    ];
  });

  @override
  Widget build(BuildContext context) {
    final disabled = _disabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: group, value: words)
            in _fileTypeGroups.entries)
          AdminToggle(
            label: context.t('admin.moderation.types.$words'),
            subtitle: context.t('admin.moderation.types.${words}Hint'),
            value: !disabled.contains(group),
            onChanged: (allowed) => _allow(group, allowed),
          ),
      ],
    );
  }
}

/// The people who hold the role, with a word when one alone would decide on
/// reports about themselves.
class _Moderators extends StatelessWidget {
  const _Moderators();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ModeratorsCubit, ModeratorsState>(
        builder: (context, state) => switch (state.status) {
          ModeratorsStatus.loading => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: HiveLoader(size: 28)),
          ),
          ModeratorsStatus.failure => HiveEmptyState(
            title: context.t(state.errorKey ?? 'errors.unexpected'),
            action: OutlinedButton(
              onPressed: context.read<ModeratorsCubit>().load,
              child: Text(context.t('common.retry')),
            ),
          ),
          ModeratorsStatus.ready when state.moderators.isEmpty => AdminNote(
            text: context.t('admin.moderation.nobody'),
            icon: LucideIcons.triangleAlert,
            tone: AdminNoteTone.warning,
          ),
          ModeratorsStatus.ready => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final person in state.moderators) _ModeratorRow(person),
              if (state.total > state.moderators.length)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.t(
                      'admin.moderation.more',
                      variables: {
                        'count': '${state.total - state.moderators.length}',
                      },
                    ),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              if (state.total == 1) ...[
                const SizedBox(height: 8),
                AdminNote(
                  text: context.t('admin.moderation.onlyOne'),
                  tone: AdminNoteTone.info,
                ),
              ],
            ],
          ),
        },
      );
}

class _ModeratorRow extends StatelessWidget {
  const _ModeratorRow(this.person);

  final AdminUser person;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          HiveAvatar(
            name: person.name,
            imageUrl: person.avatarUrl,
            pronouns: person.pronouns,
            size: 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  style: TextStyle(
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  person.email,
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
  );
}
