part of 'dashboard_screen.dart';

// ══════════════════════════ Budgets ════════════════════════════════════════

/// The fullest time budgets the reader can see, as cells of a honeycomb on
/// the navy card the sprint stands on (HIN-152, "Honigstand").
///
/// Asks the server for the three fullest within the dashboard's own project
/// scope, so a person in fifty projects still costs one request, forecasts
/// included. A cell opens the budget's history; "all" opens the report's
/// budgets, where every budget the reader sees is listed.
class _BudgetsCard extends StatefulWidget {
  const _BudgetsCard({required this.projectIds});

  /// The dashboard's project scope; empty for all.
  final List<String> projectIds;

  @override
  State<_BudgetsCard> createState() => _BudgetsCardState();
}

class _BudgetsCardState extends State<_BudgetsCard> {
  late FetchCubit<TopBudgets> _top = _cubitFor(widget.projectIds);

  FetchCubit<TopBudgets> _cubitFor(List<String> projectIds) {
    final usage = TimeUsageCubit.maybeOf(context);
    return FetchCubit<TopBudgets>(
      () => usage == null
          ? Future.value(const TopBudgets())
          : usage.top(limit: 3, projectIds: projectIds),
    )..load();
  }

  @override
  void didUpdateWidget(_BudgetsCard old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.projectIds, widget.projectIds)) {
      unawaited(_top.close());
      _top = _cubitFor(widget.projectIds);
    }
  }

  @override
  void dispose() {
    unawaited(_top.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FetchCubit<TopBudgets>, FetchState<TopBudgets>>(
      bloc: _top,
      builder: (context, state) {
        final top = state.data;
        if (top == null && state.isLoading) {
          // The card keeps its place while the figures come, so the columns
          // do not shift when they arrive.
          return _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardHead(title: context.t('budget.dashboard.title')),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: HiveLoader(size: 26)),
                ),
              ],
            ),
          );
        }
        if (top == null || top.items.isEmpty) {
          // Failed or nothing to show: one calm line, never an error over a
          // side note.
          return _EmptyPanel(
            title: context.t('budget.dashboard.title'),
            message: context.t('budget.dashboard.emptyHint'),
          );
        }
        return _GlassCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryDeep.withValues(alpha: 0xE0 / 255),
              AppColors.primary.withValues(alpha: 0xD1 / 255),
            ],
          ),
          borderColor: Colors.white.withValues(alpha: .14),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -200,
                bottom: -230,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: .07,
                    child: HexMark(size: 420, color: AppColors.accent),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _head(context, top),
                  const SizedBox(height: 16),
                  _Honeycomb(top: top),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _head(BuildContext context, TopBudgets top) => Row(
    children: [
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            context.t('budget.dashboard.title').toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: AppType.caption,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.honeyOnNavy,
            ),
          ),
        ),
      ),
      const Spacer(),
      if (top.total > top.items.length)
        TextButton(
          onPressed: () => context.go('/time/reports?tab=budgets'),
          style: TextButton.styleFrom(foregroundColor: AppColors.honeyOnNavy),
          child: Text(
            context.t(
              'budget.dashboard.all',
              variables: {'count': '${top.total}'},
            ),
          ),
        ),
    ],
  );
}

/// Up to three cells: side by side with the middle one half a cell lower,
/// like a comb, where they fit; wrapped and centred where they do not.
class _Honeycomb extends StatelessWidget {
  const _Honeycomb({required this.top});

  final TopBudgets top;

  @override
  Widget build(BuildContext context) {
    Widget cell(ProjectTimeUsage usage) => ProjectForecast(
      projectId: usage.projectId,
      builder: (context, forecast) => BudgetCell(
        label: top.names[usage.projectId] ?? '',
        gauge: usage.budget!,
        footer: forecast == null
            ? null
            : ForecastLine.sentence(context, forecast),
        // The cell opens the budget's history, where the same figures have
        // room to explain themselves (HIN-156).
        onTap: () => showBudgetHistorySheet(
          context,
          projectId: usage.projectId,
          projectName: top.names[usage.projectId] ?? '',
        ),
      ),
    );
    // Time budgets only: the server ranks nothing else here.
    final items = top.items;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits =
            constraints.maxWidth >=
            BudgetCell.slotWidth(context) * items.length;
        if (!fits || items.length < 3) {
          return Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 8,
            runSpacing: 12,
            children: [for (final usage in items) cell(usage)],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i.isOdd ? 34 : 0),
                child: cell(items[i]),
              ),
          ],
        );
      },
    );
  }
}
