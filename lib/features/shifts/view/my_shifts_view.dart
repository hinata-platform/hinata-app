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
      child: MyShiftsView(now: now),
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

class _Body extends StatelessWidget {
  const _Body({required this.now, required this.compact});

  final DateTime Function() now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final paged = context.watch<MyShiftsCubit>().state;
    final head = context.watch<NextShiftCubit>().state;
    final snapshot = context.watch<MyShiftsSnapshotCubit>().state;
    final selfId = context.select<AuthBloc, String?>(
      (bloc) => bloc.state.user?.id,
    );

    // Offline: the list could not be read and there is a snapshot to show.
    final failed = paged.errorKey != null && !paged.hasData;
    final offline = failed && !snapshot.isEmpty;
    if (!paged.hasData && !failed) {
      return const Center(child: HiveLoader());
    }
    if (failed && !offline) {
      return _Failure(
        errorKey: paged.errorKey!,
        onRetry: () {
          unawaited(context.read<MyShiftsCubit>().load());
          unawaited(context.read<NextShiftCubit>().load());
        },
      );
    }

    final next = offline ? snapshot.next : head.next;
    final rows = offline ? snapshot.rows : paged.items;
    final listed = [
      for (final row in rows)
        if (row.assignmentId != next?.assignmentId) row,
    ];
    final clock = now();
    final hero = next == null
        ? null
        : NextShiftHero(
            next: next,
            now: clock,
            detail: offline ? null : head.nextDetail,
            selfId: selfId,
            offline: offline,
            large: !compact,
            onOpen: offline ? null : () => _openSheet(context, next, null),
            onAction: (action) => _act(context, action, next),
          );

    final entries = <_Entry>[
      if (offline) _Widget(_Note(text: context.t('shifts.mine.offline'))),
      if (next == null && listed.isEmpty)
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
      if (!offline) ..._waiting(context, head),
      ..._byDay(context, listed),
      if (!offline) ..._open(context, head),
    ];

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
              sliver: SliverList.builder(
                itemCount:
                    entries.length +
                    (compact && hero != null ? 2 : 0) +
                    (paged.isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  var i = index;
                  if (compact && hero != null) {
                    if (i == 0) return hero;
                    if (i == 1) return const SizedBox(height: 28);
                    i -= 2;
                  }
                  if (i >= entries.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: HiveLoader(size: 26)),
                    );
                  }
                  return _entry(context, entries[i], offline);
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (compact || hero == null) return list;
    // Wide: the list beside the hero, 62 to 38.
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
            child: hero,
          ),
        ),
      ],
    );
  }

  /// The compact group above the list: the shifts the caller waits for.
  List<_Entry> _waiting(BuildContext context, NextShiftState head) {
    final waiting = head.waiting;
    if (waiting.isEmpty) return const [];
    return [
      _Header(context.t('shifts.mine.waitlist')),
      for (final row in waiting) ...[_Waiting(row), const _Gap(10)],
      const _Gap(18),
    ];
  }

  List<_Entry> _byDay(BuildContext context, List<MyShift> rows) {
    final out = <_Entry>[];
    DateTime? day;
    for (final row in rows) {
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
    if (rows.isNotEmpty) out.add(const _Gap(18));
    return out;
  }

  List<_Entry> _open(BuildContext context, NextShiftState head) {
    if (!head.loaded) return const [];
    final open = head.open.shifts;
    return [
      _Header(
        context.t('shifts.mine.open'),
        trailing: open.isEmpty
            ? null
            : context.t('shifts.mine.openCount', count: open.length),
      ),
      if (open.isEmpty)
        _Widget(_Note(text: context.t('shifts.mine.openEmpty'))),
      for (final shift in open) ...[
        _Open(shift, head.open.events[shift.eventId]),
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
    ];
  }

  Widget _entry(BuildContext context, _Entry entry, bool offline) {
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
