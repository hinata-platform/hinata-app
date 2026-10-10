import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/billing_models.dart';
import '../../core/repositories/billing_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/widgets/glass_filter_bar.dart' show kGlassDockRow;
import '../../core/widgets/glass_switch_chip.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show GhostButton;
import '../shell/page_chrome.dart';
import 'billing_access_cubit.dart';
import 'invoice_draft_sheet.dart';
import 'invoice_widgets.dart';

/// The routes of billing (HIN-96).
const invoicesRoute = '/time/invoices';
const ratesRoute = '/time/rates';

/// The page behind `/time/invoices` (HIN-96): drafts and issued records,
/// newest first, and the way to draft a new one.
///
/// For organisation admins and project leads; a lead sees the invoices of the
/// projects they lead. Two lists, one switch — drafts are where work waits,
/// issued records are what has gone out.
class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        BillingAccessCubit(context.read<BillingRepository>())..load(),
    child: const _InvoicesView(),
  );
}

enum _Shelf {
  all(null, LucideIcons.files),
  drafts(InvoiceStatus.draft, LucideIcons.filePen),
  issued(InvoiceStatus.issued, LucideIcons.fileCheck2);

  const _Shelf(this.status, this.icon);

  final InvoiceStatus? status;
  final IconData icon;
}

class _InvoicesView extends StatefulWidget {
  const _InvoicesView();

  @override
  State<_InvoicesView> createState() => _InvoicesViewState();
}

class _InvoicesViewState extends State<_InvoicesView> {
  late final BillingRepository _billing = context.read<BillingRepository>();
  _Shelf _shelf = _Shelf.all;
  final Map<_Shelf, PagedCubit<InvoiceSummary>> _lists = {};

  PagedCubit<InvoiceSummary> _list(_Shelf shelf) =>
      _lists.putIfAbsent(shelf, () {
        final list = PagedCubit<InvoiceSummary>(
          (page, size) =>
              _billing.invoices(status: shelf.status, page: page, size: size),
          pageSize: 20,
          keyOf: (invoice) => invoice.id,
        );
        unawaited(list.load());
        return list;
      });

  @override
  void dispose() {
    for (final list in _lists.values) {
      unawaited(list.close());
    }
    super.dispose();
  }

  Future<void> _draft() async {
    final draft = await showInvoiceDraftSheet(context, billing: _billing);
    if (draft == null || !mounted) return;
    for (final list in _lists.values) {
      unawaited(list.load());
    }
    await _openInvoice(draft.summary.id);
  }

  Future<void> _openInvoice(String id) async {
    await context.push('$invoicesRoute/$id');
    if (!mounted) return;
    // What happened there — issued, credited, deleted — shows on return.
    for (final list in _lists.values) {
      unawaited(list.load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<BillingAccessCubit>().state;
    return PageChrome(
      contentMax: Breakpoints.readingWidth,
      title: context.t('billing.invoices.title'),
      actions: [
        if (access != null && access.invoices)
          PageAction(
            icon: LucideIcons.filePlus2,
            label: context.t('billing.invoice.new'),
            primary: true,
            onTap: (_) => unawaited(_draft()),
          ),
      ],
      bottom: access != null && access.invoices ? _switcher() : null,
      bottomHeight: access != null && access.invoices ? kGlassDockRow : 0,
      child: access == null
          ? const Center(child: HiveLoader(size: 30))
          : !access.invoices
          ? Center(
              child: HiveEmptyState(
                title: context.t('billing.invoices.title'),
                message: context.t('error.billing.forbidden'),
              ),
            )
          : _InvoiceList(
              key: ValueKey(_shelf),
              list: _list(_shelf),
              onOpen: (invoice) => unawaited(_openInvoice(invoice.id)),
              onDraft: () => unawaited(_draft()),
            ),
    );
  }

  Widget _switcher() => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: context.isCompact ? context.pageGutter : 0,
    ),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: LayoutBuilder(
        builder: (context, constraints) => GlassSwitchBar(
          maxWidth: constraints.maxWidth,
          chips: [
            for (final shelf in _Shelf.values)
              GlassSwitchChip(
                label: context.t('billing.invoices.shelf.${shelf.name}'),
                icon: shelf.icon,
                active: shelf == _shelf,
                onTap: () => setState(() => _shelf = shelf),
              ),
          ],
        ),
      ),
    ),
  );
}

class _InvoiceList extends StatelessWidget {
  const _InvoiceList({
    super.key,
    required this.list,
    required this.onOpen,
    required this.onDraft,
  });

  final PagedCubit<InvoiceSummary> list;
  final void Function(InvoiceSummary) onOpen;
  final VoidCallback onDraft;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      context.pageGutter,
      context.topGutter + 12,
      context.pageGutter,
      context.bottomGutter + 24,
    );
    return BlocBuilder<PagedCubit<InvoiceSummary>, PagedState<InvoiceSummary>>(
      bloc: list,
      builder: (context, state) {
        if (state.isLoading && state.items.isEmpty) {
          return Padding(
            padding: padding,
            child: const Align(
              alignment: Alignment.topCenter,
              child: HiveLoader(size: 30),
            ),
          );
        }
        if (state.errorKey != null && state.items.isEmpty) {
          return Padding(
            padding: padding,
            child: Align(
              alignment: Alignment.topCenter,
              child: HiveEmptyState(
                title: context.t('billing.invoices.title'),
                message: context.t(state.errorKey!),
                action: GhostButton(
                  icon: LucideIcons.refreshCw,
                  label: context.t('common.retry'),
                  onPressed: () => unawaited(list.load()),
                ),
              ),
            ),
          );
        }
        if (state.items.isEmpty) {
          return Padding(
            padding: padding,
            child: Align(
              alignment: Alignment.topCenter,
              child: HiveEmptyState(
                title: context.t('billing.invoices.emptyTitle'),
                message: context.t('billing.invoices.emptyMessage'),
                action: GhostButton(
                  icon: LucideIcons.filePlus2,
                  label: context.t('billing.invoice.new'),
                  onPressed: onDraft,
                ),
              ),
            ),
          );
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (state.hasMore && notification.metrics.extentAfter < 400) {
              unawaited(list.loadMore());
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: list.load,
            child: ListView.separated(
              padding: padding,
              itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index >= state.items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: HiveLoader(size: 26)),
                  );
                }
                final invoice = state.items[index];
                return InvoiceCard(
                  invoice: invoice,
                  onTap: () => onOpen(invoice),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
