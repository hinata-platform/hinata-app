import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/util/file_download.dart';
import '../../../core/widgets/glass_switch_chip.dart';
import '../../sprint/modals/glass_modal.dart'
    show showGlassToast, GlassToastKind;

class FiguresState extends Equatable {
  const FiguresState({this.years = const [], this.year, this.busy = false});

  /// The years with figures, newest first; this one always among them.
  final List<int> years;
  final int? year;
  final bool busy;

  FiguresState copyWith({List<int>? years, int? year, bool? busy}) =>
      FiguresState(
        years: years ?? this.years,
        year: year ?? this.year,
        busy: busy ?? this.busy,
      );

  @override
  List<Object?> get props => [years, year, busy];
}

/// The yearly figures of moderation in the admin area (HIN-178): which years
/// there are, the one chosen, and the file of it.
class FiguresCubit extends Cubit<FiguresState> {
  FiguresCubit(this._admin, {DateTime Function() now = DateTime.now})
    : _now = now,
      super(const FiguresState());

  final AdminRepository _admin;
  final DateTime Function() _now;

  Future<void> load() async {
    final current = _now().year;
    var years = <int>[current];
    try {
      years = await _admin.moderationFigureYears();
      if (!years.contains(current)) years = [current, ...years];
    } catch (_) {
      // This year is always there to ask for.
    }
    if (isClosed) return;
    emit(state.copyWith(years: years, year: state.year ?? years.first));
  }

  void choose(int year) => emit(state.copyWith(year: year));

  /// The file of the year chosen; null while another is on its way.
  Future<Uint8List?> download() async {
    final year = state.year;
    if (year == null || state.busy) return null;
    emit(state.copyWith(busy: true));
    try {
      return await _admin.moderationFigures(year);
    } finally {
      if (!isClosed) emit(state.copyWith(busy: false));
    }
  }
}

/// The yearly figures in the card "Aufbewahrung und Zahlen": the year, as wide
/// as its choices, and the file in the Commission's template.
class FiguresDownload extends StatelessWidget {
  const FiguresDownload({super.key});

  Future<void> _download(BuildContext context, Rect? origin) async {
    final cubit = context.read<FiguresCubit>();
    final year = cubit.state.year;
    try {
      final bytes = await cubit.download();
      if (bytes == null || year == null || !context.mounted) return;
      final result = await downloadBytes(
        'transparency-report-$year.zip',
        bytes,
        'application/zip',
        sharePositionOrigin: origin,
      );
      if (!context.mounted || result.outcome == DownloadOutcome.dismissed) {
        return;
      }
      final failed = result.outcome == DownloadOutcome.failed;
      showGlassToast(
        context,
        context.t(
          failed
              ? 'admin.moderation.figuresFailed'
              : 'admin.moderation.figuresDone',
        ),
        kind: failed ? GlassToastKind.error : GlassToastKind.success,
      );
    } on ApiFailure catch (failure) {
      if (!context.mounted) return;
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<FiguresCubit, FiguresState>(
    builder: (context, state) {
      final year = state.year;
      if (year == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.years.length > 1) ...[
            InlineSwitchBar(
              chips: [
                for (final option in state.years)
                  GlassSwitchChip(
                    label: '$option',
                    active: option == year,
                    onTap: () => context.read<FiguresCubit>().choose(option),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Builder(
              builder: (anchor) => OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => unawaited(_download(context, _rectOf(anchor))),
                icon: state.busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.download, size: 16),
                label: Text(
                  context.t(
                    'admin.moderation.figures',
                    variables: {'year': '$year'},
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('admin.moderation.figuresHint'),
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.4,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      );
    },
  );

  static Rect? _rectOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}
