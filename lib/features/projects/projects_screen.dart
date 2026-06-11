import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late final FetchCubit<List<Project>> _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit(context.read<HivoraRepository>().projects)..load();
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
      child: BlocBuilder<FetchCubit<List<Project>>, FetchState<List<Project>>>(
        builder: (context, state) {
          final projects = state.data ?? const <Project>[];
          return RefreshIndicator(
            onRefresh: _cubit.load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      context.pageGutter, 16, context.pageGutter, 8),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(
                      title: context.t('projects.title'),
                      actionLabel: context.t('projects.new'),
                      onAction: _showCreate,
                    ),
                  ),
                ),
                if (state.isLoading && projects.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(color: AppColors.navy)),
                  )
                else if (projects.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(context.t('projects.empty'),
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.all(context.pageGutter),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: context.gridColumns(minTileWidth: 300),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        mainAxisExtent: 150,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _ProjectCard(project: projects[index], index: index),
                        childCount: projects.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showCreate() async {
    final repository = context.read<HivoraRepository>();
    final created = await WoltModalSheet.show<Project?>(
      context: context,
      pageListBuilder: (modalContext) => [
        WoltModalSheetPage(
          backgroundColor: AppColors.surface,
          hasTopBarLayer: false,
          child: RepositoryProvider.value(
            value: repository,
            child: const _CreateProjectBody(),
          ),
        ),
      ],
    );
    if (created != null) _cubit.load();
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.index});

  final Project project;
  final int index;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: AppColors.pastelFor(index),
      onTap: () => context.go('/issues?projectId=${project.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  project.key,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              const Spacer(),
              Text(
                context.t('projects.members',
                    variables: {'count': '${project.memberIds.length}'}),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          if ((project.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                project.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreateProjectBody extends StatefulWidget {
  const _CreateProjectBody();

  @override
  State<_CreateProjectBody> createState() => _CreateProjectBodyState();
}

class _CreateProjectBodyState extends State<_CreateProjectBody> {
  final _formKey = GlobalKey<FormState>();
  final _key = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t('projects.new'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: context.t('projects.name')),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? context.t('errors.required')
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _key,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: context.t('projects.key'),
                helperText: context.t('projects.keyHelp'),
              ),
              validator: (value) =>
                  RegExp(r'^[A-Za-z][A-Za-z0-9]{1,9}$').hasMatch(value ?? '')
                      ? null
                      : context.t('errors.invalidProjectKey'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration:
                  InputDecoration(labelText: context.t('issues.description')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.t('common.create')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final project = await context.read<HivoraRepository>().createProject(
            key: _key.text.trim().toUpperCase(),
            name: _name.text.trim(),
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(project);
    } on ApiFailure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }
}
