import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/theme_cubit.dart';
import '../../core/blocs/tint_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/theme/hue_labels.dart';
import '../../core/theme/tint_palette.dart';
import '../../core/widgets/folded_hint.dart';
import '../../core/widgets/hue_slider.dart';
import '../sprint/modals/glass_modal.dart';
import 'account_widgets.dart';

/// Settings → Darstellung → Anpassen (HIN-150), laid out like iOS 27's sheet:
/// two style tiles with a preview of the app in each, the colour and tint
/// sliders when the tinted style is on, the Light / Dark / System pills, and
/// a reset.
///
/// Rebuilds on the tint's preferences only (`BlocSelector`), never on a
/// drag: while a slider moves, the tinted tile and the sliders' tracks follow
/// the cubit's preview notifier inside their own repaint boundaries, and the
/// rest of the account screen behind them stays still.
class TintSection extends StatelessWidget {
  const TintSection({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeCubit>().state;
    return BlocSelector<TintCubit, TintState, TintPreferences>(
      selector: (state) => state.preferences,
      builder: (context, prefs) => _TintBody(preferences: prefs, mode: mode),
    );
  }
}

class _TintBody extends StatelessWidget {
  const _TintBody({required this.preferences, required this.mode});

  final TintPreferences preferences;
  final ThemeMode mode;

  Future<void> _save(
    BuildContext context,
    TintPreferences next, {
    bool collect = false,
  }) async {
    final ok = await context.read<TintCubit>().commit(next, collect: collect);
    if (!ok && context.mounted) {
      showGlassToast(
        context,
        context.t('account.tint.saveFailed'),
        kind: GlassToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = preferences;
    final tinted = prefs.style == TintStyle.tinted;
    final compact = context.isCompact;
    final cubit = context.read<TintCubit>();
    final tiles = _StyleTiles(
      preferences: prefs,
      previewPalette: cubit.previewPalette,
      onChanged: (style) => _save(context, prefs.copyWith(style: style)),
    );
    final sliders = tinted
        ? _Sliders(
            // A new committed value (another device, a reset) starts the
            // drag from it.
            key: ValueKey(prefs),
            committed: prefs,
            onPreview: cubit.preview,
            onEnd: (next, {required pointer}) =>
                _save(context, next, collect: !pointer),
          )
        : null;
    final modes = TileSelector<ThemeMode>(
      value: mode,
      onChanged: context.read<ThemeCubit>().setMode,
      options: [
        TileOption(
          value: ThemeMode.light,
          label: context.t('settings.themeLight'),
          icon: LucideIcons.sun,
        ),
        TileOption(
          value: ThemeMode.dark,
          label: context.t('settings.themeDark'),
          icon: LucideIcons.moon,
        ),
        TileOption(
          value: ThemeMode.system,
          label: context.t('settings.themeSystem'),
          icon: LucideIcons.monitor,
        ),
      ],
    );
    final reset = Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: prefs == TintPreferences.standard
            ? null
            : () => _save(context, TintPreferences.standard),
        icon: const Icon(LucideIcons.rotateCcw, size: 16),
        label: Text(context.t('account.tint.reset')),
      ),
    );
    final title = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TitledHint(
        title: context.t('account.tint.title'),
        titleStyle: TextStyle(
          fontSize: AppType.label,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        hint: context.t('account.tint.subtitle'),
        hintStyle: TextStyle(
          fontSize: AppType.caption,
          height: 1.35,
          color: AppColors.inkSoft,
        ),
      ),
    );
    if (compact || sliders == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            tiles,
            if (sliders != null) ...[const SizedBox(height: 16), sliders],
            const SizedBox(height: 16),
            modes,
            const SizedBox(height: 4),
            reset,
          ],
        ),
      );
    }
    // Wide: tiles on the left, the sliders beside them, as the sheet reads on
    // a tablet.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bounded, so two long names wrap inside their tiles instead
              // of pushing the sliders off the row.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: tiles,
              ),
              const SizedBox(width: 24),
              Expanded(child: sliders),
            ],
          ),
          const SizedBox(height: 16),
          modes,
          const SizedBox(height: 4),
          reset,
        ],
      ),
    );
  }
}

class _StyleTiles extends StatelessWidget {
  const _StyleTiles({
    required this.preferences,
    required this.previewPalette,
    required this.onChanged,
  });

  final TintPreferences preferences;
  final ValueListenable<TintPalette> previewPalette;
  final ValueChanged<TintStyle> onChanged;

  @override
  Widget build(BuildContext context) => TileSelector<TintStyle>(
    value: preferences.style,
    layout: TileSelectorLayout.tile,
    onChanged: onChanged,
    options: [
      TileOption(
        value: TintStyle.defaultStyle,
        label: context.t('account.tint.styleDefault'),
        preview: TintMiniPreview.standard(),
      ),
      TileOption(
        value: TintStyle.tinted,
        label: context.t('account.tint.styleTinted'),
        preview: TintMiniPreview.live(previewPalette),
      ),
    ],
  );
}

/// The app in miniature: a strip of rail, a tab pill on glass-coloured
/// paper and a primary button, in one palette. Decorative; the tile's name
/// says what it is.
class TintMiniPreview extends StatelessWidget {
  TintMiniPreview.standard({super.key})
    : palette = TintPalette.standard,
      live = null;

  const TintMiniPreview.live(this.live, {super.key}) : palette = null;

  final TintPalette? palette;
  final ValueListenable<TintPalette>? live;

  @override
  Widget build(BuildContext context) {
    final fixed = palette;
    if (fixed != null) return _paint(context, fixed);
    return RepaintBoundary(
      child: ValueListenableBuilder<TintPalette>(
        valueListenable: live!,
        builder: (context, p, _) => _paint(context, p),
      ),
    );
  }

  Widget _paint(BuildContext context, TintPalette p) {
    final dark = AppColors.brightness == Brightness.dark;
    final paper = dark ? AppColors.canvasDark : AppColors.canvasLight;
    final chrome = Color.alphaBlend(
      dark ? p.chromeTintDark : p.chromeTintLight,
      dark ? AppColors.surfaceDark : AppColors.surfaceLight,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: paper,
        child: Row(
          children: [
            Container(width: 14, color: p.rail),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 8,
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: chrome,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == 0
                                    ? (dark ? p.accent : p.accentText)
                                    : AppColors.inkFaint,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The two sliders. They hold what is being dragged themselves, so a step
/// rebuilds this widget and nothing around it: the tiles, the pills and the
/// reset button above and below stay as they are.
class _Sliders extends StatefulWidget {
  const _Sliders({
    super.key,
    required this.committed,
    required this.onPreview,
    required this.onEnd,
  });

  /// What the account holds; a new value resets the drag (see the key).
  final TintPreferences committed;
  final ValueChanged<TintPreferences> onPreview;
  final void Function(TintPreferences, {required bool pointer}) onEnd;

  @override
  State<_Sliders> createState() => _SlidersState();
}

class _SlidersState extends State<_Sliders> {
  late TintPreferences _dragging = widget.committed;

  void _preview(TintPreferences next) {
    if (next.hue != _dragging.hue) tintSnapHaptic(_dragging.hue, next.hue);
    setState(() => _dragging = next);
    widget.onPreview(next);
  }

  @override
  Widget build(BuildContext context) {
    final dragging = _dragging;
    final labelStyle = TextStyle(
      fontSize: AppType.caption,
      fontWeight: FontWeight.w600,
      color: AppColors.inkSoft,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Captions are decoration for a reader: each slider carries its own
        // name, and the colour's name is in its spoken value.
        ExcludeSemantics(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  context.t('account.tint.hue'),
                  style: labelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TintPalette.of(dragging).accent,
                  border: Border.all(color: AppColors.hairline),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  hueFamilyLabel(context, dragging.hue),
                  style: labelStyle.copyWith(color: AppColors.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        RepaintBoundary(
          child: HueSlider(
            hue: dragging.hue,
            level: dragging.level,
            onChanged: (hue) => _preview(dragging.copyWith(hue: hue)),
            onChangeEnd: (hue, {required pointer}) =>
                widget.onEnd(dragging.copyWith(hue: hue), pointer: pointer),
          ),
        ),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: Text(context.t('account.tint.level'), style: labelStyle),
        ),
        RepaintBoundary(
          child: LevelSlider(
            hue: dragging.hue,
            level: dragging.level,
            onChanged: (level) => _preview(dragging.copyWith(level: level)),
            onChangeEnd: (level, {required pointer}) =>
                widget.onEnd(dragging.copyWith(level: level), pointer: pointer),
          ),
        ),
      ],
    );
  }
}
