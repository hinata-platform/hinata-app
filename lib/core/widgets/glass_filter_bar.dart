/// The docked filter bar's parts: a liquid-glass pill, and the controls built
/// on it — a search field, a count, a dropdown chip.
///
/// They live in core rather than under one feature because this is what a
/// toolbar docked into the app bar's blur looks like everywhere in the app: a
/// row of real glass floating in the band the bar is already blurring, with the
/// active control washed amber. The admin audit log was the first to need it;
/// it is not the last.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../theme/app_colors.dart';
import 'frosted_surface.dart';
import 'glass_popup_menu.dart';
import 'hive_widgets.dart' show backChevron, forwardChevron;
import '../../features/shell/app_shell.dart' show isNativeApp;
import '../theme/glass_chrome.dart' show kNavGlassDark, kNavGlassLight;

/// Height of a docked search field. A text input needs the room; a control
/// does not, which is what [kGlassControlHeight] is for.
const double kGlassPillHeight = 42;

/// Height a page reserves for its one docked row.
///
/// One number, because four pages wear the same row of the same pills and the
/// shell hands the reserved height down as a *tight* constraint: a page that
/// picked its own put an identical row of controls at a different height from
/// the page beside it. Tall enough for the search field the controls give way
/// to; shorter controls centre in it (see [GlassSearchDock]).
const double kGlassDockRow = kGlassPillHeight;

/// Height of a docked control pill — a chip, a filter, a button.
///
/// Deliberately shorter than the search field. At 42 a 13pt label leaves eleven
/// and a half points of air above and below it, so the pill reads as a box the
/// text happens to sit in rather than as a control; at 36 the proportion is the
/// one every other control in the app keeps.
const double kGlassControlHeight = 36;

/// A liquid-glass pill surface used by every docked filter control. On native it
/// is a real [GlassContainer] (its own glass layer, iOS-26 refraction); on web it
/// is a [FrostedSurface] (a nested backdrop blur pixelates on Skia). [active]
/// lays an amber wash over the glass so a live filter reads clearly on both.
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.onTap,
    this.active = false,
    this.height = kGlassPillHeight,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = height / 2;
    final br = BorderRadius.circular(radius);

    Widget inner = child;
    if (active) {
      inner = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: dark ? 0.22 : 0.15),
          borderRadius: br,
        ),
        child: child,
      );
    }

    Widget surface;
    if (isNativeApp) {
      surface = GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: LiquidRoundedSuperellipse(borderRadius: radius),
        settings: dark ? kNavGlassDark : kNavGlassLight,
        child: inner,
      );
    } else {
      surface = FrostedSurface(
        borderRadius: br,
        dark: dark,
        child: ClipRRect(borderRadius: br, child: inner),
      );
    }

    surface = SizedBox(height: height, child: surface);
    if (onTap == null) return surface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: surface,
    );
  }
}

/// A glass search field for a docked toolbar — the pill surface wrapping a bare,
/// transparent [TextField].
class GlassSearchField extends StatelessWidget {
  const GlassSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
    this.maxLength,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  /// The most characters the field takes, where what it searches has a limit.
  /// Null takes any length.
  final int? maxLength;

  /// Whether the field takes the keyboard as it appears. True where the field
  /// *is* the act — a search mode the reader asked for by pressing a button
  /// has nothing else to be for.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return GlassPill(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
        child: Row(
          children: [
            Icon(LucideIcons.search, size: 17, color: AppColors.inkSoft),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                autofocus: autofocus,
                inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 14, color: AppColors.ink),
                cursorColor: AppColors.accentStrong,
                // The pill itself is the surface — strip every field border/fill
                // so the theme's amber focus outline can't bleed through.
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  hintText: hint,
                  hintStyle: TextStyle(fontSize: 14, color: AppColors.inkFaint),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The icon-only pill that opens a page's search, for a phone's docked row.
///
/// A search *field* is a row of its own, and a page is allowed one docked row
/// in total — the one it already spends on its filters. So on a phone the field
/// is not there until it is asked for, and [GlassSearchDock] is what swaps it
/// in.
///
/// [active] washes the pill amber while a query is in force. Leaving the search
/// clears the query, so on a phone that is normally unreachable — it is for the
/// window that was wide enough to show the field, had something typed into it,
/// and then narrowed. Without it that reader is left looking at a filtered list
/// with nothing on screen to say so.
class GlassSearchButton extends StatelessWidget {
  const GlassSearchButton({
    super.key,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.height = kGlassControlHeight,
  });

  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  /// How tall the pill is. A docked row gives [kGlassControlHeight]; a page
  /// head gives [kGlassPillHeight], so the button lines up with the switcher
  /// next to it rather than sitting a few points low in the row.
  final double height;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GlassPill(
      height: height,
      onTap: onTap,
      active: active,
      child: SizedBox(
        width: height,
        child: Icon(
          LucideIcons.search,
          size: 17,
          color: active ? AppColors.accentInk : AppColors.inkSoft,
        ),
      ),
    ),
  );
}

/// The search a page head carries: a round pill that opens into a field, and
/// closes back into a pill.
///
/// [GlassSearchDock] solves the phone's problem — one docked row, shared
/// between a search and a row of filters. This solves the other one. A page
/// head is a title, a switcher and a button on one line, and a field wide
/// enough to type into does not fit beside them; but a page whose list runs to
/// a hundred rows still needs one. So it is a pill until it is asked for, and
/// the head gives up the width only while somebody is typing.
///
/// The open and the close are the same animation run backwards: the pill grows
/// along its trailing edge into the field, because that is the edge it is
/// pinned to in a head.
class GlassSearchExpander extends StatelessWidget {
  const GlassSearchExpander({
    super.key,
    required this.searching,
    required this.hint,
    required this.controller,
    required this.onChanged,
    required this.onOpen,
    required this.onClose,
    this.width = 360,
    this.height = kGlassPillHeight,
    this.flexible = false,
  });

  final bool searching;
  final String hint;

  /// The height of both shapes. A page head puts a switcher and a button on the
  /// same line, and all three have to be the same height or the row reads as
  /// three controls that happened to land near each other.
  final double height;

  /// Required, because closing the search clears it — see [onClose].
  final TextEditingController controller;

  final ValueChanged<String> onChanged;
  final VoidCallback onOpen;

  /// Told that the search is over. The field has already been cleared and
  /// [onChanged] called with the empty string; this is where the page puts
  /// [searching] back to false.
  final VoidCallback onClose;

  /// How much room the open field asks for, close button included — enough to
  /// read a typed query back, not just the first word of it.
  ///
  /// With [flexible] it is a ceiling rather than a demand.
  final double width;

  /// Whether the shape may come in under [width] when the row is tight.
  ///
  /// Only legal directly inside a [Row] or [Column]: it wraps itself in a
  /// [Flexible]. A page head is exactly that — title, search, switcher, button
  /// on one line — and a narrow window has no [width] to spare, so the field
  /// takes what is left instead of pushing the row into an overflow.
  final bool flexible;

  void _close() {
    if (controller.text.isNotEmpty) {
      controller.clear();
      onChanged('');
    }
    onClose();
  }

  @override
  Widget build(BuildContext context) {
    final shape = _shape(context);
    if (!flexible) return shape;
    // Flex only while the field is open. A flex child is handed a share of the
    // row's free space whether or not it fills it, so a closed pill with flex 1
    // would sit in the middle of a reserved gap and drag the whole action row
    // away from the edge it belongs to. At flex 0 the row lays it out like any
    // other fixed control — and the shape stays in one place in the tree, so
    // the open and close still animate.
    return Flexible(flex: searching ? 1 : 0, child: shape);
  }

  Widget _shape(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    alignment: AlignmentDirectional.centerEnd.resolve(
      Directionality.of(context),
    ),
    child: searching
        ? ConstrainedBox(
            // Flexible hands down the share of the row that is going spare; the
            // ceiling keeps a wide window from turning that into a banner.
            constraints: BoxConstraints(maxWidth: width),
            child: SizedBox(
              width: flexible ? null : width,
              height: height,
              child: Row(
              children: [
                Expanded(
                  child: GlassSearchField(
                    hint: hint,
                    controller: controller,
                    onChanged: onChanged,
                    autofocus: true,
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: MaterialLocalizations.of(
                    context,
                  ).closeButtonTooltip,
                  child: GlassPill(
                    height: height,
                    onTap: _close,
                    child: SizedBox(
                      width: height,
                      child: Icon(
                        LucideIcons.x,
                        size: 17,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
          )
        : GlassSearchButton(
            tooltip: hint,
            active: controller.text.isNotEmpty,
            onTap: onOpen,
            height: height,
          ),
  );
}

/// A page's one docked row, which is either its controls or its search.
///
/// The rule this exists for: the blurred band above a page holds at most two
/// lines, the app bar's own title row and one more. A search field and a row of
/// filters is three, so the field arrives only when it is wanted — sliding down
/// out of the bar it belongs to, already holding the keyboard — and the round
/// button at its trailing edge puts the filters back.
///
/// On a wide window there is no such shortage and no such swap: pass
/// [searching] as false and lay the field out beside the filters as usual.
class GlassSearchDock extends StatelessWidget {
  const GlassSearchDock({
    super.key,
    required this.searching,
    required this.hint,
    required this.controller,
    required this.onChanged,
    required this.onClose,
    required this.controls,
    this.maxLength,
  });

  final bool searching;
  final String hint;

  /// Required, because closing the search clears it — see [onClose].
  final TextEditingController controller;

  final ValueChanged<String> onChanged;

  /// Told that the search is over. The dock has already cleared [controller]
  /// and called [onChanged] with the empty string; this is where the page puts
  /// [searching] back to false.
  final VoidCallback onClose;

  /// What the row shows when nothing is being searched for.
  final Widget controls;

  /// See [GlassSearchField.maxLength].
  final int? maxLength;

  /// Leaves the search, and clears it.
  ///
  /// Here rather than in each page, because it is one rule and three pages had
  /// three copies of it: a field that is gone cannot say what it is still
  /// filtering by, and a list quietly cut to three rows with nothing on screen
  /// to explain it is the bug that would otherwise ship on every one of them.
  void _close() {
    if (controller.text.isNotEmpty) {
      controller.clear();
      onChanged('');
    }
    onClose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 190),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      // Down from above, because that is where it came from: the field is part
      // of the bar, not a panel that appeared over the page.
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -0.4),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: searching
        ? Row(
            key: const ValueKey(true),
            children: [
              Expanded(
                child: GlassSearchField(
                  hint: hint,
                  controller: controller,
                  onChanged: onChanged,
                  autofocus: true,
                  maxLength: maxLength,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: MaterialLocalizations.of(context).closeButtonTooltip,
                child: GlassPill(
                  onTap: _close,
                  child: SizedBox(
                    width: kGlassPillHeight,
                    child: Icon(
                      LucideIcons.x,
                      size: 18,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ],
          )
        : KeyedSubtree(key: const ValueKey(false), child: controls),
  );
}

/// A page's tools on a wide window, laid out in the room they actually get.
///
/// The wide counterpart of [GlassSearchDock]. A phone has one docked row and
/// scrolls it sideways; a wide window lays its tools out, and a window dragged
/// narrower passes through every width on the way, so they wrap instead. One
/// line while everything fits: [leading] on the leading edge, [trailing]
/// against the other one. With less room [trailing] takes a line of its own,
/// and with less still each side wraps among itself. Nothing scrolls out of
/// sight and nothing is cut in half, which a single scrolling line did to the
/// boards' search field and filter at some widths.
class WideToolbar extends StatelessWidget {
  const WideToolbar({
    super.key,
    required this.leading,
    this.trailing = const [],
  });

  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 10,
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [_side(leading), if (trailing.isNotEmpty) _side(trailing)],
  );

  static Widget _side(List<Widget> tools) => tools.length == 1
      ? tools.single
      : Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: tools,
        );
}

/// The control that steps a window back and forth: two chevrons and, between
/// them, the window they are moving.
///
/// Its own widget rather than a shape the timesheet assembles inline, because
/// the chevrons have to be full-height tap targets and that is easy to get
/// wrong. It has one user today — the timesheet's week navigator; the
/// calendar's arrows are on the page canvas on a wide window and are round
/// buttons rather than glass, and on a phone the calendar has no arrows at all.
///
/// The chevrons take the pill's full height, so the tap target is the pill and
/// not an eighteen-point glyph floating in the middle of it.
/// One of a page's lists as a glass pill, washed amber while it is the one
/// showing. The proportions are the filter pills' on the time page, so every
/// docked row in the app reads as one idiom.
///
/// Shared rather than private to the page that first needed it: absences grew a
/// second pair of lists with the same shape (HIN-117), and two copies of a
/// control are two things to keep in step for no gain.
class GlassScopePill extends StatelessWidget {
  const GlassScopePill({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: GlassPill(
        height: kGlassControlHeight,
        active: active,
        onTap: active ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active ? AppColors.accentStrong : AppColors.inkSoft,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? AppColors.accentStrong : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlassStepperPill extends StatelessWidget {
  const GlassStepperPill({
    super.key,
    required this.label,
    required this.onBack,
    required this.onForward,
    required this.backTooltip,
    required this.forwardTooltip,
    this.height = kGlassControlHeight,
  });

  /// What sits between the arrows — a week, a month, a date.
  final Widget label;

  final VoidCallback onBack;
  final VoidCallback onForward;
  final String backTooltip;
  final String forwardTooltip;
  final double height;

  @override
  Widget build(BuildContext context) => GlassPill(
    height: height,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      // Stretched, so each chevron is a full-height tap target.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepperArrow(
          icon: backChevron(context),
          tooltip: backTooltip,
          onTap: onBack,
        ),
        Center(child: label),
        _StepperArrow(
          icon: forwardChevron(context),
          tooltip: forwardTooltip,
          onTap: onForward,
        ),
      ],
    ),
  );
}

/// One of [GlassStepperPill]'s chevrons. Private, so nothing can use it outside
/// a stretched row and quietly get the small tap target back.
class _StepperArrow extends StatelessWidget {
  const _StepperArrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkResponse(
      onTap: onTap,
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Center(child: Icon(icon, size: 18, color: AppColors.inkSoft)),
      ),
    ),
  );
}

/// A read-only amber count pill (e.g. "200 Ereignisse").
class GlassCountPill extends StatelessWidget {
  const GlassCountPill({
    super.key,
    required this.label,
    this.icon = LucideIcons.history,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GlassPill(
      active: true,
      height: kGlassControlHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.accentStrong),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.accentStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A glass dropdown filter chip ("Kategorie ▾"). The trigger is an [GlassPill]
/// (real glass on native / frosted on web) and the menu itself is the app's glass
/// [GlassPopupMenu]. [value] `null` (or the first option) means "no filter".
class GlassFilterChip<T> extends StatelessWidget {
  const GlassFilterChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.menuWidth = 230,
  });

  final IconData icon;
  final String label;
  final T value;

  /// (value, label) pairs; the first is treated as the "all / any" reset.
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final double menuWidth;

  @override
  Widget build(BuildContext context) {
    final active = value != null && value != options.first.$1;
    final current = options.firstWhere(
      (o) => o.$1 == value,
      orElse: () => options.first,
    );
    final text = active ? current.$2 : label;
    final fg = active ? AppColors.accentStrong : AppColors.inkSoft;

    return GlassPopupMenu<int>(
      value: -1,
      width: menuWidth,
      onSelected: (i) => onChanged(options[i].$1),
      items: [
        for (var i = 0; i < options.length; i++)
          GlassMenuItem(value: i, label: options[i].$2),
      ],
      child: GlassPill(
        active: active,
        height: kGlassControlHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 7),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A docked filter: a glass pill that opens a picker, wearing the amber wash
/// when it is narrowing something.
///
/// Its proportions are the audit log's, deliberately — one toolbar idiom in the
/// app rather than two. [kGlassControlHeight] is shorter than the search field
/// above it, which is what the token exists for.
class GlassFilterPill extends StatelessWidget {
  const GlassFilterPill({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.chevron = true,
  });

  final IconData icon;
  final String label;
  final bool active;

  /// Whether the pill shows it opens something. A pill that toggles in place —
  /// an order, say — has nothing to drop down.
  final bool chevron;

  /// Receives the pill's own rectangle on screen, so what it opens can hang off
  /// it on a wide window instead of rising out of the bottom of the display.
  /// Measured here rather than by the caller: the caller holds the page's
  /// context, and the page is the whole page.
  ///
  /// Null when the pill is no longer on screen, which is an answer and not a
  /// failure — the pickers read it as "no anchor" and fall back to the sheet
  /// rather than pinning a popover to the top-left corner of the display.
  final ValueChanged<Rect?> onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentStrong : AppColors.inkSoft;
    return GlassPill(
      height: kGlassControlHeight,
      active: active,
      onTap: () => onTap(_rectOf(context)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 7),
            ConstrainedBox(
              // A project name can be long; the pill may not grow with it.
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? AppColors.accentStrong : AppColors.ink,
                ),
              ),
            ),
            if (chevron) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronDown, size: 13, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

/// Undoes every filter at once — icon-only, matched to the pill height.
class GlassClearFiltersPill extends StatelessWidget {
  const GlassClearFiltersPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlassPill(
    height: kGlassControlHeight,
    onTap: onTap,
    child: SizedBox(
      width: kGlassControlHeight,
      child: Icon(LucideIcons.filterX, size: 16, color: AppColors.inkSoft),
    ),
  );
}

/// The on-screen rectangle of the widget [context] belongs to, or null when it
/// is not laid out — which the pickers read as "no anchor".
Rect? _rectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
