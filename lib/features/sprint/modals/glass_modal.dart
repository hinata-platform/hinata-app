import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../search/search_tokens.dart';

/// Phone breakpoint for the sprint modals (matches the app's φ-stepped phone bp
/// used by the search palette).
const double _kPhoneBreakpoint = 610;

/// Opens a Liquid-Glass sprint modal over a dimmed, blurred app — the shared
/// material for Create / Start / Complete / Estimate (mirrors `sprint.css`
/// "LIQUID-GLASS SPRINT MODALS": radius 26, blurred scrim, spring entrance).
///
/// Honours `prefers-reduced-motion`: cross-fade only, no spring/blur ramp.
Future<T?> showGlassModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 540,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, _, _) =>
        _GlassModalScaffold(width: width, builder: builder),
    transitionBuilder: (_, _, _, child) => child,
  );
}

/// A Liquid-Glass confirmation dialog — the shared replacement for Material's
/// [AlertDialog]. Renders an amber (or danger-tinted) icon tile, a title and a
/// message on the app's glass material, with Cancel / confirm actions.
///
/// Resolves to `true` when confirmed, `false`/`null` when dismissed.
Future<bool?> showGlassConfirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  IconData confirmIcon = LucideIcons.check,
}) {
  return showGlassModal<bool>(
    context,
    width: 420,
    builder: (modalContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassConfirmHeader(icon: icon, title: title, destructive: destructive),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: confirmLabel,
          confirmIcon: confirmIcon,
          confirmColor: destructive ? AppColors.danger : null,
          onConfirm: () => Navigator.of(modalContext).pop(true),
        ),
      ],
    ),
  );
}

/// Header for [showGlassConfirm]: icon tile + title + close button (no
/// subtitle line, unlike [GlassModalHeader]).
class _GlassConfirmHeader extends StatelessWidget {
  const _GlassConfirmHeader({
    required this.icon,
    required this.title,
    required this.destructive,
  });

  final IconData icon;
  final String title;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tileBg = destructive
        ? AppColors.danger.withValues(alpha: 0.14)
        : AppColors.accentSoft;
    final glyph = destructive ? AppColors.danger : AppColors.accentStrong;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: glyph),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
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

/// Opens a Liquid-Glass bottom sheet — the shared replacement for Material's
/// [showModalBottomSheet]. Renders [builder]'s content on the app's signature
/// glass panel (transparent transport, blurred glassFill, grab handle), riding
/// above the on-screen keyboard. Mirrors the action sheet in
/// `upload_source_sheet.dart`.
///
/// The [builder] should return its own content directly (a `Column`/list); the
/// helper supplies the surface, the grab handle, side insets and `SafeArea`, so
/// content must NOT add its own — see [showUploadSourceSheet] for the original.
Future<T?> showGlassBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool showHandle = true,
  double radius = 24,
  double maxWidth = 560,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (sheetContext) => _GlassBottomSheet(
      radius: radius,
      showHandle: showHandle,
      maxWidth: maxWidth,
      builder: builder,
    ),
  );
}

class _GlassBottomSheet extends StatelessWidget {
  const _GlassBottomSheet({
    required this.radius,
    required this.showHandle,
    required this.maxWidth,
    required this.builder,
  });

  final double radius;
  final bool showHandle;
  final double maxWidth;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Ride above the keyboard: subscribing rebuilds the sheet as it animates.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final size = MediaQuery.sizeOf(context);
    // Never grow past the space above the keyboard; the body scrolls within.
    final maxH = (size.height - 80 - keyboard).clamp(160.0, size.height);

    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxH),
      child: GlassPanelShadow(
        radius: BorderRadius.circular(radius),
        shadows: tokens.panelShadow,
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          clipBehavior: Clip.antiAlias,
          shape: LiquidRoundedSuperellipse(borderRadius: radius),
          settings: liquidGlassPanelSettings(
            glassFill: tokens.glassFill,
            dark: dark,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showHandle) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
                Flexible(child: builder(context)),
              ],
            ),
          ),
        ),
      ),
    );

    // With `isScrollControlled`, the bottom-sheet body stretches to the full
    // screen height, so the `Align` leaves a tall transparent gap above the
    // panel that belongs to the sheet — not the modal barrier. Without an
    // explicit handler, taps in that gap (or the side gutters) fall on the
    // sheet and do nothing instead of dismissing. Catch them here; the panel
    // wraps its own taps so its content stays interactive.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + keyboard),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(onTap: () {}, child: panel),
          ),
        ),
      ),
    );
  }
}

/// Width at/above which option pickers anchor as a dropdown popover instead of
/// sliding up as a bottom sheet (matches the issue sheet's dialog breakpoint).
const double _kOptionsPopoverBreakpoint = 760;

/// A single choice for [showGlassOptions]: a [value] and the [child] widget that
/// renders it (a status dot, a priority flag, a plain label…).
typedef GlassOption<T> = ({T value, Widget child});

/// Responsive single-choice picker on the glass material — the shared pattern
/// for the issue-detail field pickers (status / priority / type / sprint…).
///
/// On wide screens, when an [anchorRect] (the global rect of the tapped row) is
/// supplied, it opens as an **anchored dropdown popover** beside the field so it
/// reads as an inline editor rather than a detached sheet. On phones (or without
/// an anchor) it slides up via [showGlassBottomSheet]. Resolves to the chosen
/// value, or `null` if dismissed.
Future<T?> showGlassOptions<T>(
  BuildContext context, {
  required String title,
  required List<GlassOption<T>> options,
  Rect? anchorRect,
}) {
  final wide = MediaQuery.sizeOf(context).width >= _kOptionsPopoverBreakpoint;
  if (wide && anchorRect != null) {
    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) =>
          _AnchoredOptions<T>(anchorRect: anchorRect, options: options),
      transitionBuilder: (_, _, _, child) => child,
    );
  }
  return showGlassBottomSheet<T>(
    context,
    builder: (sheetContext) => _OptionsList<T>(title: title, options: options),
  );
}

/// Bottom-sheet body for [showGlassOptions] on phones: a title and a tap-to-pick
/// list, sized to its content.
class _OptionsList<T> extends StatelessWidget {
  const _OptionsList({required this.title, required this.options});

  final String title;
  final List<GlassOption<T>> options;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        for (final o in options)
          InkWell(
            onTap: () => Navigator.of(context).pop(o.value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Align(alignment: Alignment.centerLeft, child: o.child),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Wide-screen body for [showGlassOptions]: a glass dropdown popover anchored to
/// [anchorRect], placed below the field (flips above when space is tight) and
/// clamped on-screen — mirrors the placement logic of `GlassPopupMenu`.
class _AnchoredOptions<T> extends StatelessWidget {
  const _AnchoredOptions({required this.anchorRect, required this.options});

  final Rect anchorRect;
  final List<GlassOption<T>> options;

  static const double _margin = 12;
  static const double _radius = 20;
  static const double _gap = 6;
  static const double _width = 300;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final anim = ModalRoute.of(context)!.animation!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final panelWidth = math.min(_width, size.width - _margin * 2);
    final double left = anchorRect.left
        .clamp(_margin, math.max(_margin, size.width - panelWidth - _margin))
        .toDouble();
    final belowTop = anchorRect.bottom + _gap;
    final roomBelow = size.height - belowTop - _margin - pad.bottom;
    final roomAbove = anchorRect.top - _gap - _margin - pad.top;
    final placeAbove = roomBelow < 220 && roomAbove > roomBelow;
    final maxHeight = (placeAbove ? roomAbove : roomBelow).clamp(140.0, 460.0);
    final top = placeAbove ? null : belowTop;
    final bottom = placeAbove ? (size.height - anchorRect.top + _gap) : null;

    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: panelWidth, maxHeight: maxHeight),
      child: GlassPanelShadow(
        radius: BorderRadius.circular(_radius),
        shadows: tokens.panelShadow,
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          clipBehavior: Clip.antiAlias,
          shape: const LiquidRoundedSuperellipse(borderRadius: _radius),
          settings: liquidGlassPanelSettings(
            glassFill: tokens.glassFill,
            dark: dark,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              children: [
                for (final o in options)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(o.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: o.child,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: panelWidth,
          child: AnimatedBuilder(
            animation: anim,
            builder: (_, child) {
              if (reduceMotion) {
                return Opacity(opacity: anim.value, child: child);
              }
              final t = const Cubic(
                0.34,
                1.3,
                0.64,
                1,
              ).transform(anim.value.clamp(0.0, 1.0));
              return Opacity(
                opacity: (anim.value / 0.6).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.92 + 0.08 * t,
                  alignment: placeAbove
                      ? Alignment.bottomLeft
                      : Alignment.topLeft,
                  child: child,
                ),
              );
            },
            child: panel,
          ),
        ),
      ],
    );
  }
}

/// A Liquid-Glass date picker — the shared replacement for Material's
/// [showDatePicker]. Renders Material's [CalendarDatePicker] (robust month/year
/// logic) on the app's glass modal, themed with the navy/amber accents, with the
/// chosen day echoed in the header and a Cancel / OK footer.
///
/// Resolves to the picked [DateTime], or `null` if dismissed.
Future<DateTime?> showGlassDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required String title,
}) {
  return showGlassModal<DateTime>(
    context,
    width: 360,
    builder: (modalContext) => _GlassDatePicker(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

class _GlassDatePicker extends StatefulWidget {
  const _GlassDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  @override
  State<_GlassDatePicker> createState() => _GlassDatePickerState();
}

class _GlassDatePickerState extends State<_GlassDatePicker> {
  late DateTime _selected = widget.initialDate;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    // Theme the Material calendar to the app's surface-free, navy/amber palette
    // so it reads on the glass instead of painting its own opaque dialog.
    final themed = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.navy,
        onPrimary: Colors.white,
        surface: Colors.transparent,
        onSurface: AppColors.ink,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        todayForegroundColor: WidgetStateProperty.all(AppColors.accentStrong),
        todayBorder: const BorderSide(color: AppColors.accent),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.calendar,
          title: widget.title,
          subtitle: MaterialLocalizations.of(context).formatFullDate(_selected),
        ),
        Theme(
          data: themed,
          child: SizedBox(
            height: 340,
            child: CalendarDatePicker(
              initialDate: _selected,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              onDateChanged: (d) => setState(() => _selected = d),
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: MaterialLocalizations.of(context).okButtonLabel,
          onConfirm: () => Navigator.of(context).pop(_selected),
        ),
      ],
    );
  }
}

/// A `WoltModalSheet.pageContentDecorator` that re-skins the sheet's surface as
/// the app's liquid glass. Pair it with a transparent page `backgroundColor`
/// (and `surfaceTintColor`) so Wolt's underlying Material stops painting a solid
/// fill and this glass panel shows through instead. Wolt keeps owning layout,
/// the top bar, drag and the sticky action bar — only the surface changes.
Widget glassWoltSurface(Widget pageContent) {
  return Builder(
    builder: (context) {
      final tokens = SearchTokens.of(Theme.of(context).brightness);
      final dark = Theme.of(context).brightness == Brightness.dark;
      return GlassPanelShadow(
        radius: BorderRadius.circular(26),
        shadows: tokens.panelShadow,
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          clipBehavior: Clip.antiAlias,
          shape: const LiquidRoundedSuperellipse(borderRadius: 26),
          settings: liquidGlassPanelSettings(
            glassFill: tokens.glassFill,
            dark: dark,
          ),
          // Large editing sheets carry dense content over the busy app behind,
          // so float it on a *thick* near-opaque warm-canvas wash (iOS "thick
          // material") for legibility — the thin `glassFill` alone leaves text
          // muddy here. The glass rim, soft translucency and floating shadow
          // keep the liquid-glass identity; small popovers keep the thin fill.
          child: ColoredBox(
            color: AppColors.canvas.withValues(alpha: dark ? 0.84 : 0.88),
            child: pageContent,
          ),
        ),
      );
    },
  );
}

class _GlassModalScaffold extends StatelessWidget {
  const _GlassModalScaffold({required this.width, required this.builder});

  final double width;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // The on-screen keyboard's height. Subscribing rebuilds the modal as the
    // keyboard animates in/out so the panel rides above it and its scrollable
    // body can reveal the focused field.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final mobile = size.width < _kPhoneBreakpoint;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final anim = ModalRoute.of(context)!.animation!;
    final maxW = mobile ? size.width - 32 : width;
    // Cap the panel to the space left above the keyboard so it never hides
    // behind it; the body scrolls within whatever height remains.
    final maxH = (size.height - (mobile ? 120 : 96) - keyboard).clamp(
      160.0,
      size.height,
    );

    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
      child: GlassPanelShadow(
        radius: BorderRadius.circular(26),
        shadows: tokens.panelShadow,
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          clipBehavior: Clip.antiAlias,
          shape: LiquidRoundedSuperellipse(borderRadius: 26),
          settings: liquidGlassPanelSettings(
            glassFill: tokens.glassFill,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: builder(context),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        // Scrim: dim + blur the app behind.
        AnimatedBuilder(
          animation: anim,
          builder: (_, _) {
            final t = anim.value.clamp(0.0, 1.0);
            Widget scrim = ColoredBox(
              color: tokens.scrim.withValues(alpha: tokens.scrim.a * t),
              child: const SizedBox.expand(),
            );
            if (!reduceMotion) {
              scrim = BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 7 * t, sigmaY: 7 * t),
                child: scrim,
              );
            }
            return Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: scrim,
              ),
            );
          },
        ),
        Positioned.fill(
          child: SafeArea(
            // Shrink the centring box by the keyboard height so the panel
            // re-centres in the visible area above it instead of being clipped.
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboard),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AnimatedBuilder(
                    animation: anim,
                    builder: (_, child) {
                      if (reduceMotion) {
                        return Opacity(opacity: anim.value, child: child);
                      }
                      final curved = const Cubic(
                        0.34,
                        1.56,
                        0.64,
                        1,
                      ).transform(anim.value.clamp(0.0, 1.0));
                      final fade = (anim.value / 0.6).clamp(0.0, 1.0);
                      return Opacity(
                        opacity: fade,
                        child: Transform.translate(
                          offset: Offset(0, (1 - curved) * -14),
                          child: Transform.scale(
                            scale: 0.965 + 0.035 * curved,
                            child: child,
                          ),
                        ),
                      );
                    },
                    // Absorb taps so they don't fall through to the scrim.
                    child: GestureDetector(
                      onTap: () {},
                      behavior: HitTestBehavior.opaque,
                      child: panel,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A labelled form field on the glass material.
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

/// Input decoration for text fields rendered on the glass material.
InputDecoration glassInputDecoration({String? hint}) => InputDecoration(
  hintText: hint,
  isDense: true,
  filled: true,
  fillColor: AppColors.surface.withValues(alpha: 0.7),
  contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: BorderSide(color: AppColors.hairline),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: BorderSide(color: AppColors.hairline),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
  ),
);

/// A segmented selector (e.g. sprint duration 1–4 weeks) sized to fill width.
class GlassSegmented extends StatelessWidget {
  const GlassSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == selected
                      ? AppColors.navy
                      : AppColors.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(
                    color: i == selected ? AppColors.navy : AppColors.hairline,
                  ),
                ),
                child: Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: i == selected ? Colors.white : AppColors.inkSoft,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A read-only "commitment" / info line used in the start & complete modals.
class GlassInfoLine extends StatelessWidget {
  const GlassInfoLine({super.key, required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.inkSoft),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Header row shared by every sprint modal: an amber icon tile, title + sub,
/// and a close button.
class GlassModalHeader extends StatelessWidget {
  const GlassModalHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppColors.accentStrong),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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

/// Footer with an optional leading hint and the Cancel / confirm buttons.
class GlassModalFooter extends StatelessWidget {
  const GlassModalFooter({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.confirmIcon = LucideIcons.check,
    this.hint,
    this.busy = false,
    this.confirmColor,
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;
  final IconData confirmIcon;
  final Widget? hint;
  final bool busy;

  /// Background colour of the confirm button. Defaults to the app's navy;
  /// pass [AppColors.danger] for destructive confirmations.
  final Color? confirmColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          if (hint != null) Expanded(child: hint!) else const Spacer(),
          const SizedBox(width: 8),
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).maybePop(),
            child: Text(context.t('common.cancel')),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: busy ? null : onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: confirmColor ?? AppColors.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(confirmIcon, size: 15),
            label: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}
