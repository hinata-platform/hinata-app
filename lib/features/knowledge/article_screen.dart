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

class ArticleScreen extends StatefulWidget {
  const ArticleScreen({super.key, required this.articleId});

  final String articleId;

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late final FetchCubit<Article> _cubit;

  @override
  void initState() {
    super.initState();
    _cubit =
        FetchCubit(() => context.read<HivoraRepository>().article(widget.articleId))
          ..load();
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
      child: BlocBuilder<FetchCubit<Article>, FetchState<Article>>(
        builder: (context, state) {
          return AsyncView(
            isLoading: state.isLoading,
            hasData: state.hasData,
            errorKey: state.errorKey,
            onRetry: _cubit.load,
            builder: (context) {
              final article = state.data!;
              return SingleChildScrollView(
                padding: EdgeInsets.all(context.pageGutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => context.canPop()
                              ? context.pop()
                              : context.go('/knowledge'),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: context.t('common.edit'),
                          onPressed: () async {
                            final saved =
                                await showArticleEditor(context, existing: article);
                            if (saved != null) _cubit.load();
                          },
                          icon: const Icon(Icons.edit_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SoftCard(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            article.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (article.tags.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final tag in article.tags)
                                  PillChip(
                                      label: '#$tag',
                                      background: AppColors.pastelLavender),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          SelectableText(
                            article.content ?? '',
                            style: const TextStyle(height: 1.6, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
