import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/repositories/moderation_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/soft_card.dart';
import '../house_rules_sheet.dart' show openHouseRules;
import '../widgets/moderation_hex.dart';
import '../widgets/statement_view.dart';
import 'appeal_sheet.dart';
import 'notice_cubit.dart';

export '../moderation_locations.dart' show noticeLocation;

/// The notice of the moderation to the person concerned (HIN-173), for
/// `/notices/:caseId`.
class NoticeScreen extends StatelessWidget {
  const NoticeScreen({super.key, required this.caseId});

  final String caseId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        NoticeCubit(context.read<ModerationRepository>(), caseId)..load(),
    child: const NoticeView(),
  );
}

/// The notice, or why there is none; dumb, it renders [NoticeCubit].
class NoticeView extends StatelessWidget {
  const NoticeView({super.key});

  /// The width a notice reads at on a wide window.
  static const double _readingWidth = 680;

  @override
  Widget build(BuildContext context) => BlocBuilder<NoticeCubit, NoticeState>(
    builder: (context, state) {
      final statement = state.statement;
      return switch (state.status) {
        NoticeStatus.loading => const Center(child: HiveLoader()),
        NoticeStatus.gone => HiveEmptyState(
          title: context.t('moderation.notice.goneTitle'),
          message: context.t('moderation.notice.goneMessage'),
          action: OutlinedButton(
            onPressed: () => unawaited(openHouseRules(context)),
            child: Text(context.t('moderation.notice.rules')),
          ),
        ),
        NoticeStatus.failure => HiveEmptyState(
          title: context.t('moderation.notice.failedTitle'),
          message: context.t(state.errorKey ?? 'errors.unexpected'),
          action: OutlinedButton(
            onPressed: () => unawaited(context.read<NoticeCubit>().load()),
            child: Text(context.t('common.retry')),
          ),
        ),
        NoticeStatus.ready when statement != null => ListView(
          padding: context.pagePadding,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _readingWidth),
                child: SoftCard(
                  padding: EdgeInsets.all(context.isCompact ? 18 : 24),
                  child: _Notice(statement: statement),
                ),
              ),
            ),
          ],
        ),
        NoticeStatus.ready => const SizedBox.shrink(),
      };
    },
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.statement});

  final Statement statement;

  @override
  Widget build(BuildContext context) {
    final s = statement;
    final rules = s.rulesUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(statement: s),
        const SizedBox(height: 10),
        StatementView(statement: s),
        const SizedBox(height: 16),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 10,
          overflowSpacing: 8,
          overflowAlignment: OverflowBarAlignment.end,
          children: [
            if (rules != null && rules.isNotEmpty)
              OutlinedButton(
                onPressed: () => unawaited(
                  launchUrl(
                    context.read<ModerationRepository>().page(rules),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                child: Text(context.t('moderation.notice.rules')),
              ),
            if (s.appealable)
              FilledButton.icon(
                onPressed: () => unawaited(
                  showAppealSheet(context, context.read<NoticeCubit>()),
                ),
                icon: const Icon(LucideIcons.rotateCcw, size: 16),
                label: Text(context.t('moderation.notice.appeal')),
              ),
          ],
        ),
      ],
    );
  }
}

/// The cell, the headline and whose notice it is. Large text in a narrow
/// column puts the cell above the words.
class _Head extends StatelessWidget {
  const _Head({required this.statement});

  final Statement statement;

  @override
  Widget build(BuildContext context) {
    final suspends = statement.suspends;
    final hex = ModerationHex(
      glyph: suspends ? LucideIcons.userX : LucideIcons.eyeOff,
      label: context.t(
        suspends ? 'moderation.state.suspended' : 'moderation.state.removed',
      ),
      fill: 1,
      size: 40,
      words: false,
    );
    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            statement.headline,
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: AppType.heading,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        Text(
          context.t('moderation.notice.from'),
          style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 420 &&
            MediaQuery.textScalerOf(context).scale(10) > 15;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [hex, const SizedBox(height: 10), titles],
          );
        }
        return Row(
          children: [
            hex,
            const SizedBox(width: 14),
            Expanded(child: titles),
          ],
        );
      },
    );
  }
}
