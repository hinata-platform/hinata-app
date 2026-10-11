import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/paged_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/lexical/hinata_document.dart';
import '../../../core/models/content_models.dart' show ArticleVersion;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../data/knowledge_models.dart';
import '../data/knowledge_repository.dart';
import '../knowledge_tokens.dart';
import '../widgets/knowledge_widgets.dart';

/// Loads one version in full.
typedef VersionLoader = Future<ArticleVersion> Function(int number);

/// A page's history: every saved version, newest first, and the one picked,
/// read as it was. Restoring makes the picked version the newest one; nothing
/// in between is lost.
///
/// Wide, list and version sit side by side. On a phone the list fills the
/// page and a picked version replaces it, with the way back in the app bar.
class KnowledgeHistoryView extends StatefulWidget {
  const KnowledgeHistoryView({
    super.key,
    required this.repo,
    required this.article,
    required this.versions,
    required this.loadVersion,
    required this.selected,
    required this.onSelect,
    required this.wide,
  });

  final KnowledgeRepository repo;
  final KbArticle article;

  /// The version list, paged.
  final PagedCubit<ArticleVersion> versions;
  final VersionLoader loadVersion;

  /// The version shown, if one is picked.
  final int? selected;
  final ValueChanged<int?> onSelect;
  final bool wide;

  @override
  State<KnowledgeHistoryView> createState() => _KnowledgeHistoryViewState();
}

class _KnowledgeHistoryViewState extends State<KnowledgeHistoryView> {
  Future<ArticleVersion>? _shown;
  int? _shownNumber;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(KnowledgeHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _follow();
  }

  void _follow() {
    final n = widget.selected;
    if (n == _shownNumber) return;
    _shownNumber = n;
    _shown = n == null ? null : widget.loadVersion(n);
  }

  @override
  Widget build(BuildContext context) {
    final list =
        BlocBuilder<PagedCubit<ArticleVersion>, PagedState<ArticleVersion>>(
          bloc: widget.versions,
          builder: (context, state) => _VersionList(
            repo: widget.repo,
            state: state,
            selected: widget.selected,
            onSelect: widget.onSelect,
            onMore: widget.versions.loadMore,
            onRetry: widget.versions.load,
          ),
        );
    if (!widget.wide) {
      return widget.selected == null ? list : _preview(context);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 320, child: list),
        const SizedBox(width: 28),
        Expanded(
          child: widget.selected == null
              ? HiveEmptyState(
                  title: context.t('knowledge.history.pickTitle'),
                  message: context.t('knowledge.history.pickMessage'),
                )
              : _preview(context),
        ),
      ],
    );
  }

  Widget _preview(BuildContext context) {
    return FutureBuilder<ArticleVersion>(
      future: _shown,
      builder: (context, snap) {
        if (snap.hasError) {
          return HiveEmptyState(
            title: context.t('knowledge.history.loadFailedTitle'),
            message: context.t('knowledge.history.loadFailedMessage'),
          );
        }
        final v = snap.data;
        if (v == null) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: HiveLoader()),
          );
        }
        final editor = widget.repo.userById(v.editorId ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                context.t(
                  'knowledge.history.versionBy',
                  variables: {
                    'number': '${v.number}',
                    'name':
                        editor?.name ?? context.t('knowledge.reader.someone'),
                    'when': kbDateTime(context, v.createdAt),
                  },
                ),
                style: TextStyle(
                  fontSize: AppType.label,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              v.title,
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: AppType.hero,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.6,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: KbTokens.readerMaxWidth,
              ),
              child: HinataDocument(doc: v.doc),
            ),
          ],
        );
      },
    );
  }
}

class _VersionList extends StatelessWidget {
  const _VersionList({
    required this.repo,
    required this.state,
    required this.selected,
    required this.onSelect,
    required this.onMore,
    required this.onRetry,
  });

  final KnowledgeRepository repo;
  final PagedState<ArticleVersion> state;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final VoidCallback onMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!state.hasData && state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: HiveLoader()),
      );
    }
    if (!state.hasData && state.errorKey != null) {
      return HiveEmptyState(
        title: context.t('knowledge.history.loadFailedTitle'),
        message: context.t('knowledge.history.loadFailedMessage'),
        action: OutlinedButton(
          onPressed: onRetry,
          child: Text(context.t('common.retry')),
        ),
      );
    }
    if (state.items.isEmpty) {
      return HiveEmptyState(
        title: context.t('knowledge.history.emptyTitle'),
        message: context.t('knowledge.history.emptyMessage'),
      );
    }
    final latest = state.items.first.number;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KbSectionLabel(
          context.t(
            'knowledge.history.versions',
            variables: {'count': '${state.total}'},
          ),
        ),
        const SizedBox(height: 6),
        for (final v in state.items)
          _VersionRow(
            version: v,
            editor: repo.userById(v.editorId ?? ''),
            current: v.number == latest,
            selected: v.number == selected,
            onTap: () => onSelect(v.number),
          ),
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              child: state.isLoadingMore
                  ? const HiveLoader(size: 18)
                  : TextButton(
                      onPressed: onMore,
                      child: Text(context.t('knowledge.history.more')),
                    ),
            ),
          ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.editor,
    required this.current,
    required this.selected,
    required this.onTap,
  });

  final ArticleVersion version;
  final KbUser? editor;
  final bool current;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(KbTokens.radiusControl),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(KbTokens.radiusControl),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  AppAvatar(
                    name: editor?.name ?? '?',
                    pronouns: editor?.pronouns,
                    radius: 15,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              context.t(
                                'knowledge.history.version',
                                variables: {'number': '${version.number}'},
                              ),
                              style: TextStyle(
                                fontSize: AppType.label,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            if (current) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusPill,
                                  ),
                                  border: Border.all(
                                    color: AppColors.hairline2,
                                  ),
                                ),
                                child: Text(
                                  context.t('knowledge.history.current'),
                                  style: TextStyle(
                                    fontSize: AppType.caption,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${editor?.name ?? context.t('knowledge.reader.someone')} · ${kbDateTime(context, version.createdAt)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: AppColors.inkSoft,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
