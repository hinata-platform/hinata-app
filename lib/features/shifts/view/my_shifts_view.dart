import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/auth_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/glass_filter_bar.dart' show kGlassDockRow;
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../shell/page_chrome.dart';
import '../../sprint/modals/glass_modal.dart' show anchorRectOfContext;
import '../bloc/my_shifts_cubit.dart';
import '../bloc/my_shifts_snapshot_cubit.dart';
import '../bloc/next_shift_cubit.dart';
import '../shift_texts.dart';
import '../shift_views.dart';
import '../widgets/next_shift_hero.dart';
import '../widgets/shift_actions.dart';
import '../widgets/shift_row.dart';
import '../widgets/shift_sheet.dart';
import '../widgets/shift_status_badge.dart';
import '../widgets/shift_visibility.dart';
import '../widgets/shifts_head.dart';

/// `/shifts`: provides the cubits of "Meine Schichten" and wires their fresh
/// answers into the offline snapshot.
class MyShiftsPage extends StatelessWidget {
  const MyShiftsPage({super.key, this.now});

  /// The clock, for tests.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ShiftRepository>();
    final snapshot = context.read<MyShiftsSnapshotCubit>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) =>
              MyShiftsCubit(repository, onFirstPage: snapshot.recordRows)
                ..load(),
        ),
        BlocProvider(
          create: (_) =>
              NextShiftCubit(repository, onNext: snapshot.recordNext, now: now)
                ..load(),
        ),
      ],
      child: Builder(
        builder: (context) => ShiftVisibilityRelay(
          onVisible: (visible) {
            context.read<MyShiftsCubit>().setVisible(visible);
            context.read<NextShiftCubit>().setVisible(visible);
          },
          child: MyShiftsView(now: now),
        ),
      ),
    );
  }
}

/// "Meine Schichten" (HIN-44): the hero with the next shift, the caller's
/// waiting lists (HIN-162), their shifts by day, and the open shifts in their
/// projects. Offline it draws the snapshot, people counted and never named.
class MyShiftsView extends StatelessWidget {
  const MyShiftsView({super.key, this.now});

  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return PageChrome(
      bottom: compact ? const ShiftsDock(current: ShiftsView.mine) : null,
      bottomHeight: compact ? kGlassDockRow : 0,
      child: compact
          ? _Body(now: now ?? DateTime.now, compact: true)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ShiftsHead(current: ShiftsView.mine),
                Expanded(
                  child: _Body(now: now ?? DateTime.now, compact: false),
                ),
              ],
            ),
    );
  }
}

/// One line of the list: a day's header or a shift.
sealed class _Entry {
  const _Entry();
}

class _Header extends _Entry {
  const _Header(this.text, {this.trailing});
  final String text;
  final String? trailing;
}

class _Mine extends _Entry {
  const _Mine(this.shift);
  final MyShift shift;
}

class _Open extends _Entry {
  const _Open(this.shift, this.event);
  final Shift shift;
  final ShiftEventHead? event;
}

class _Waiting extends _Entry {
  const _Waiting(this.shift);
  final MyShift shift;
}

class _Gap extends _Entry {
  const _Gap(this.height);
  final double height;
}

class _Widget extends _Entry {
  const _Widget(this.child);
  final Widget child;
}

/// The page's frame: which of loading, failure, offline and the list it is.
///
/// It reads only what decides that, so the three cubits behind the page
/// rebuild their own part and nothing else: the hero, the waiting lists, the
/// own rows and the open shifts are slivers of their own, each with its own
/// selector. The snapshot is read only while offline.
class _Body extends StatelessWidget {
  const _Body({required this.now, required this.compact});

  final DateTime Function() now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hasData = context.select<MyShiftsCubit, bool>((c) => c.state.hasData);
    final errorKey = context.select<MyShiftsCubit, String?>(
      (c) => c.state.errorKey,
    );
    final snapshotEmpty = context.select<MyShiftsSnapshotCubit, bool>(
      (c) => c.state.isEmpty,
    );

    // Offline: the list could not be read and there is a snapshot to show.
    final failed = errorKey != null && !hasData;
    final offline = failed && !snapshotEmpty;
    if (!hasData && !failed) {
      return const Center(child: HiveLoader());
    }
    if (failed && !offline) {
      return _Failure(
        errorKey: errorKey,
        onRetry: () {
          unawaited(context.read<MyShiftsCubit>().load());
          unawaited(context.read<NextShiftCubit>().load());
        },
      );
    }

    final rows = _Rows(now: now, compact: compact, offline: offline);
    final heroSliver = compact
        ? SliverToBoxAdapter(child: _HeroSlot(rows: rows, gap: 28))
        : null;

    final list = NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (!offline && n.metrics.extentAfter < 400) {
          unawaited(context.read<MyShiftsCubit>().loadMore());
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => Future.wait([
          context.read<MyShiftsCubit>().load(),
          context.read<NextShiftCubit>().load(),
        ]),
        child: CustomScrollView(
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                context.pageGutter,
                compact ? context.pageGutter + context.topGutter : 4,
                compact ? context.pageGutter : 0,
                // The last row scrolls clear of the floating nav.
                context.pageGutter + context.bottomGutter,
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  ?heroSliver,
                  if (offline)
                    _OfflineRows(rows: rows)
                  else ...[
                    _MineRows(rows: rows, emptyOnly: true),
                    _WaitingRows(rows: rows),
                    _MineRows(rows: rows),
                    _OpenRows(rows: rows),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (compact) return list;
    // Wide: the list beside the hero, 62 to 38, once there is a hero.
    return _HeroBeside(rows: rows, list: list);
  }
}

/// Lays [entries] out lazily, one sliver.
class _EntrySliver extends StatelessWidget {
  const _EntrySliver({required this.rows, required this.entries});

  final _Rows rows;
  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) => SliverList.builder(
    itemCount: entries.length,
    itemBuilder: (context, i) => rows.entry(context, entries[i]),
  );
}

/// The next shift, from the next-shift cubit alone; offline from the
/// snapshot.
class _HeroSlot extends StatelessWidget {
  const _HeroSlot({required this.rows, this.gap = 0});

  final _Rows rows;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final MyShift? next;
    final ShiftDetail? detail;
    if (rows.offline) {
      next = context.select<MyShiftsSnapshotCubit, MyShift?>(
        (c) => c.state.next,
      );
      detail = null;
    } else {
      next = context.select<NextShiftCubit, MyShift?>((c) => c.state.next);
      detail = context.select<NextShiftCubit, ShiftDetail?>(
        (c) => c.state.nextDetail,
      );
    }
    if (next == null) return const SizedBox.shrink();
    final hero = rows.hero(context, next, detail);
    return gap == 0
        ? hero
        : Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: hero,
          );
  }
}

/// Wide: the list, and the hero beside it once there is one.
class _HeroBeside extends StatelessWidget {
  const _HeroBeside({required this.rows, required this.list});

  final _Rows rows;
  final Widget list;

  @override
  Widget build(BuildContext context) {
    final hasNext = rows.offline
        ? context.select<MyShiftsSnapshotCubit, bool>(
            (c) => c.state.next != null,
          )
        : context.select<NextShiftCubit, bool>((c) => c.state.next != null);
    if (!hasNext) return list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 62, child: list),
        const SizedBox(width: 24),
        Expanded(
          flex: 38,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              0,
              4,
              context.pageGutter,
              context.pageGutter + context.bottomGutter,
            ),
            child: _HeroSlot(rows: rows),
          ),
        ),
      ],
    );
  }
}

/// The compact group above the list: the shifts the caller waits for.
class _WaitingRows extends StatelessWidget {
  const _WaitingRows({required this.rows});

  final _Rows rows;

  @override
  Widget build(BuildContext context) {
    final waiting = context.select<NextShiftCubit, List<MyShift>>(
      (c) => c.state.waiting,
    );
    final failed = context.select<NextShiftCubit, bool>(
      (c) => c.state.waitingFailed,
    );
    if (waiting.isEmpty && !failed) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return _EntrySliver(
      rows: rows,
      entries: [
        _Header(context.t('shifts.mine.waitlist')),
        if (failed)
          _Widget(_Note(text: context.t('shifts.mine.waitlistFailed'))),
        for (final row in waiting) ...[_Waiting(row), const _Gap(10)],
        const _Gap(18),
      ],
    );
  }
}

/// The caller's own rows by day, the empty state when there are none, and
/// the spinner while a page is on its way.
class _MineRows extends StatelessWidget {
  const _MineRows({required this.rows, this.emptyOnly = false});

  final _Rows rows;

  /// Only the empty state, which stands above the waiting lists.
  final bool emptyOnly;

  @override
  Widget build(BuildContext context) {
    final items = context.select<MyShiftsCubit, List<MyShift>>(
      (c) => c.state.items,
    );
    final loadingMore = context.select<MyShiftsCubit, bool>(
      (c) => c.state.isLoadingMore,
    );
    final nextId = context.select<NextShiftCubit, String?>(
      (c) => c.state.next?.assignmentId,
    );
    if (emptyOnly) {
      return _EntrySliver(
        rows: rows,
        entries: rows.empty(context, items, nextId),
      );
    }
    return _EntrySliver(
      rows: rows,
      entries: [
        ...rows.mine(context, items, nextId),
        if (loadingMore)
          const _Widget(
            Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: HiveLoader(size: 26)),
            ),
          ),
      ],
    );
  }
}

/// The open shifts in the caller's projects.
class _OpenRows extends StatelessWidget {
  const _OpenRows({required this.rows});

  final _Rows rows;

  @override
  Widget build(BuildContext context) {
    final loaded = context.select<NextShiftCubit, bool>((c) => c.state.loaded);
    final open = context.select<NextShiftCubit, ShiftCalendar>(
      (c) => c.state.open,
    );
    if (!loaded) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return _EntrySliver(
      rows: rows,
      entries: [
        _Header(
          context.t('shifts.mine.open'),
          trailing: open.shifts.isEmpty
              ? null
              : context.t('shifts.mine.openCount', count: open.shifts.length),
        ),
        if (open.shifts.isEmpty)
          _Widget(_Note(text: context.t('shifts.mine.openEmpty'))),
        for (final shift in open.shifts) ...[
          _Open(shift, open.events[shift.eventId]),
          const _Gap(10),
        ],
        _Widget(
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => context.go(ShiftsView.events.route),
              icon: const Icon(LucideIcons.arrowRight, size: 16),
              label: Text(context.t('shifts.mine.toEvents')),
            ),
          ),
        ),
      ],
    );
  }
}

/// Offline: what the snapshot kept, said to be the last state loaded.
class _OfflineRows extends StatelessWidget {
  const _OfflineRows({required this.rows});

  final _Rows rows;

  @override
  Widget build(BuildContext context) {
    final snapshot = context.watch<MyShiftsSnapshotCubit>().state;
    return _EntrySliver(
      rows: rows,
      entries: [
        _Widget(_Note(text: context.t('shifts.mine.offline'))),
        ...rows.empty(context, snapshot.rows, snapshot.next?.assignmentId),
        ...rows.mine(context, snapshot.rows, snapshot.next?.assignmentId),
      ],
    );
  }
}

/// How the page draws its rows; shared by the slivers.
class _Rows {
  const _Rows({
    required this.now,
    required this.compact,
    required this.offline,
  });

  final DateTime Function() now;
  final bool compact;
  final bool offline;

  Widget hero(BuildContext context, MyShift next, ShiftDetail? detail) =>
      NextShiftHero(
        next: next,
        now: now(),
        detail: offline ? null : detail,
        selfId: context.select<AuthBloc, String?>((b) => b.state.user?.id),
        offline: offline,
        large: !compact,
        onOpen: offline ? null : () => _openSheet(context, next, null),
        onAction: (action) => _act(context, action, next),
      );

  /// The empty state, when there is neither a next shift nor a row.
  List<_Entry> empty(BuildContext context, List<MyShift> rows, String? nextId) {
    if (nextId != null || rows.any((r) => r.assignmentId != nextId)) {
      return const [];
    }
    return [
      _Widget(
        HiveEmptyState(
          title: context.t('shifts.empty.title'),
          message: context.t('shifts.empty.message'),
          action: GhostButton(
            label: context.t('shifts.mine.toEvents'),
            icon: LucideIcons.partyPopper,
            onPressed: () => context.go(ShiftsView.events.route),
          ),
        ),
      ),
    ];
  }

  /// The own rows by day, without the hero's.
  List<_Entry> mine(BuildContext context, List<MyShift> rows, String? nextId) {
    final listed = [
      for (final row in rows)
        if (row.assignmentId != nextId) row,
    ];
    final out = <_Entry>[];
    DateTime? day;
    for (final row in listed) {
      final start = row.shift.startsLocal;
      final d = DateTime(start.year, start.month, start.day);
      if (day != d) {
        if (day != null) out.add(const _Gap(14));
        out.add(_Header(dayLabel(context, d)));
        day = d;
      }
      out
        ..add(_Mine(row))
        ..add(const _Gap(10));
    }
    if (listed.isNotEmpty) out.add(const _Gap(18));
    return out;
  }

  Widget entry(BuildContext context, _Entry entry) {
    switch (entry) {
      case _Header(:final text, :final trailing):
        return ShiftSectionLabel(text, trailing: trailing);
      case _Gap(:final height):
        return SizedBox(height: height);
      case _Widget(:final child):
        return child;
      case _Waiting(:final shift):
        final mine = shift.shift.copyWith(
          myWaitAssignmentId: shift.assignmentId,
        );
        return Builder(
          builder: (rowContext) => ShiftRow(
            shift: mine,
            eventTitle: shift.event.title,
            location: shift.event.location,
            stacked: compact,
            onTap: () => unawaited(
              showShiftSheet(
                context,
                shiftId: mine.id,
                anchorRect: anchorRectOfContext(rowContext),
                onOpenEvent: () =>
                    context.push('${ShiftsView.events.route}/${mine.eventId}'),
              ),
            ),
            trailing: ShiftOfferView(
              offer: shiftOfferFor(mine),
              shift: mine,
              onAction: (action) {
                final next = context.read<NextShiftCubit>();
                startShiftAction(
                  context,
                  action,
                  shift: mine,
                  assignmentId: shift.assignmentId,
                  then: (outcome) {
                    if (outcome.ok) next.dropWaiting(shift.assignmentId);
                  },
                );
              },
            ),
          ),
        );
      case _Mine(:final shift):
        return Builder(
          builder: (rowContext) => ShiftRow(
            shift: shift.shift,
            eventTitle: shift.event.title,
            location: shift.event.location,
            stacked: compact,
            note: !offline && shift.promoted && shift.confirmByLocal != null
                ? confirmByLabel(context, shift.confirmByLocal!, now: now())
                : null,
            onTap: offline
                ? null
                : () => _openSheet(
                    context,
                    shift,
                    anchorRectOfContext(rowContext),
                  ),
            trailing: offline ? null : _mineAction(context, shift),
          ),
        );
      case _Open(:final shift, :final event):
        final offer = shiftOfferFor(
          shift,
          selfAssignable: event?.selfAssignable ?? true,
          eventCancelled: event?.cancelled ?? false,
        );
        return Builder(
          builder: (rowContext) => ShiftRow(
            shift: shift,
            eventTitle: event?.title,
            location: event?.location,
            stacked: compact,
            onTap: () => unawaited(
              showShiftSheet(
                context,
                shiftId: shift.id,
                anchorRect: anchorRectOfContext(rowContext),
                onOpenEvent: () =>
                    context.push('${ShiftsView.events.route}/${shift.eventId}'),
              ),
            ),
            trailing: ShiftOfferView(
              offer: offer,
              shift: shift,
              showSecondary: false,
              onAction: (action) => startShiftAction(
                context,
                action,
                shift: shift,
                then: (outcome) {
                  final after = outcome.shift;
                  if (outcome.ok && after != null && context.mounted) {
                    context.read<NextShiftCubit>().applyShift(after);
                  }
                },
              ),
            ),
          ),
        );
    }
  }

  /// The row's one thing: confirm while it waits for an answer, otherwise
  /// the status as a badge (the row opens the sheet with the rest).
  Widget _mineAction(BuildContext context, MyShift mine) {
    if (mine.status == ShiftAssignmentStatus.assigned) {
      return ShiftActionButton(
        action: ShiftAction.confirm,
        shiftId: mine.shift.id,
        onPressed: () => _act(context, ShiftAction.confirm, mine),
      );
    }
    return ShiftStatusBadge(status: mine.status);
  }

  void _act(BuildContext context, ShiftAction action, MyShift mine) {
    final list = context.read<MyShiftsCubit>();
    startShiftAction(
      context,
      action,
      shift: mine.shift,
      assignmentId: mine.assignmentId,
      then: (outcome) {
        if (!outcome.ok) return;
        final confirmed = outcome.myShift;
        if (confirmed != null) {
          list.replaceItem(confirmed);
        } else if (action == ShiftAction.release ||
            action == ShiftAction.decline) {
          list.removeItem(mine.assignmentId);
        }
      },
    );
  }

  void _openSheet(BuildContext context, MyShift mine, Rect? anchor) =>
      unawaited(
        showShiftSheet(
          context,
          shiftId: mine.shift.id,
          anchorRect: anchor,
          assignment: mine.ref,
          onOpenEvent: () =>
              context.push('${ShiftsView.events.route}/${mine.shift.eventId}'),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: ExcludeSemantics(
            child: Icon(LucideIcons.info, size: 15, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
          ),
        ),
      ],
    ),
  );
}

/// A list that could not be read and has nothing to fall back on.
class _Failure extends StatelessWidget {
  const _Failure({required this.errorKey, required this.onRetry});

  final String errorKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: context.pagePadding,
    children: [
      HiveEmptyState(
        title: context.t('shifts.loadFailed'),
        message: context.t(errorKey),
        action: GhostButton(
          label: context.t('common.retry'),
          icon: LucideIcons.refreshCw,
          onPressed: onRetry,
        ),
      ),
    ],
  );
}
