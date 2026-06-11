import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/hivora_repository.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import 'article_editor.dart';

/// Knowledge base: hierarchical list of organization-wide articles.
class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  late final FetchCubit<List<Article>> _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit(() => context.read<HivoraRepository>().articles())..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<List<Article>>, FetchState<List<Article>>>(
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: _cubit.load,
            child: AsyncView(
              isLoading: state.isLoading,
              hasData: state.hasData,
              errorKey: state.errorKey,
              onRetry: _cubit.load,
              builder: (context) {
                final articles = state.data!;
                final roots =
                    articles.where((article) => article.parentId == null).toList();
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(context.pageGutter),
                  children: [
                    SectionHeader(
                      title: context.t('knowledge.title'),
                      actionLabel: context.t('knowledge.new'),
                      onAction: () async {
                        final saved = await showArticleEditor(context);
                        if (saved != null) _cubit.load();
                      },
                    ),
                    const SizedBox(height: 12),
                    if (roots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          context.t('knowledge.empty'),
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    for (final root in roots)
                      _ArticleNode(article: root, all: articles, depth: 0),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ArticleNode extends StatelessWidget {
  const _ArticleNode({
    required this.article,
    required this.all,
    required this.depth,
  });

  final Article article;
  final List<Article> all;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final children =
        all.where((candidate) => candidate.parentId == article.id).toList();
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            onTap: () => context.go('/knowledge/${article.id}'),
            child: Row(
              children: [
                const Icon(Icons.description_rounded,
                    color: AppColors.accentPurple, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    article.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (children.isNotEmpty)
                  PillChip(
                    label: '${children.length}',
                    background: AppColors.surfaceMuted,
                  ),
              ],
            ),
          ),
          for (final child in children)
            _ArticleNode(article: child, all: all, depth: depth + 1),
        ],
      ),
    );
  }
}
