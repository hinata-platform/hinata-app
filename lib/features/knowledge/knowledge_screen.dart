import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/hivora_repository.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
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
            edgeOffset: context.topGutter,
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
                  padding: EdgeInsets.fromLTRB(
                      context.pageGutter,
                      24 + context.topGutter,
                      context.pageGutter,
                      context.pageGutter + context.bottomGutter),
                  children: [
                    PageHead(
                      title: context.t('knowledge.title'),
                      subtitle: context.t('knowledge.summary',
                          variables: {'count': '${articles.length}'}),
                      actions: [
                        PrimaryButton(
                          label: context.t('knowledge.new'),
                          onPressed: () async {
                            final saved = await showArticleEditor(context);
                            if (saved != null) _cubit.load();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (roots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          context.t('knowledge.empty'),
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: AppColors.textSecondary),
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
    final updated = article.updatedAt;
    final meta = [
      if (article.tags.isNotEmpty) article.tags.first,
      if (updated != null) context.t('knowledge.updated', variables: {
        'when': '${updated.year}-${updated.month.toString().padLeft(2, '0')}-${updated.day.toString().padLeft(2, '0')}'
      }),
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            onTap: () => context.go('/knowledge/${article.id}'),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.description_outlined,
                      color: AppColors.accentStrong, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5, color: AppColors.inkSoft)),
                      ],
                    ],
                  ),
                ),
                if (children.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.subject_rounded,
                          size: 13, color: AppColors.inkFaint),
                      const SizedBox(width: 4),
                      Text('${children.length}',
                          style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 11.5,
                              color: AppColors.inkFaint)),
                    ],
                  ),
                ],
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
