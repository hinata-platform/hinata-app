import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/folded_hint.dart';
import '../../core/theme/app_type.dart';

/// A titled card section used down the account screen. Header carries an amber
/// icon tile + title/subtitle and an optional trailing widget.
class AccountSection extends StatelessWidget {
  const AccountSection({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final accent = danger ? AppColors.danger : AppColors.accentStrong;
    final accentBg = danger
        ? AppColors.danger.withValues(alpha: 0.12)
        : AppColors.accentSoft;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: danger
              ? AppColors.danger.withValues(alpha: 0.35)
              : AppColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppTheme.fontBrand,
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: danger ? AppColors.dangerInk : AppColors.ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: AppType.label,
                            height: 1.35,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.hairline2),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A label/value/control row that stacks the control below the label on phone
/// so it never overflows (per the responsive spec).
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.description,
    this.trailing,
    this.icon,
    this.stack = false,
    this.onTap,
  });

  final String label;
  final String? description;
  final Widget? trailing;
  final IconData? icon;

  /// When true, the trailing control wraps below the text (narrow widths).
  final bool stack;

  /// When set, the whole row becomes tappable (ListTile-style) with a ripple
  /// that spans the full card width — not just the text/trailing controls.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = TitledHint(
      title: label,
      titleStyle: TextStyle(
        fontSize: AppType.label,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      hint: description,
      hintStyle: TextStyle(
        fontSize: AppType.caption,
        height: 1.35,
        color: AppColors.inkSoft,
      ),
    );

    final body = stack
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: AppColors.inkSoft),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: text),
                ],
              ),
              if (trailing != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: trailing!,
                ),
              ],
            ],
          )
        : Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.inkSoft),
                const SizedBox(width: 10),
              ],
              Expanded(child: text),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          );

    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: body,
      );
    }

    // Tappable variant (ListTile-style): the whole row responds to taps with a
    // ripple. The padding lives inside the InkWell so the ink covers the full
    // row height, and matches the default row's vertical inset + horizontal
    // alignment so a tappable row sits flush with its static siblings.
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// A small pill (e.g. "Verified", role badges, "Always on").
class AccountPill extends StatelessWidget {
  const AccountPill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.accentInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A frosted glass capsule for in-section actions (Change, Reset…).
class AccountActionButton extends StatelessWidget {
  const AccountActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    // The app's frosted capsule ([GlassButtons.outlined]); danger tints the
    // label and the rim.
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      foregroundColor: danger ? AppColors.danger : null,
      side: danger
          ? BorderSide(color: AppColors.danger.withValues(alpha: 0.4))
          : null,
    );
    final text = Text(label);
    final glyph = icon;
    return glyph == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: text)
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(glyph, size: 15),
            label: text,
          );
  }
}

/// An amber/red note banner used for the pending-email and danger hints.
class AccountNote extends StatelessWidget {
  const AccountNote({
    super.key,
    required this.text,
    this.icon = LucideIcons.info,
    this.tone = AccountNoteTone.warn,
  });

  final String text;
  final IconData icon;
  final AccountNoteTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AccountNoteTone.warn => AppColors.warning,
      AccountNoteTone.danger => AppColors.danger,
      AccountNoteTone.info => AppColors.stTodo,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppType.label,
                height: 1.4,
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum AccountNoteTone { warn, danger, info }

/// How a [TileSelector] lays its options out.
enum TileSelectorLayout {
  /// Square tiles with a preview above the name — iOS 27's style tiles.
  tile,

  /// A row of pills — the Light / Dark / System switch.
  pill,
}

/// One choice of a [TileSelector].
class TileOption<T> {
  const TileOption({
    required this.value,
    required this.label,
    this.icon,
    this.preview,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// What a tile shows above its name; decorative, excluded from semantics.
  final Widget? preview;
}

/// A group of options of which exactly one is chosen, as tiles or pills.
///
/// Replaces the account screen's private segment switches (`_ThemeSelector`,
/// `_AccessToggle`), which were bare `GestureDetector`s: unreachable by Tab, deaf to Space and Enter, their
/// active segment told apart by a wash of colour alone. Here every option is
/// a focusable button with a visible focus ring, and the chosen one carries a
/// check and a bold name as well as its colour (WCAG 1.4.1, 2.1.1, 2.4.7).
class TileSelector<T> extends StatelessWidget {
  const TileSelector({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.layout = TileSelectorLayout.pill,
  });

  final T value;
  final List<TileOption<T>> options;
  final ValueChanged<T> onChanged;
  final TileSelectorLayout layout;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final option in options)
        _TileOptionButton<T>(
          option: option,
          selected: option.value == value,
          layout: layout,
          onSelect: () => onChanged(option.value),
        ),
    ];
    return switch (layout) {
      TileSelectorLayout.tile => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: tiles,
      ),
      TileSelectorLayout.pill => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tiles,
      ),
    };
  }
}

class _TileOptionButton<T> extends StatefulWidget {
  const _TileOptionButton({
    required this.option,
    required this.selected,
    required this.layout,
    required this.onSelect,
  });

  final TileOption<T> option;
  final bool selected;
  final TileSelectorLayout layout;
  final VoidCallback onSelect;

  @override
  State<_TileOptionButton<T>> createState() => _TileOptionButtonState<T>();
}

class _TileOptionButtonState<T> extends State<_TileOptionButton<T>> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tile = widget.layout == TileSelectorLayout.tile;
    final selected = widget.selected;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final ink = selected ? AppColors.accentInk : AppColors.inkSoft;
    // A list row's hover: the ink at a whisper. `surfaceMuted` sat a shade
    // off the card and could not be seen once the fade had settled.
    final hoverWash = AppColors.ink.withValues(alpha: 0.06);
    final label = Text(
      widget.option.label,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: tile ? AppType.caption : AppType.label,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: ink,
      ),
    );
    final check = selected
        ? Icon(LucideIcons.check, size: tile ? 14 : 15, color: ink)
        : null;
    final content = tile
        ? ConstrainedBox(
            // A tile is a square with a name under it; a long name wraps
            // rather than widening the tile past its neighbours.
            constraints: const BoxConstraints(maxWidth: 132),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.option.preview != null)
                  ExcludeSemantics(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: widget.option.preview,
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (check != null) ...[check, const SizedBox(width: 4)],
                    Flexible(child: label),
                  ],
                ),
              ],
            ),
          )
        : ConstrainedBox(
            // A pill's name wraps at large text sizes instead of running
            // past the row.
            constraints: const BoxConstraints(maxWidth: 300),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.option.icon != null) ...[
                  Icon(widget.option.icon, size: 15, color: ink),
                  const SizedBox(width: 6),
                ],
                if (check != null) ...[check, const SizedBox(width: 4)],
                Flexible(child: label),
              ],
            ),
          );
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        label: widget.option.label,
        onTap: widget.onSelect,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect,
          // The focus ring sits outside the pill so it never fights the
          // state border.
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tile ? 16 : 12),
              border: Border.all(
                color: _focused ? AppColors.focusRing : Colors.transparent,
                width: 2,
              ),
            ),
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              constraints: BoxConstraints(
                minWidth: tile ? 72 : 48,
                minHeight: tile ? 72 : 44,
              ),
              margin: const EdgeInsets.all(2),
              padding: EdgeInsets.symmetric(
                horizontal: tile ? 10 : 14,
                vertical: tile ? 8 : 9,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accentSoft
                    : _hovered
                    ? hoverWash
                    // The same ink with no alpha, not Colors.transparent:
                    // that is transparent black, and the fade towards it
                    // passed through grey.
                    : hoverWash.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(tile ? 14 : 10),
                border: Border.all(
                  color: selected ? AppColors.stateBorder : AppColors.hairline,
                ),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
