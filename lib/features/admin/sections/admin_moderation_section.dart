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
import '../admin_form_helpers.dart';
import 'admin_moderation_cubit.dart';

/// Admin → Moderation (HIN-26): who moderates, and the contact the operator
/// publishes for reports. The role itself is handed out in user management;
/// the contact is saved with the other settings.
class AdminModerationSection extends StatelessWidget {
  const AdminModerationSection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        ModeratorsCubit(context.read<AdminRepository>())..load(),
    child: _AdminModerationView(settings: settings),
  );
}

class _AdminModerationView extends StatelessWidget {
  const _AdminModerationView({required this.settings});

  final Map<String, dynamic> settings;

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
    return AdminCards(
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
      },
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
