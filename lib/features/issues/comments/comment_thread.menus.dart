part of 'comment_thread.dart';

/// The overflow menu content (inside a [GlassPopover] glass panel).
class _ContextMenuCard extends StatelessWidget {
  const _ContextMenuCard({required this.rows});
  final List<_MenuRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final r in rows) _row(context, r)],
      ),
    );
  }

  Widget _row(BuildContext context, _MenuRowData r) {
    final color = r.danger ? AppColors.danger : AppColors.ink;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: r.onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(r.icon, size: 18, color: color),
              const SizedBox(width: 12),
              Text(
                r.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The quick-reactions pill content (emoji row + "…" full picker), placed inside
/// a [GlassPopover] glass panel.
class _QuickReactionsBar extends StatelessWidget {
  const _QuickReactionsBar({
    required this.selected,
    required this.onPick,
    required this.onMore,
  });

  final String? selected;
  final void Function(String emoji) onPick;

  /// Opens the full emoji picker (anchored by the caller to the react button).
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in kQuickReactions)
          _emojiButton(e, e == selected, () => onPick(e)),
        _moreButton(context),
      ],
    );
  }

  Widget _emojiButton(String emoji, bool active, VoidCallback onTap) {
    return Material(
      color: active
          ? AppColors.accent.withValues(alpha: 0.22)
          : Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
        ),
      ),
    );
  }

  Widget _moreButton(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return Material(
      color: dark ? Colors.white10 : Colors.black12,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onMore,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(LucideIcons.ellipsis, size: 18, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

class _MenuRowData {
  _MenuRowData(this.icon, this.label, this.onTap, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// Opens the full glass emoji picker and returns the chosen emoji (or null).
/// Responsive: anchored beside the "…" button on wide layouts, docked as a glass
/// sheet on phones. The system emoji grid renders on transparent glass.
Future<String?> _pickEmojiGlass(BuildContext context, {Rect? anchor}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.14),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => _GlassEmojiOverlay(anchor: anchor),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
      child: child,
    ),
  );
}

/// Positions the glass emoji panel: anchored to [anchor] on wide screens (it
/// flips above the trigger if it would overflow below), otherwise docked to the
/// bottom of the screen as a glass sheet. A full-screen barrier dismisses it.
class _GlassEmojiOverlay extends StatelessWidget {
  const _GlassEmojiOverlay({this.anchor});
  final Rect? anchor;

  static const double _panelH = 396;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final wide = anchor != null && size.width >= 600;

    final Widget positioned;
    if (wide) {
      const w = 340.0;
      const h = _panelH;
      final a = anchor!;
      const gap = 8.0;
      final left = a.left.clamp(12.0, size.width - w - 12);
      var top = a.bottom + gap;
      if (top + h > size.height - 12) top = a.top - gap - h; // flip above
      top = top.clamp(media.padding.top + 12, size.height - h - 12);
      positioned = Positioned(
        left: left,
        top: top,
        child: _GlassEmojiPanel(
          width: w,
          height: h,
          onPick: (e) => Navigator.of(context).pop(e),
        ),
      );
    } else {
      final h = (size.height * 0.55).clamp(300.0, _panelH);
      positioned = Positioned(
        left: 10,
        // Ride above the keyboard: the emoji picker has its own search field,
        // so include viewInsets.bottom (0 when the keyboard is down, when
        // padding.bottom covers the home indicator instead).
        bottom: media.viewInsets.bottom + media.padding.bottom + 12,
        child: _GlassEmojiPanel(
          width: size.width - 20,
          height: h,
          onPick: (e) => Navigator.of(context).pop(e),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        positioned,
      ],
    );
  }
}

/// The Liquid-Glass emoji panel: the system emoji grid on a transparent
/// background so the glass shows through.
class _GlassEmojiPanel extends StatelessWidget {
  const _GlassEmojiPanel({
    required this.width,
    required this.height,
    required this.onPick,
  });

  final double width;
  final double height;
  final void Function(String emoji) onPick;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return GlassContainer(
      width: width,
      height: height,
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: _navGlass(dark),
      clipBehavior: Clip.antiAlias,
      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
      padding: const EdgeInsets.all(6),
      // EmojiPicker's search field + ink need a Material ancestor;
      // showGeneralDialog (unlike a bottom sheet) doesn't provide one.
      child: Material(
        type: MaterialType.transparency,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) => onPick(emoji.emoji),
          config: Config(
            height: height - 12,
            emojiViewConfig: const EmojiViewConfig(
              backgroundColor: Colors.transparent,
              columns: 8,
            ),
            categoryViewConfig: CategoryViewConfig(
              backgroundColor: Colors.transparent,
              indicatorColor: AppColors.accent,
              iconColorSelected: AppColors.accent,
              // Unselected category tabs — the package default (Colors.grey)
              // washes out to invisible on the light glass panel. Theme-aware
              // ink keeps them legible in both light and dark.
              iconColor: AppColors.inkSoft,
              backspaceColor: AppColors.inkSoft,
            ),
            bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
            searchViewConfig: SearchViewConfig(
              backgroundColor: dark
                  ? const Color(0x33121218)
                  : const Color(0x14000000),
              // Default buttonIconColor (Colors.black26) vanishes on dark glass —
              // theme-aware ink keeps the back/clear button visible either way.
              buttonIconColor: AppColors.inkSoft,
              hintText: context.t('comments.searchEmoji'),
            ),
          ),
        ),
      ),
    );
  }
}
