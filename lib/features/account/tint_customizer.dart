import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/theme_cubit.dart';
import '../../core/blocs/tint_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/theme/hue_labels.dart';
import '../../core/theme/tint_palette.dart';
import '../../core/widgets/hue_slider.dart';
import '../../core/widgets/hive_widgets.dart' show hiveEase;
import '../../core/widgets/tint_symbol.dart';
import '../sprint/modals/glass_modal.dart';
import 'account_widgets.dart';

/// Settings → Darstellung → Anpassen (HIN-150): one row in the account that
/// opens the Customize panel, as iOS 27 opens its sheet from the home screen.
///
/// The row shows what is set (the style, the colour, light or dark) and a
/// small tile in the current tint. Changing anything happens in the panel.
class TintCustomizeRow extends StatelessWidget {
  const TintCustomizeRow({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeCubit>().state;
    return BlocBuilder<TintCubit, TintState>(
      buildWhen: (a, b) => a.preferences != b.preferences,
      builder: (context, state) {
        final prefs = state.preferences;
        final tinted = prefs.style == TintStyle.tinted;
        final summary = [
          context.t(
            tinted ? 'account.tint.styleTinted' : 'account.tint.styleDefault',
          ),
          if (tinted) hueFamilyLabel(context, prefs.hue),
          context.t(tintModeLabelKey(mode)),
        ].join(' · ');
        return Builder(
          builder: (rowContext) => SettingRow(
            label: context.t('account.tint.title'),
            description: summary,
            icon: LucideIcons.palette,
            onTap: () =>
                showTintCustomizer(context, anchorRect: _rectOf(rowContext)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TintSymbol(palette: state.palette, tinted: tinted, size: 30),
                const SizedBox(width: 8),
                Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: AppColors.inkSoft,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Rect _rectOf(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    // Under the trailing end of the row, where the tile and the chevron
    // are, its right edge flush with the row's: the panel opens under what
    // was clicked.
    return Rect.fromLTWH(
      origin.dx + box.size.width - _panelWidth,
      origin.dy,
      _panelWidth,
      box.size.height,
    );
  }
}

/// The popover's width on wide screens.
const double _panelWidth = 320;

/// The key of the name of a theme mode in the panel: Light, Dark, Automatic.
String tintModeLabelKey(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'settings.themeLight',
  ThemeMode.dark => 'settings.themeDark',
  ThemeMode.system => 'account.tint.modeAuto',
};

/// Opens the Customize panel: a glass popover under [anchorRect] on wide
/// screens, a glass bottom sheet on compact ones.
Future<void> showTintCustomizer(
  BuildContext context, {
  required Rect anchorRect,
}) {
  if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
    return showGlassAnchoredPopover<void>(
      context,
      anchorRect: anchorRect,
      width: _panelWidth,
      // Low on purpose: it opens under the row whenever a useful part of it
      // fits there, and scrolls rather than jumping above what was clicked.
      minHeight: 240,
      maxHeight: 520,
      builder: (_) => const SingleChildScrollView(child: TintCustomizerPanel()),
    );
  }
  return showGlassBottomSheet<void>(
    context,
    builder: (_) =>
        const SingleChildScrollView(child: TintCustomizerPanel(sheet: true)),
  );
}

/// What the panel holds, after iOS 27's Customize sheet: the title, the
/// style tiles with their names under them, the colour and tint sliders
/// while the tinted style is on, and Light / Dark / Automatic.
///
/// Rebuilds on the tint's preferences only, never on a drag: while a slider
/// moves, the tinted tile and the sliders follow the cubit's preview inside
/// their own repaint boundaries.
class TintCustomizerPanel extends StatelessWidget {
  const TintCustomizerPanel({super.key, this.sheet = false});

  /// In a bottom sheet the helper draws the handle; the title sits closer.
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeCubit>().state;
    return BlocSelector<TintCubit, TintState, TintPreferences>(
      selector: (state) => state.preferences,
      builder: (context, prefs) =>
          _PanelBody(preferences: prefs, mode: mode, sheet: sheet),
    );
  }
}

class _PanelBody extends StatelessWidget {
  const _PanelBody({
    required this.preferences,
    required this.mode,
    required this.sheet,
  });

  final TintPreferences preferences;
  final ThemeMode mode;
  final bool sheet;

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
    final cubit = context.read<TintCubit>();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, sheet ? 2 : 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              context.t('account.tint.title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.title,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _StyleTiles(
            selected: prefs.style,
            preview: cubit.previewPalette,
            onChanged: (style) => _save(context, prefs.copyWith(style: style)),
          ),
          AnimatedSize(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: hiveEase,
            alignment: Alignment.topCenter,
            child: tinted
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _Sliders(
                      // A new committed value (another device) starts the
                      // drag from it.
                      key: ValueKey(prefs),
                      committed: prefs,
                      onPreview: cubit.preview,
                      onEnd: (next, {required pointer}) =>
                          _save(context, next, collect: !pointer),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 12),
          _ModeChoices(
            mode: mode,
            onChanged: context.read<ThemeCubit>().setMode,
          ),
        ],
      ),
    );
  }
}

class _StyleTiles extends StatelessWidget {
  const _StyleTiles({
    required this.selected,
    required this.preview,
    required this.onChanged,
  });

  final TintStyle selected;
  final ValueListenable<TintPalette> preview;
  final ValueChanged<TintStyle> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Flexible(
        child: _StyleTile(
          label: context.t('account.tint.styleDefault'),
          selected: selected == TintStyle.defaultStyle,
          onTap: () => onChanged(TintStyle.defaultStyle),
          symbol: TintSymbol(palette: TintPalette.standard, size: 60),
        ),
      ),
      const SizedBox(width: 28),
      Flexible(
        child: _StyleTile(
          label: context.t('account.tint.styleTinted'),
          selected: selected == TintStyle.tinted,
          onTap: () => onChanged(TintStyle.tinted),
          // Follows a drag frame by frame, inside its own boundary.
          symbol: RepaintBoundary(
            child: ValueListenableBuilder<TintPalette>(
              valueListenable: preview,
              builder: (_, palette, _) =>
                  TintSymbol(palette: palette, tinted: true, size: 60),
            ),
          ),
        ),
      ),
    ],
  );
}

/// A tile: the symbol and its name under it; the name sits on a glass
/// capsule while chosen. The whole tile is the button.
class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.symbol,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget symbol;

  @override
  Widget build(BuildContext context) => GlassChoice(
    label: label,
    selected: selected,
    onTap: onTap,
    builder: (context, capsule) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        symbol,
        const SizedBox(height: 6),
        capsule(
          Text(
            label,
            textAlign: TextAlign.center,
            style: _choiceStyle(selected, AppType.label),
          ),
        ),
      ],
    ),
  );
}

/// Light / Dark / Automatic: three names, the chosen one on a capsule.
class _ModeChoices extends StatelessWidget {
  const _ModeChoices({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final m in const [ThemeMode.light, ThemeMode.dark, ThemeMode.system])
        GlassChoice(
          label: context.t(tintModeLabelKey(m)),
          selected: mode == m,
          onTap: () => onChanged(m),
          builder: (context, capsule) => capsule(
            Text(
              context.t(tintModeLabelKey(m)),
              style: _choiceStyle(mode == m, AppType.label),
            ),
          ),
        ),
    ],
  );
}

TextStyle _choiceStyle(bool selected, double size) => TextStyle(
  fontSize: size,
  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
  color: selected ? AppColors.ink : AppColors.inkSoft,
);

/// Wraps a choice's name in the panel's capsule: a clear wash of the ink
/// while chosen, a fainter one while hovered, the focus ring around it.
typedef CapsuleBuilder = Widget Function(Widget child);

/// One choice in the panel, the way iOS 27 marks it: no box, no check, a
/// capsule behind the name. Button and selected state for a reader, Tab and
/// Space for a keyboard, a hand and a wash for a mouse.
class GlassChoice extends StatefulWidget {
  const GlassChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.builder,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget Function(BuildContext context, CapsuleBuilder capsule) builder;

  @override
  State<GlassChoice> createState() => _GlassChoiceState();
}

class _GlassChoiceState extends State<GlassChoice> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final selected = widget.selected;
    final wash = AppColors.ink.withValues(alpha: 0.11);
    // Every state is the same ink at another alpha: a fade between them
    // never passes through grey (Colors.transparent is transparent black).
    final fill = selected
        ? wash
        : _hovered
        ? wash.withValues(alpha: 0.05)
        : wash.withValues(alpha: 0);
    Widget capsule(Widget child) => AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 160),
      constraints: const BoxConstraints(minHeight: 30, minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShapeDecoration(
        color: fill,
        // A capsule on one line; a name that wraps at large text keeps
        // rounded corners instead of a lozenge.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(
            color: _focused ? AppColors.focusRing : fill.withValues(alpha: 0),
            width: 2,
          ),
        ),
      ),
      child: child,
    );
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        label: widget.label,
        onTap: widget.onTap,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: widget.builder(context, capsule),
            ),
          ),
        ),
      ),
    );
  }
}

/// The two sliders. They hold what is being dragged themselves, so a step
/// rebuilds this widget and nothing around it.
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
    // No captions, as on iOS: each slider carries its name for a reader and
    // the colour's name is in its spoken value.
    return Column(
      children: [
        RepaintBoundary(
          child: HueSlider(
            hue: dragging.hue,
            level: dragging.level,
            onChanged: (hue) => _preview(dragging.copyWith(hue: hue)),
            onChangeEnd: (hue, {required pointer}) =>
                widget.onEnd(dragging.copyWith(hue: hue), pointer: pointer),
          ),
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
