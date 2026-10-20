import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/models/shift_plan_export.dart';
import '../../../core/repositories/shift_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/util/file_download.dart';
import '../../../core/util/share_origin.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../../sprint/modals/glass_modal.dart';
import '../bloc/shift_plan_export_cubit.dart';

/// The label of each format in the segment.
String shiftPlanFormatLabelKey(ShiftPlanFormat format) =>
    'shifts.export.format.${format.name}';

/// "Schichtplan exportieren" (HIN-163): asks for the format and, for a
/// planner, whether the file names people, then takes the plan out the way a
/// time report goes: a download on the web, the share sheet on a phone and on
/// macOS. Says that it is working, what came of it, and why not.
///
/// [anchor] is the control that was pressed, for the share popover on iPad.
Future<void> exportShiftPlan(
  BuildContext context,
  ShiftEventSummary event, {
  Rect? anchor,
}) async {
  final cubit = ShiftPlanExportCubit(context.read<ShiftRepository>(), event);
  try {
    final go = await showGlassModal<bool>(
      context,
      adaptive: false,
      width: 440,
      builder: (_) =>
          BlocProvider.value(value: cubit, child: const ShiftPlanExportBody()),
    );
    if (go != true || !context.mounted) return;
    await _deliver(context, cubit, anchor);
  } finally {
    await cubit.close();
  }
}

Future<void> _deliver(
  BuildContext context,
  ShiftPlanExportCubit cubit,
  Rect? anchor,
) async {
  final origin = shareOriginOf(context, preferred: anchor);
  final format = cubit.state.format;
  final fallbackName = cubit.fileName(context.t('shifts.export.fileName'));
  final progress = showGlassToast(
    context,
    context.t('shifts.export.preparing'),
    duration: const Duration(minutes: 5),
  );
  var truncated = false;
  try {
    final DownloadResult result;
    if (kIsWeb) {
      final file = await cubit.fetch();
      if (file == null) {
        progress.close();
        return;
      }
      truncated = file.truncated;
      progress.close();
      result = await downloadBytes(
        file.fileName ?? fallbackName,
        file.bytes,
        format.mimeType,
        sharePositionOrigin: origin,
      );
    } else {
      // Straight to disk, named before the answer arrives: by the server's own
      // rule, so the file is called what the header would have said.
      result = await downloadFile(fallbackName, format.mimeType, (path) async {
        truncated = await cubit.fetchTo(path) ?? false;
        progress.close();
      }, sharePositionOrigin: origin);
    }
    if (!context.mounted) return;
    if (result.outcome == DownloadOutcome.dismissed) {
      progress.close();
      return;
    }
    final failed = result.outcome == DownloadOutcome.failed;
    showGlassToast(
      context,
      context.t(
        failed
            ? 'shifts.export.failed'
            : truncated
            ? 'shifts.export.truncated'
            : 'shifts.export.done',
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
  } catch (_) {
    if (!context.mounted) return;
    showGlassToast(
      context,
      context.t('shifts.export.failed'),
      kind: GlassToastKind.error,
    );
  }
}

/// The dialog's content, on its own for tests: the format as a segment, the
/// names switch for a planner, and one primary action.
class ShiftPlanExportBody extends StatelessWidget {
  const ShiftPlanExportBody({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ShiftPlanExportCubit>();
    final state = context.watch<ShiftPlanExportCubit>().state;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: context.t('shifts.export.title')),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // In the scroll, not the head: at large text on a phone the
                // sentence takes several lines and must not be cut.
                Text(
                  context.t('shifts.export.subtitle'),
                  style: TextStyle(
                    fontSize: AppType.label,
                    height: 1.45,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('shifts.export.formatLabel'),
                  child: _FormatSegment(
                    selected: state.format,
                    onChanged: state.running ? null : cubit.selectFormat,
                  ),
                ),
                if (cubit.mayName) ...[
                  const SizedBox(height: 10),
                  _NamesSwitch(
                    value: state.names,
                    onChanged: state.running ? null : cubit.setNames,
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('shifts.export.action'),
          confirmIcon: LucideIcons.download,
          busy: state.running,
          onConfirm: state.running
              ? null
              : () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// PDF, Word, Tabelle side by side; one above the other once the words no
/// longer fit a third of the width (a phone at large text), so a label is
/// never cut or broken inside its word.
class _FormatSegment extends StatelessWidget {
  const _FormatSegment({required this.selected, required this.onChanged});

  final ShiftPlanFormat selected;
  final ValueChanged<ShiftPlanFormat>? onChanged;

  static const double _inset = 3;
  static const double _gap = 4;

  /// The selected segment's check glyph, its gap, and the padding either side.
  static const double _chrome = 14 + 6 + 2 * 12;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = TextStyle(
      fontSize: AppType.label,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    );
    final labels = {
      for (final format in ShiftPlanFormat.values)
        format: context.t(shiftPlanFormatLabelKey(format)),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        var widest = 0.0;
        for (final label in labels.values) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textScaler: scaler,
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          if (painter.width > widest) widest = painter.width;
          painter.dispose();
        }
        final count = ShiftPlanFormat.values.length;
        final share =
            (constraints.maxWidth - 2 * _inset - (count - 1) * _gap) / count;
        final across = widest + _chrome <= share;
        final segments = [
          for (final format in ShiftPlanFormat.values)
            _Segment(
              label: labels[format]!,
              selected: format == selected,
              onTap: onChanged == null ? null : () => onChanged!(format),
            ),
        ];
        return Semantics(
          container: true,
          child: Container(
            padding: const EdgeInsets.all(_inset),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl + 3),
              border: Border.all(color: AppColors.hairline),
            ),
            child: across
                ? Row(
                    children: [
                      for (var i = 0; i < segments.length; i++) ...[
                        if (i > 0) const SizedBox(width: _gap),
                        Expanded(child: segments[i]),
                      ],
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < segments.length; i++) ...[
                        if (i > 0) const SizedBox(height: _gap),
                        segments[i],
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusControl);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: onTap != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.accentSoft : Colors.transparent,
              borderRadius: radius,
              border: Border.all(
                color: selected ? AppColors.accentLine : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  ExcludeSemantics(
                    child: Icon(
                      LucideIcons.check,
                      size: 14,
                      color: AppColors.accentInk,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Mit Namen" with its sentence always in sight, never folded behind an info
/// button: what the switch does to the file is the point of asking. The whole
/// row toggles, and reads as one switch.
class _NamesSwitch extends StatelessWidget {
  const _NamesSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged(!value),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t('shifts.export.names'),
                        style: TextStyle(
                          fontSize: AppType.label,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.t('shifts.export.namesHint'),
                        style: TextStyle(
                          fontSize: AppType.caption,
                          height: 1.35,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                HiveSwitch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dialog's head. From one and a half times the text size the icon and
/// the close button give their room to the title, which would otherwise break
/// inside "Schichtplan"; "Abbrechen" in the footer still closes it.
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(10) >= 15;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, large ? 22 : 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!large) ...[
            ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  LucideIcons.fileDown,
                  size: 20,
                  color: AppColors.accentInk,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: large ? 0 : 8),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: AppType.title,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
          if (!large)
            IconButton(
              tooltip: context.t('common.cancel'),
              icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    );
  }
}
