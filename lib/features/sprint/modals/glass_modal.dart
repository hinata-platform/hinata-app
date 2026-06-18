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
    pageBuilder: (_, _, _) => _GlassModalScaffold(width: width, builder: builder),
    transitionBuilder: (_, _, _, child) => child,
  );
}

class _GlassModalScaffold extends StatelessWidget {
  const _GlassModalScaffold({required this.width, required this.builder});

  final double width;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < _kPhoneBreakpoint;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final anim = ModalRoute.of(context)!.animation!;
    final maxW = mobile ? size.width - 32 : width;
    final maxH = size.height - (mobile ? 120 : 96);

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
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AnimatedBuilder(
                  animation: anim,
                  builder: (_, child) {
                    if (reduceMotion) {
                      return Opacity(opacity: anim.value, child: child);
                    }
                    final curved = const Cubic(0.34, 1.56, 0.64, 1)
                        .transform(anim.value.clamp(0.0, 1.0));
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
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;
  final IconData confirmIcon;
  final Widget? hint;
  final bool busy;

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
              backgroundColor: AppColors.navy,
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
