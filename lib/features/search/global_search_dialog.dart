import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../../core/repositories/search_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/hive_widgets.dart';
import 'global_search_controller.dart';
import 'search_models.dart';
import 'search_tokens.dart';

/// Phone breakpoint — below this the palette becomes a full-screen sheet that
/// slides down from the top (matches the app's phone breakpoint, §3.5).
const double _kPhoneBreakpoint = 610;

/// Opens the global search / command palette over a dimmed, blurred app.
///
/// Uses [showGeneralDialog] so we own the scrim, blur and spring (§3.1). The
/// enter/exit motion lives inside [GlobalSearchDialog], driven by the route
/// animation, so it can branch between the desktop spring and the mobile sheet.
Future<void> openGlobalSearch(BuildContext context) {
  final controller = GlobalSearchController(
    repository: context.read<SearchRepository>(),
    storage: context.read<AppStorage>(),
  );
  // Localise command labels against the launching context, then load async.
  controller.load(t: (key) => context.t(key));

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent, // we paint our own scrim
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (_, _, _) => GlobalSearchDialog(controller: controller),
    // Motion is handled inside the dialog (reads the route animation), so the
    // transition builder is a pass-through.
    transitionBuilder: (_, _, _, child) => child,
  ).whenComplete(controller.dispose);
}

class GlobalSearchDialog extends StatefulWidget {
  const GlobalSearchDialog({super.key, required this.controller});

  final GlobalSearchController controller;

  @override
  State<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<GlobalSearchDialog> {
  GlobalSearchController get _c => widget.controller;

  final _text = TextEditingController();
  late final FocusNode _fieldNode;
  final _scroll = ScrollController();
  final _rowKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _fieldNode = FocusNode(onKeyEvent: _onKey);
    _c.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChange);
    _text.dispose();
    _fieldNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    // Sync the field when a recent search is applied programmatically.
    if (_text.text != _c.query) {
      _text.value = TextEditingValue(
        text: _c.query,
        selection: TextSelection.collapsed(offset: _c.query.length),
      );
    }
    // Keep the selected row in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowCtx = _rowKeys[_c.selected]?.currentContext;
      if (rowCtx != null) {
        Scrollable.ensureVisible(rowCtx,
            alignment: 0.12,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic);
      }
    });
    if (mounted) setState(() {});
  }

  // ---- keyboard model (§4.5) ----
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _close();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _c.moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _c.moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _activateSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        _c.cycleScope(!HardwareKeyboard.instance.isShiftPressed);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _activateSelected() {
    if (_c.showRecents) {
      final recent = _c.selectedRecent;
      if (recent != null) _applyRecent(recent);
      return;
    }
    final entry = _c.selectedEntry;
    if (entry != null) _activateEntry(entry);
  }

  void _applyRecent(String recent) {
    _c.setQuery(recent);
    _fieldNode.requestFocus();
  }

  void _activateEntry(SearchEntry entry) {
    final query = _c.query.trim();
    if (query.isNotEmpty) _c.pushRecent(query);
    // Navigate while the dialog (and its context) is still mounted, then
    // dismiss — the dialog sits above the shell on the root navigator.
    entry.onSelect(context);
    if (entry.closesOnSelect) _close();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < _kPhoneBreakpoint;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final anim = ModalRoute.of(context)!.animation!;

    return Stack(
      children: [
        // ---- scrim: dim + blur the app behind (§3.2) ----
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
                onTap: _close,
                child: scrim,
              ),
            );
          },
        ),
        // ---- the panel ----
        Positioned.fill(
          child: SafeArea(
            top: !mobile,
            bottom: !mobile,
            child: mobile
                ? _mobilePanel(tokens, anim, reduceMotion, size)
                : _desktopPanel(tokens, anim, reduceMotion, size),
          ),
        ),
      ],
    );
  }

  // ---- desktop: centered dialog with the spring entrance (§3.5) ----
  Widget _desktopPanel(SearchTokens tokens, Animation<double> anim,
      bool reduceMotion, Size size) {
    final maxW = math.min(640.0, size.width - 48);
    final maxH = math.min(620.0, size.height * 0.78);
    final panel = Padding(
      padding: EdgeInsets.fromLTRB(24, size.height * 0.11, 24, 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
          child: _shadowed(tokens, BorderRadius.circular(28),
              _glassPanel(tokens, radius: 28, mobile: false)),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) {
        if (reduceMotion) return Opacity(opacity: anim.value, child: child);
        final curved = const Cubic(0.34, 1.56, 0.64, 1).transform(
            anim.value.clamp(0.0, 1.0));
        final fade = (anim.value / 0.6).clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, (1 - curved) * -14),
            child: Transform.scale(
              scale: 0.965 + 0.035 * curved,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: panel,
    );
  }

  // ---- mobile: full-screen sheet sliding from the top (§3.5) ----
  Widget _mobilePanel(SearchTokens tokens, Animation<double> anim,
      bool reduceMotion, Size size) {
    const radius = BorderRadius.vertical(bottom: Radius.circular(26));
    final panel = SizedBox.expand(
      child: _shadowed(
          tokens, radius, _glassPanel(tokens, radius: 26, mobile: true)),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) {
        if (reduceMotion) return Opacity(opacity: anim.value, child: child);
        final eased =
            const Cubic(0.22, 1, 0.36, 1).transform(anim.value.clamp(0.0, 1.0));
        return FractionalTranslation(
          translation: Offset(0, eased - 1.0),
          child: child,
        );
      },
      child: panel,
    );
  }

  /// Drop shadow behind the (transparent) glass, clipped to outside the panel
  /// so the dark blur can't bleed up through it. See [GlassPanelShadow].
  Widget _shadowed(SearchTokens tokens, BorderRadius radius, Widget child) {
    return GlassPanelShadow(
      radius: radius, shadows: tokens.panelShadow, child: child);
  }

  Widget _glassPanel(SearchTokens tokens,
      {required double radius, required bool mobile}) {
    final content = _PointerGlare(
      color: tokens.glare,
      enabled: !mobile,
      child: Stack(
        children: [
          // showGeneralDialog inserts no Material, so the TextField (and any
          // ink-using descendant) needs one. Transparent → keeps the glass look.
          Material(type: MaterialType.transparency, child: _column(tokens, mobile)),
          // Specular rim — bright top-left → dim → bright, at 140° (§3.3).
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RimPainter(
                  radius: radius,
                  edge: tokens.edge,
                  edgeSoft: tokens.edgeSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final dark = Theme.of(context).brightness == Brightness.dark;

    // Real iOS-26 liquid glass via the package. The effect comes from
    // refraction + blur + specular highlights, NOT a tint fill — the package's
    // own default `glassColor` is fully transparent. The earlier code passed
    // `glassColor: tokens.tint` (alpha 0.62), a near-opaque warm fill that
    // buried the glass and read as a flat card. We now feed a very light tint
    // (just enough warmth + text contrast) and let the lens do the work.
    // `premium` quality enables texture capture + chromatic aberration on
    // Impeller (falls back gracefully on Skia/Web).
    final glass = GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.premium,
      clipBehavior: Clip.antiAlias,
      shape: LiquidRoundedSuperellipse(borderRadius: mobile ? 0 : radius),
      settings: liquidGlassPanelSettings(glassFill: tokens.glassFill, dark: dark),
      child: content,
    );

    if (mobile) {
      return ClipRRect(
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(26)),
        child: glass,
      );
    }
    return glass;
  }

  Widget _column(SearchTokens tokens, bool mobile) {
    final results = _Results(
      controller: _c,
      scroll: _scroll,
      tokens: tokens,
      rowKeys: _rowKeys,
      onActivateEntry: _activateEntry,
      onApplyRecent: _applyRecent,
      onHoverIndex: _c.setSelected,
    );
    // Absorb taps inside the panel so they don't fall through to the scrim.
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: mobile ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _field(tokens, mobile),
          _scopes(tokens),
          if (mobile)
            Expanded(child: results)
          else
            Flexible(child: results),
          if (!mobile) _footer(tokens),
        ],
      ),
    );
  }

  // ---- field (§3.4) ----
  Widget _field(SearchTokens tokens, bool mobile) {
    final topPad = mobile
        ? math.max(20.0, MediaQuery.viewPaddingOf(context).top + 12)
        : 18.0;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPad, 20, 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 22, color: tokens.inkSoft),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _fieldNode,
              autofocus: true,
              cursorColor: tokens.ink,
              onChanged: _c.setQuery,
              style: TextStyle(
                fontSize: mobile ? 19 : 20,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
                color: tokens.ink,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                fillColor: Colors.transparent,
                hoverColor: Colors.transparent,
                hintText: context.t('search.placeholder'),
                hintStyle: TextStyle(
                  fontSize: mobile ? 19 : 20,
                  fontWeight: FontWeight.w400,
                  color: tokens.inkFaint,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _EscPill(tokens: tokens, onTap: _close, mobile: mobile),
        ],
      ),
    );
  }

  // ---- scope chips (§3.4) ----
  Widget _scopes(SearchTokens tokens) {
    final chips = <SearchCat?>[null, ...SearchCat.values];
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            for (final cat in chips) ...[
              _ScopeChip(
                tokens: tokens,
                icon: cat == null
                    ? LucideIcons.sparkles
                    : kSearchCatMeta[cat]!.icon,
                label: cat == null
                    ? context.t('search.scope.all')
                    : context.t(kSearchCatMeta[cat]!.labelKey),
                count: cat == null ? null : (_c.counts[cat] ?? 0),
                active: _c.scope == cat,
                onTap: () => _c.setScope(cat),
              ),
              const SizedBox(width: 7),
            ],
          ],
        ),
      ),
    );
  }

  // ---- footer (desktop only, §3.4) ----
  Widget _footer(SearchTokens tokens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
      decoration: BoxDecoration(
        color: tokens.field,
        border: Border(top: BorderSide(color: tokens.hairline)),
      ),
      child: Row(
        children: [
          // Hints take the free space; if they don't fit (e.g. long labels or
          // untranslated keys) they scroll instead of overflowing the footer.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FootHint(tokens: tokens, caps: const ['↑', '↓'], label: context.t('search.foot.navigate')),
                  const SizedBox(width: 16),
                  _FootHint(tokens: tokens, caps: const ['↵'], label: context.t('search.foot.open')),
                  const SizedBox(width: 16),
                  _FootHint(tokens: tokens, caps: const ['tab'], label: context.t('search.foot.scope')),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          HexMark(size: 15, color: AppColors.accent),
          const SizedBox(width: 7),
          Text(
            context.t('search.brand'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: tokens.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── results ────────────────────────────────────

class _Results extends StatelessWidget {
  const _Results({
    required this.controller,
    required this.scroll,
    required this.tokens,
    required this.rowKeys,
    required this.onActivateEntry,
    required this.onApplyRecent,
    required this.onHoverIndex,
  });

  final GlobalSearchController controller;
  final ScrollController scroll;
  final SearchTokens tokens;
  final Map<int, GlobalKey> rowKeys;
  final void Function(SearchEntry) onActivateEntry;
  final void Function(String) onApplyRecent;
  final void Function(int) onHoverIndex;

  @override
  Widget build(BuildContext context) {
    rowKeys.clear();
    final children = <Widget>[];
    var flatIndex = 0;

    GlobalKey keyFor(int i) => rowKeys.putIfAbsent(i, () => GlobalKey());

    if (controller.showRecents) {
      children.add(_RecentsHead(
        tokens: tokens,
        hasItems: controller.recents.isNotEmpty,
        onClear: controller.clearRecents,
      ));
      if (controller.recents.isEmpty) {
        children.add(_EmptyDeep(
          tokens: tokens,
          icon: null,
          title: context.t('search.empty.title'),
          subtitle: context.t('search.empty.subtitle'),
        ));
      } else {
        for (final recent in controller.recents) {
          final i = flatIndex++;
          children.add(_RecentRow(
            key: keyFor(i),
            tokens: tokens,
            text: recent,
            selected: controller.selected == i,
            onTap: () => onApplyRecent(recent),
            onHover: () => onHoverIndex(i),
          ));
        }
      }
    } else if (controller.flatLength == 0) {
      // Only surface "no matches" for a real query — a blank scoped query just
      // awaits its suggestions (don't flash an empty-state).
      if (controller.query.trim().isNotEmpty) {
        children.add(_EmptyDeep(
          tokens: tokens,
          icon: LucideIcons.searchX,
          title: context.t('search.noMatch',
              variables: {'q': controller.query.trim()}),
          subtitle: context.t('search.noMatchSub'),
        ));
      }
    } else {
      for (final group in controller.groups) {
        children.add(_GroupLabel(
          tokens: tokens,
          icon: kSearchCatMeta[group.cat]!.icon,
          label: context.t(kSearchCatMeta[group.cat]!.labelKey),
        ));
        for (final entry in group.items) {
          final i = flatIndex++;
          children.add(_ResultRow(
            key: keyFor(i),
            tokens: tokens,
            entry: entry,
            query: controller.query,
            selected: controller.selected == i,
            onTap: () => onActivateEntry(entry),
            onHover: () => onHoverIndex(i),
          ));
        }
      }
    }

    return Scrollbar(
      controller: scroll,
      child: SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

// ─────────────────────────────── rows ───────────────────────────────────────

/// Shared selectable lozenge: hover/selected tint, inset highlight, the 3px
/// accent bar on the left edge and the trailing `↵` reveal on selection.
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.tokens,
    required this.selected,
    required this.onTap,
    required this.onHover,
    required this.children,
  });

  final SearchTokens tokens;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? tokens.selTint : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: tokens.selEdge,
                          offset: const Offset(0, 1),
                          blurRadius: 0,
                          spreadRadius: -0.5,
                        ),
                      ]
                    : null,
              ),
              child: Row(children: children),
            ),
            if (selected)
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.tokens,
    required this.entry,
    required this.query,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final SearchTokens tokens;
  final SearchEntry entry;
  final String query;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      tokens: tokens,
      selected: selected,
      onTap: onTap,
      onHover: onHover,
      children: [
        _leading(),
        const SizedBox(width: 13),
        Expanded(child: _body()),
        const SizedBox(width: 8),
        _trailing(),
      ],
    );
  }

  Widget _leading() {
    switch (entry.cat) {
      case SearchCat.issues:
        return TypeGlyph(type: entry.issueType ?? 'TASK', size: 34);
      case SearchCat.projects:
        return _HexChip(
          text: entry.keyChipText ?? '',
          color: entry.keyChipColor ?? AppColors.stBacklog,
        );
      case SearchCat.people:
        return HiveAvatar(
            name: entry.avatarName ?? entry.title,
            imageUrl: entry.avatarUrl,
            size: 34);
      case SearchCat.commands:
      case SearchCat.boards:
      case SearchCat.docs:
        return _IconTile(tokens: tokens, icon: entry.leadingIcon ?? LucideIcons.zap);
    }
  }

  Widget _body() {
    final title = Text.rich(
      TextSpan(
        children: _highlightSpans(
          entry.title,
          query,
          TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tokens.ink,
            letterSpacing: -0.1,
          ),
          tokens.markBg,
        ),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (entry.cat == SearchCat.issues) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(
                  entry.mono ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11,
                    color: tokens.inkSoft,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: entry.statusColor ?? tokens.inkFaint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  entry.statusName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: tokens.inkSoft),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (entry.subtitle == null) {
      return title;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        const SizedBox(height: 2),
        Text(
          entry.subtitle!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: tokens.inkSoft),
        ),
      ],
    );
  }

  Widget _trailing() {
    final meta = <Widget>[];
    switch (entry.cat) {
      case SearchCat.issues:
        if (entry.avatarName != null) {
          meta.add(HiveAvatar(
              name: entry.avatarName!, imageUrl: entry.avatarUrl, size: 22));
        }
      case SearchCat.projects:
        if (entry.memberNames != null && entry.memberNames!.isNotEmpty) {
          meta.add(HiveAvatarStack(names: entry.memberNames!, size: 20, max: 3));
        }
      case SearchCat.commands:
        if (entry.hint != null) {
          meta.add(_KbdHint(tokens: tokens, text: entry.hint!));
        }
      case SearchCat.people:
      case SearchCat.boards:
      case SearchCat.docs:
        break;
    }
    if (selected) {
      if (meta.isNotEmpty) meta.add(const SizedBox(width: 8));
      meta.add(Text('↵',
          style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 12,
              color: tokens.inkFaint)));
    }
    if (meta.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: meta);
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    super.key,
    required this.tokens,
    required this.text,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final SearchTokens tokens;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      tokens: tokens,
      selected: selected,
      onTap: onTap,
      onHover: onHover,
      children: [
        _IconTile(tokens: tokens, icon: LucideIcons.clock),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: tokens.ink),
          ),
        ),
        const SizedBox(width: 8),
        Icon(LucideIcons.arrowUpLeft, size: 15, color: tokens.inkFaint),
      ],
    );
  }
}

// ─────────────────────────────── pieces ─────────────────────────────────────

class _IconTile extends StatelessWidget {
  const _IconTile({required this.tokens, required this.icon});
  final SearchTokens tokens;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: tokens.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.hairline),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 17, color: tokens.inkSoft),
    );
  }
}

/// Filled hexagon chip carrying a project key (the `.gs-pkey` clip-path).
class _HexChip extends StatelessWidget {
  const _HexChip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: ClipPath(
        clipper: _HexClipper(),
        child: ColoredBox(
          color: color,
          child: Center(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexClipper extends CustomClipper<Path> {
  // polygon(50% 0, 100% 25%, 100% 75%, 50% 100%, 0 75%, 0 25%)
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * 0.5, 0)
    ..lineTo(s.width, s.height * 0.25)
    ..lineTo(s.width, s.height * 0.75)
    ..lineTo(s.width * 0.5, s.height)
    ..lineTo(0, s.height * 0.75)
    ..lineTo(0, s.height * 0.25)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.tokens,
    required this.icon,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final SearchTokens tokens;
  final IconData icon;
  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? tokens.ink : tokens.inkSoft;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? tokens.tintStrong : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: active ? tokens.edgeSoft : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 10.5,
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EscPill extends StatelessWidget {
  const _EscPill({required this.tokens, required this.onTap, required this.mobile});
  final SearchTokens tokens;
  final VoidCallback onTap;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    // On phones there's no keyboard, so keep a tappable X. On the wide (web /
    // desktop) layout show the boxed `esc` key hint instead — pressing Escape is
    // how you dismiss it there — kept tappable for mouse users.
    if (mobile) {
      return Tooltip(
        message: 'esc',
        child: IconButton(
          icon: Icon(LucideIcons.x),
          color: tokens.inkSoft,
          onPressed: onTap,
          style: ButtonStyle(
            padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 9, vertical: 4)),
          ),
        ),
      );
    }
    return Tooltip(
      message: 'esc',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: _KbdHint(tokens: tokens, text: 'esc'),
        ),
      ),
    );
  }
}

class _KbdHint extends StatelessWidget {
  const _KbdHint({required this.tokens, required this.text});
  final SearchTokens tokens;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.field,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.hairline),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontFamily: AppTheme.fontMono, fontSize: 11, color: tokens.inkSoft),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(
      {required this.tokens, required this.icon, required this.label});
  final SearchTokens tokens;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 7),
      child: Row(
        children: [
          Icon(icon, size: 13, color: tokens.inkFaint),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: tokens.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentsHead extends StatelessWidget {
  const _RecentsHead(
      {required this.tokens, required this.hasItems, required this.onClear});
  final SearchTokens tokens;
  final bool hasItems;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 7),
      child: Row(
        children: [
          Text(
            context.t('search.recent.title').toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: tokens.inkFaint,
            ),
          ),
          const Spacer(),
          if (hasItems)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: Text(
                context.t('search.recent.clear'),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.inkSoft),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyDeep extends StatelessWidget {
  const _EmptyDeep({
    required this.tokens,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final SearchTokens tokens;
  final IconData? icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 44, 20, 50),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.5,
            child: icon == null
                ? HexMark(size: 40, color: AppColors.accent)
                : Icon(icon, size: 30, color: tokens.inkFaint),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: tokens.inkSoft),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: tokens.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

class _FootHint extends StatelessWidget {
  const _FootHint(
      {required this.tokens, required this.caps, required this.label});
  final SearchTokens tokens;
  final List<String> caps;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in caps) ...[
          _Cap(tokens: tokens, text: c),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: tokens.inkSoft),
        ),
      ],
    );
  }
}

class _Cap extends StatelessWidget {
  const _Cap({required this.tokens, required this.text});
  final SearchTokens tokens;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.tintStrong,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: tokens.hairline),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontFamily: AppTheme.fontMono, fontSize: 11, color: tokens.ink),
      ),
    );
  }
}

/// Pointer-tracked radial sheen, soft-light blended (§3.6). Desktop only.
class _PointerGlare extends StatefulWidget {
  const _PointerGlare(
      {required this.color, required this.enabled, required this.child});
  final Color color;
  final bool enabled;
  final Widget child;

  @override
  State<_PointerGlare> createState() => _PointerGlareState();
}

class _PointerGlareState extends State<_PointerGlare> {
  Offset? _pos;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return MouseRegion(
      onHover: (e) => setState(() => _pos = e.localPosition),
      onExit: (_) => setState(() => _pos = null),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pos = _pos;
          return Stack(
            children: [
              widget.child,
              if (pos != null && constraints.hasBoundedWidth)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        backgroundBlendMode: BlendMode.softLight,
                        gradient: RadialGradient(
                          center: Alignment(
                            (pos.dx / constraints.maxWidth) * 2 - 1,
                            (pos.dy / constraints.maxHeight) * 2 - 1,
                          ),
                          radius: 220 / constraints.maxWidth,
                          colors: [
                            widget.color,
                            widget.color.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 1px specular rim: bright top-left → dim → bright bottom-right at 140°.
class _RimPainter extends CustomPainter {
  _RimPainter(
      {required this.radius, required this.edge, required this.edgeSoft});
  final double radius;
  final Color edge;
  final Color edgeSoft;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [edge, edgeSoft, Colors.transparent, edgeSoft],
        const [0.0, 0.28, 0.52, 1.0],
      );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.edge != edge || old.edgeSoft != edgeSoft;
}

/// Wraps matched query substrings in a highlight background (the `<mark>`).
List<InlineSpan> _highlightSpans(
    String text, String query, TextStyle base, Color markBg) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (terms.isEmpty) return [TextSpan(text: text, style: base)];
  final escaped = terms.map(RegExp.escape).join('|');
  final re = RegExp('($escaped)', caseSensitive: false);
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    spans.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: base.copyWith(backgroundColor: markBg)));
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: base));
  }
  return spans;
}
