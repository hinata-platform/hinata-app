import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../../features/search/search_tokens.dart';
import 'glass_panel.dart';
import 'hive_widgets.dart' show forwardChevron;
import '../theme/app_type.dart';

/// One line in a [GlassPopupMenu]: an action ([GlassMenuItem]) or a line that
/// only informs ([GlassMenuNote]).
sealed class GlassMenuEntry<T> {
  const GlassMenuEntry({this.dividerAbove = false});

  /// When true, a hairline divider is drawn above this line to separate it
  /// from the previous group (e.g. before a destructive action).
  final bool dividerAbove;
}

/// One selectable row in a [GlassPopupMenu].
class GlassMenuItem<T> extends GlassMenuEntry<T> {
  const GlassMenuItem({
    required this.value,
    required this.label,
    this.leading,
    this.trailing,
    this.color,
    super.dividerAbove,
    this.enabled = true,
    this.disabledReason,
    this.submenu,
  });

  /// The value reported back through [GlassPopupMenu.onSelected] when tapped.
  /// Unused on a row that opens a [submenu].
  final T value;

  /// The row's text.
  final String label;

  /// Optional leading glyph/avatar shown left of the label.
  final Widget? leading;

  /// Optional trailing glyph. Yields to the check mark when the row is the
  /// selected value, and to the chevron when it opens a [submenu].
  final Widget? trailing;

  /// Optional label colour — e.g. a danger tint for a destructive action.
  /// Falls back to the standard ink colour when null.
  final Color? color;

  /// When false the row is shown greyed-out and is not selectable — used for
  /// guarded actions (e.g. last-admin, SSO-managed) that should be visible but
  /// inert per the "disable, don't hide" rule.
  final bool enabled;

  /// Optional reason shown beneath a disabled row's label.
  final String? disabledReason;

  /// Rows of a card that opens over this menu when the row is chosen, instead
  /// of a second popover of its own. The card's header repeats this row's
  /// glyph and label and takes the card back down; a row chosen inside it
  /// reports its value through the same [GlassPopupMenu.onSelected].
  final List<GlassMenuEntry<T>>? submenu;
}

/// A line that says something and does nothing when tapped: a hint, a section
/// caption, a person on a roster.
class GlassMenuNote<T> extends GlassMenuEntry<T> {
  const GlassMenuNote({
    required this.label,
    this.leading,
    this.caption = false,
    super.dividerAbove,
  });

  final String label;

  /// Optional glyph or avatar, in the slot a row's leading glyph sits in.
  final Widget? leading;

  /// Small faint text (a hint or a section caption) instead of row text.
  final bool caption;
}

/// A reusable liquid-glass replacement for [PopupMenuButton].
///
/// Renders [child] as the tappable anchor and, on tap, opens the package's
/// [lg.GlassMenu] at it: the glass grows out of the anchor and rows with a
/// [GlassMenuItem.submenu] open as layered cards over their parent. The
/// currently [value]-matched row carries a check; choosing a row reports it
/// through [onSelected] and closes the menu.
class GlassPopupMenu<T> extends StatefulWidget {
  const GlassPopupMenu({
    super.key,
    this.items = const [],
    this.itemsBuilder,
    required this.value,
    required this.onSelected,
    required this.child,
    this.width = 240,
    this.onOpenChanged,
  });

  /// The rows to show.
  final List<GlassMenuEntry<T>> items;

  /// Builds the rows when the menu opens, in place of [items] — for a menu
  /// whose rows cost something to work out and that every row of a list
  /// carries, most of which are never opened.
  final List<GlassMenuEntry<T>> Function(BuildContext context)? itemsBuilder;

  /// The currently selected value (highlighted in the list). May be `null`.
  final T value;

  /// Called with the chosen row's value.
  final ValueChanged<T> onSelected;

  /// The tappable anchor (e.g. a chip or button).
  final Widget child;

  /// Menu width.
  final double width;

  /// Called with `true` when the menu opens and `false` when it closes.
  ///
  /// For anchors that share the screen with something floating of their own —
  /// the editor's selection overlay is the case this exists for. That overlay
  /// points at the words the menu now covers, so it has to step aside while
  /// the menu is up; nothing else can know when that is.
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<GlassPopupMenu<T>> createState() => _GlassPopupMenuState<T>();
}

/// Opens the same glass menu [GlassPopupMenu] does, for an anchor that is not
/// a widget this library wraps.
///
/// The wrapper covers the ordinary case — a chip or a button that *is* the
/// menu. It cannot cover a control the app shell draws on a page's behalf: the
/// title in the compact app bar belongs to the shell and the menu behind it
/// belongs to the page, so the two meet through a rect and a future rather than
/// through a widget one of them owns.
///
/// Returns the chosen value, or null when the menu was dismissed — so `T` here
/// should be non-nullable; the widget form is the one that can tell "picked
/// null" from "dismissed". [anchorRect] is in global coordinates.
Future<T?> showGlassMenu<T extends Object>({
  required BuildContext context,
  required Rect anchorRect,
  required List<GlassMenuEntry<T>> items,
  required T value,
  double width = 240,
}) async {
  final selected = await _showMenu<T>(
    context: context,
    anchorRect: anchorRect,
    items: items,
    value: value,
    width: width,
  );
  return selected?.value;
}

/// The menu itself, shared by the widget form and the imperative one.
///
/// It runs in a route of its own rather than under the anchor: an anchor in a
/// hover-gated subtree (a tree row's action button) unmounts as soon as the
/// menu covers it, and would take a menu it owned down with it. The future
/// resolves as soon as a row is chosen or the menu starts to close; the route
/// leaves once the closing morph has played.
Future<_MenuResult<T>?> _showMenu<T>({
  required BuildContext context,
  required Rect anchorRect,
  required List<GlassMenuEntry<T>> items,
  required T value,
  required double width,
}) {
  final result = Completer<_MenuResult<T>?>();
  unawaited(
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => _GlassMenuHost<T>(
        anchorRect: anchorRect,
        items: items,
        value: value,
        width: width,
        result: result,
      ),
    ),
  );
  return result.future;
}

class _GlassPopupMenuState<T> extends State<GlassPopupMenu<T>> {
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _open() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final Rect anchorRect = (box != null && box.hasSize)
        ? (box.localToGlobal(Offset.zero) & box.size)
        : Rect.zero;

    // Capture the callback up-front: when this anchor lives inside a hover-gated
    // subtree (e.g. a tree row's action menu that only renders while hovered),
    // opening the menu moves the pointer off the row, which unmounts the
    // anchor — and therefore this State — before the menu returns. The owner
    // of [onSelected] (the parent screen) is still alive and guards its own
    // async work, so we must invoke it regardless of *our* mounted state; an
    // earlier `&& mounted` check here silently dropped the selection.
    final onSelected = widget.onSelected;
    // Captured for the same reason, and called in a `finally` for one more:
    // whatever was told to step aside has to be told to come back, including
    // when the menu is dismissed rather than answered.
    final onOpenChanged = widget.onOpenChanged;
    onOpenChanged?.call(true);

    final _MenuResult<T>? selected;
    try {
      selected = await _showMenu<T>(
        context: context,
        anchorRect: anchorRect,
        items: widget.itemsBuilder?.call(context) ?? widget.items,
        value: widget.value,
        width: widget.width,
      );
    } finally {
      onOpenChanged?.call(false);
    }

    if (selected != null) onSelected(selected.value);
  }

  @override
  Widget build(BuildContext context) {
    // The anchor is drawn by the caller, so the role comes from here: a
    // button that opens a menu, named by whatever text the anchor shows. The
    // click cursor is the hover cue; the anchor keeps its own resting look.
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _open,
          behavior: HitTestBehavior.opaque,
          child: KeyedSubtree(key: _anchorKey, child: widget.child),
        ),
      ),
    );
  }
}

/// Wrapper so a `null` selection still distinguishes "picked null" from
/// "dismissed" (which resolves to `null`).
class _MenuResult<T> {
  const _MenuResult(this.value);
  final T value;
}

/// Places an invisible stand-in for the anchor where the anchor is, so the
/// package menu grows out of the spot the user touched, opens it, and takes
/// its route away again once the menu has closed.
class _GlassMenuHost<T> extends StatefulWidget {
  const _GlassMenuHost({
    required this.anchorRect,
    required this.items,
    required this.value,
    required this.width,
    required this.result,
  });

  final Rect anchorRect;
  final List<GlassMenuEntry<T>> items;
  final T value;
  final double width;
  final Completer<_MenuResult<T>?> result;

  @override
  State<_GlassMenuHost<T>> createState() => _GlassMenuHostState<T>();
}

class _GlassMenuHostState<T> extends State<_GlassMenuHost<T>>
    with SingleTickerProviderStateMixin {
  static const double _margin = 12;
  static const double _radius = 20;
  static const double _rowHeight = 44;

  final lg.GlassMenuController _controller = lg.GlassMenuController();

  /// Runs from the moment the menu starts closing until its overlay is gone,
  /// since the package reports the start of a close and not its end.
  late final Ticker _closeWatch = createTicker(_watchClose);

  @override
  void initState() {
    super.initState();
    // The stand-in has to be laid out before the menu can measure it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.open();
    });
  }

  @override
  void dispose() {
    // Taken away by something else (the back key, a route pushed over it):
    // the caller still waits for an answer.
    _finish(null);
    _closeWatch.dispose();
    super.dispose();
  }

  void _finish(_MenuResult<T>? result) {
    if (!widget.result.isCompleted) widget.result.complete(result);
  }

  void _onClose() {
    // A row chosen just before already answered; this only covers a dismiss.
    _finish(null);
    if (!_closeWatch.isActive) _closeWatch.start();
  }

  void _watchClose(Duration _) {
    if (_controller.isOpen) return;
    _closeWatch.stop();
    final route = ModalRoute.of(context);
    // Removed rather than popped: whatever the choice opened may already sit
    // on top of this route, and a pop would close that instead.
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final width = math.min(widget.width, size.width - _margin * 2);
    final rows = _MenuRows<T>(
      context: context,
      tokens: tokens,
      value: widget.value,
      width: width,
      onPick: (value) => _finish(_MenuResult<T>(value)),
    );

    return Stack(
      children: [
        Positioned.fromRect(
          rect: widget.anchorRect,
          // The menu's overlay inherits from here: without a Material above
          // it, its text falls back to the debug style (yellow underline).
          child: Material(
            type: MaterialType.transparency,
            child: lg.GlassMenu(
              controller: _controller,
              trigger: const SizedBox.expand(),
              items: rows.build(widget.items),
              menuWidth: width,
              menuBorderRadius: _radius,
              itemBorderRadius: 12,
              autoAdjustToScreen: true,
              menuPadding: EdgeInsets.fromLTRB(
                _margin,
                _margin + pad.top,
                _margin,
                _margin + pad.bottom,
              ),
              // Same fill as the app's other popovers carry under their rows: a
              // menu opens over whatever its button happens to sit on.
              settings: liquidGlassPanelSettings(
                glassFill: tokens.tint,
                dark: dark,
              ),
              quality: kPanelGlassQuality,
              selectionColor: tokens.rowHover,
              glowColor: tokens.glare.withValues(alpha: dark ? 0.12 : 0.3),
              morphFromZero: widget.anchorRect.isEmpty,
              morphSpeed: MediaQuery.disableAnimationsOf(context)
                  ? lg.MorphSpeed.instant
                  : lg.MorphSpeed.normal,
              onClose: _onClose,
            ),
          ),
        ),
      ],
    );
  }
}

/// Turns the app's menu entries into the package's rows.
class _MenuRows<T> {
  _MenuRows({
    required this.context,
    required this.tokens,
    required this.value,
    required this.width,
    required this.onPick,
  });

  final BuildContext context;
  final SearchTokens tokens;
  final T value;
  final double width;
  final ValueChanged<T> onPick;

  List<Widget> build(List<GlassMenuEntry<T>> entries) => [
    for (final (i, entry) in entries.indexed) ...[
      if (entry.dividerAbove && i > 0)
        lg.GlassMenuDivider(color: tokens.hairline, indent: 12),
      switch (entry) {
        GlassMenuItem<T>() => _item(entry),
        GlassMenuNote<T>() => _GlassMenuNoteRow(
          note: entry,
          tokens: tokens,
          width: width,
          textScaler: MediaQuery.textScalerOf(context),
          baseStyle: DefaultTextStyle.of(context).style,
          textDirection: Directionality.of(context),
        ),
      },
    ],
  ];

  Widget _item(GlassMenuItem<T> item) {
    final submenu = item.submenu;
    // The value is only a value on a row that is chosen: a submenu row's
    // placeholder must not tick it as the current one.
    final selected = submenu == null && item.value == value;
    final ink = item.color ?? tokens.ink;
    return lg.GlassMenuItem(
      // Labels can repeat (two teams of one name), and the package keys rows
      // by label when they have no key of their own.
      key: ObjectKey(item),
      title: item.label,
      icon: item.leading,
      subtitle: !item.enabled ? item.disabledReason : null,
      enabled: item.enabled,
      height: _GlassMenuHostState._rowHeight,
      titleStyle: TextStyle(
        fontSize: AppType.body,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      subtitleStyle: TextStyle(
        fontSize: AppType.caption,
        color: tokens.inkSoft,
      ),
      iconColor: ink,
      iconSize: 17,
      trailing: selected
          ? Icon(
              LucideIcons.check,
              size: 17,
              color: AppColors.accentInk,
              semanticLabel: context.t('common.selectedOption'),
            )
          : submenu != null
          // The package draws a chevron that points right in every reading
          // direction.
          ? Icon(forwardChevron(context), size: 16, color: tokens.inkFaint)
          : item.trailing,
      submenu: submenu == null ? null : build(submenu),
      onTap: () => onPick(item.value),
    );
  }
}

/// A [GlassMenuNote], measured up front: the package lays rows out from the
/// heights they declare.
class _GlassMenuNoteRow extends StatelessWidget implements PreferredSizeWidget {
  _GlassMenuNoteRow({
    required this.note,
    required this.tokens,
    required double width,
    required TextScaler textScaler,
    required TextStyle baseStyle,
    required TextDirection textDirection,
  }) : preferredSize = Size.fromHeight(
         _measure(
           note,
           baseStyle.merge(_style(note, tokens)),
           width,
           textScaler,
           textDirection,
         ),
       );

  final GlassMenuNote note;
  final SearchTokens tokens;

  @override
  final Size preferredSize;

  static const double _hPad = 16;

  /// The package insets every row of the menu body by this much on each side.
  static const double _bodyPad = 12;
  static const double _leadingSlot = 26 + 12;

  static TextStyle _style(GlassMenuNote note, SearchTokens tokens) =>
      note.caption
      ? TextStyle(
          fontSize: AppType.caption,
          height: 1.35,
          color: tokens.inkFaint,
        )
      : TextStyle(
          fontSize: AppType.label,
          fontWeight: FontWeight.w600,
          color: tokens.ink,
        );

  static int _maxLines(GlassMenuNote note) => note.caption ? 4 : 1;

  static double _measure(
    GlassMenuNote note,
    TextStyle style,
    double width,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    final textWidth =
        width -
        _bodyPad * 2 -
        _hPad * 2 -
        (note.leading != null ? _leadingSlot : 0);
    final painter = TextPainter(
      text: TextSpan(text: note.label, style: style),
      maxLines: _maxLines(note),
      ellipsis: '…',
      textScaler: textScaler,
      textDirection: textDirection,
    )..layout(maxWidth: math.max(1, textWidth));
    final text = painter.height;
    painter.dispose();
    final content = note.leading != null ? math.max(text, 26.0) : text;
    return content + (note.caption ? 8 : 14);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: preferredSize.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _hPad),
        child: Row(
          children: [
            if (note.leading != null) ...[
              SizedBox(width: 26, child: Center(child: note.leading)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                note.label,
                maxLines: _maxLines(note),
                overflow: TextOverflow.ellipsis,
                style: _style(note, tokens),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
