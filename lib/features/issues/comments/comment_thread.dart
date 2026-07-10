import 'dart:ui' as ui;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        GlassContainer,
        GlassQuality,
        LiquidGlassSettings,
        LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../knowledge/markdown/markdown_renderer.dart';
import 'voice/voice_player.dart';

/// The quick-reaction emojis offered above a focused bubble (before the "…"
/// opens the full device picker). Mirrors WhatsApp/iMessage.
const List<String> kQuickReactions = ['❤️', '👍', '😂', '😮', '😢', '🙏'];

/// Opaque glass for the long-press bubble menu: it floats over the feed, so —
/// like the composer — it needs a strong tint (transparent nav glass would be
/// unreadable) and, on native, the standard lightweight shader (the default
/// premium pipeline corrupts on rotation). Same lighting as [kNavGlassDark].
const _menuGlassDark = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345,
  glassColor: Color(0xD91A1A22), // ~0.85 opaque dark slate
);
const _menuGlassLight = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345,
  glassColor: Color(0xF2FFFFFF), // ~0.95 near-solid frost
);

LiquidGlassSettings _navGlass(bool dark) =>
    dark ? _menuGlassDark : _menuGlassLight;

/// The per-comment actions + directory lookups the thread needs, bundled so both
/// [CommentThread] and a single [CommentBubbleRow] (the "All" tab) share one
/// wiring. Callbacks are dispatched by the focused menu / hover affordances.
class CommentInteractions {
  const CommentInteractions({
    required this.meId,
    required this.nameFor,
    required this.avatarFor,
    required this.loadVoice,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onReply,
    required this.onReact,
    required this.onCopy,
    required this.onCopyLink,
    required this.onTogglePin,
    required this.onEnterSelection,
    required this.onJumpToComment,
  });

  final String? meId;
  final String Function(String authorId) nameFor;
  final String? Function(String authorId) avatarFor;
  final VoiceAudioLoader Function(IssueComment comment) loadVoice;

  /// Whether the signed-in user owns [comment] (edit/delete/select gate).
  final bool Function(IssueComment comment) canManage;

  final void Function(IssueComment comment) onEdit;
  final void Function(IssueComment comment) onDelete;
  final void Function(IssueComment comment) onReply;
  final void Function(IssueComment comment, String emoji) onReact;
  final void Function(IssueComment comment) onCopy;
  final void Function(IssueComment comment) onCopyLink;
  final void Function(IssueComment comment) onTogglePin;
  final void Function(IssueComment comment) onEnterSelection;
  final void Function(String commentId) onJumpToComment;
}

/// Chat-style activity feed (Liquid-Glass comment section). Text comments render
/// as bubbles; voice comments as playable waveform bubbles. Consecutive messages
/// from one author within a few minutes group WhatsApp-style (name once on top,
/// avatar once at the bottom).
///
/// Alignment is responsive: on **compact** (phone) the signed-in user's own
/// comments sit on the right (classic chat), everyone else on the left. On
/// **medium/expanded** (tablet + desktop) *every* bubble aligns left, which
/// reads more naturally in a wide column.
class CommentThread extends StatelessWidget {
  const CommentThread({
    super.key,
    required this.comments,
    required this.interactions,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onToggleSelected,
    this.highlightedId,
    this.commentKeys,
    this.pinnedSection = false,
  });

  final List<IssueComment> comments;
  final CommentInteractions interactions;

  /// Multi-select (batch delete of own comments) state.
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(IssueComment comment)? onToggleSelected;

  /// The comment currently flashing from a deep-link jump (brief highlight).
  final String? highlightedId;

  /// Per-comment keys so the host can `Scrollable.ensureVisible` a deep-linked
  /// comment. Keyed by comment id.
  final Map<String, GlobalKey>? commentKeys;

  /// True when this thread renders the pinned section (pin marker, no grouping).
  final bool pinnedSection;

  /// Whether the signed-in user's own comments sit on the right (chat style).
  /// Only on compact (phone); wide layouts left-align everything.
  static bool chatMode(BuildContext context) =>
      context.layoutSize == LayoutSize.compact;

  static const _groupWindow = Duration(minutes: 5);

  static bool _grouped(IssueComment a, IssueComment b) {
    if (a.authorId != b.authorId) return false;
    final ta = a.createdAt, tb = b.createdAt;
    if (ta == null || tb == null) return true;
    return tb.difference(ta).abs() <= _groupWindow;
  }

  @override
  Widget build(BuildContext context) {
    final chat = chatMode(context);
    final rows = <Widget>[];
    for (var idx = 0; idx < comments.length; idx++) {
      final c = comments[idx];
      // The pinned section shows each comment standalone (no grouping); the
      // chronological feed groups consecutive same-author messages.
      final prev = pinnedSection || idx == 0 ? null : comments[idx - 1];
      final next = pinnedSection || idx == comments.length - 1
          ? null
          : comments[idx + 1];
      final firstOfGroup = prev == null || !_grouped(prev, c);
      final lastOfGroup = next == null || !_grouped(c, next);
      final row = CommentBubbleRow(
        comment: c,
        interactions: interactions,
        me: chat && interactions.meId != null && c.authorId == interactions.meId,
        showName: firstOfGroup,
        showAvatar: lastOfGroup,
        tail: lastOfGroup,
        pinned: pinnedSection,
        selectionMode: selectionMode,
        selected: selectedIds.contains(c.id),
        onToggleSelected: onToggleSelected,
        highlight: highlightedId == c.id,
      );
      final key = commentKeys?[c.id];
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            top: idx == 0 ? 0 : (firstOfGroup ? 14 : 3),
          ),
          child: key == null ? row : KeyedSubtree(key: key, child: row),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// One comment in the feed (text bubble or playable voice bubble). Owns the
/// hover state (desktop affordances) and a repaint key so the pressed bubble can
/// be lifted into the focused menu.
class CommentBubbleRow extends StatefulWidget {
  const CommentBubbleRow({
    super.key,
    required this.comment,
    required this.interactions,
    required this.me,
    this.showName = true,
    this.showAvatar = true,
    this.tail = true,
    this.pinned = false,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
    this.highlight = false,
  });

  final IssueComment comment;
  final CommentInteractions interactions;
  final bool me;
  final bool showName;
  final bool showAvatar;
  final bool tail;
  final bool pinned;
  final bool selectionMode;
  final bool selected;
  final void Function(IssueComment comment)? onToggleSelected;
  final bool highlight;

  @override
  State<CommentBubbleRow> createState() => _CommentBubbleRowState();
}

class _CommentBubbleRowState extends State<CommentBubbleRow> {
  final GlobalKey _bubbleKey = GlobalKey();
  bool _hovered = false;

  IssueComment get _c => widget.comment;
  CommentInteractions get _x => widget.interactions;
  bool get _canManage => _x.canManage(_c);

  @override
  Widget build(BuildContext context) {
    final compact = CommentThread.chatMode(context);
    final me = widget.me;
    final name = _x.nameFor(_c.authorId);

    final avatar = widget.showAvatar
        ? HiveAvatar(name: name, imageUrl: _x.avatarFor(_c.authorId), size: 30)
        : const SizedBox(width: 30);

    Widget bubble = RepaintBoundary(
      key: _bubbleKey,
      child: _Bubble(
        comment: _c,
        me: me,
        tail: widget.tail,
        pinned: widget.pinned,
        loadVoice: _x.loadVoice(_c),
        replyAuthorName: _c.replyToAuthorId != null
            ? _x.nameFor(_c.replyToAuthorId!)
            : null,
        onTapReply: _c.isReply
            ? () => _x.onJumpToComment(_c.replyToId!)
            : null,
        highlight: widget.highlight,
      ),
    );

    // Gestures: the focused (lifted-bubble) menu is a MOBILE affordance — only a
    // long-press on compact layouts opens it. On wide layouts the hover action
    // buttons (chevron menu + quick-react) replace it, so long-press is off there.
    // Right-click still opens it everywhere (a deliberate desktop context-menu
    // gesture, and the only menu path for pinned rows, which have no hover
    // buttons). A tap in selection mode toggles the checkbox.
    bubble = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.selectionMode && _canManage
          ? () => widget.onToggleSelected?.call(_c)
          : null,
      onLongPress: (compact && !widget.selectionMode)
          ? () => _openFocusedMenu(context)
          : null,
      onSecondaryTapDown: widget.selectionMode
          ? null
          : (_) => _openFocusedMenu(context),
      child: bubble,
    );

    // Reaction chips sit just under the bubble, aligned to its side.
    final column = Flexible(
      child: Column(
        crossAxisAlignment: me
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (widget.showName && !me && !widget.pinned)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          bubble,
          if (_c.reactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _ReactionChips(
                comment: _c,
                meId: _x.meId,
                onTap: (emoji) => _x.onReact(_c, emoji),
              ),
            ),
        ],
      ),
    );

    final children = me
        ? [column, const SizedBox(width: 9), avatar]
        : [avatar, const SizedBox(width: 9), column];

    Widget row = Row(
      mainAxisAlignment: me ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: children,
    );

    // Selection checkbox for own comments in selection mode.
    if (widget.selectionMode) {
      row = Row(
        children: [
          if (_canManage)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SelectDot(selected: widget.selected),
            )
          else
            const SizedBox(width: 30),
          Expanded(child: row),
        ],
      );
    } else if (!compact && !widget.pinned) {
      // Desktop/web: reveal hover affordances (chevron menu + quick-react button)
      // beside the bubble instead of the mobile long-press.
      row = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: _HoverAffordances(
          me: me,
          show: _hovered,
          onOpenMenu: () => _openDesktopMenu(context),
          onQuickReact: () => _openDesktopReactions(context),
          child: row,
        ),
      );
    }

    return row;
  }

  // ── focused (mobile) menu ──────────────────────────────────────────────────
  Future<void> _openFocusedMenu(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final captured = await _captureBubble();
    if (!context.mounted || captured == null) return;
    await showFocusedCommentMenu(
      context,
      comment: _c,
      interactions: _x,
      me: widget.me,
      canManage: _canManage,
      bubbleRect: captured.rect,
      bubbleImage: captured.image,
      showQuickReactions: true,
    );
  }

  // ── desktop popovers ───────────────────────────────────────────────────────
  Future<void> _openDesktopMenu(BuildContext context) async {
    final rect = _bubbleGlobalRect();
    if (rect == null) return;
    await showFocusedCommentMenu(
      context,
      comment: _c,
      interactions: _x,
      me: widget.me,
      canManage: _canManage,
      bubbleRect: rect,
      bubbleImage: null,
      showQuickReactions: false,
    );
  }

  Future<void> _openDesktopReactions(BuildContext context) async {
    final rect = _bubbleGlobalRect();
    if (rect == null) return;
    await showFocusedCommentMenu(
      context,
      comment: _c,
      interactions: _x,
      me: widget.me,
      canManage: _canManage,
      bubbleRect: rect,
      bubbleImage: null,
      showQuickReactions: true,
      showMenu: false,
    );
  }

  Rect? _bubbleGlobalRect() {
    final box = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Snapshots the bubble to a [ui.Image] so it can be lifted above the blurred
  /// backdrop in the focused menu (iOS-style). Null if it can't be captured.
  Future<({ui.Image image, Rect rect})?> _captureBubble() async {
    final ctx = _bubbleKey.currentContext;
    final obj = ctx?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return null;
    try {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final image = await obj.toImage(pixelRatio: dpr);
      final rect = obj.localToGlobal(Offset.zero) & obj.size;
      return (image: image, rect: rect);
    } catch (_) {
      return null;
    }
  }
}

/// The circular selection indicator shown on own comments in selection mode.
class _SelectDot extends StatelessWidget {
  const _SelectDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? AppColors.accent : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.hairline,
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(LucideIcons.check, size: 13, color: Color(0xFF2A2410))
          : null,
    );
  }
}

/// Reaction chips (emoji + count) shown under a bubble. The user's own reaction
/// is tinted; tapping a chip toggles it.
class _ReactionChips extends StatelessWidget {
  const _ReactionChips({
    required this.comment,
    required this.meId,
    required this.onTap,
  });

  final IssueComment comment;
  final String? meId;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final mine = comment.myReaction(meId);
    final counts = comment.reactionCounts;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final entry in counts.entries)
          _chip(
            emoji: entry.key,
            count: entry.value,
            selected: entry.key == mine,
            dark: dark,
          ),
      ],
    );
  }

  Widget _chip({
    required String emoji,
    required int count,
    required bool selected,
    required bool dark,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: () => onTap(emoji),
        customBorder: const StadiumBorder(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: dark ? 0.26 : 0.18)
                : (dark ? const Color(0xFF23222F) : AppColors.surface),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.accentLine : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              if (count > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.accentStrong : AppColors.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Desktop/web hover affordances: a chevron button (opens the context menu) and
/// a quick-react button (opens the emoji bar) that fade in beside the bubble on
/// mouse hover. Positioned via an overlay Stack so they don't shift the row.
class _HoverAffordances extends StatelessWidget {
  const _HoverAffordances({
    required this.me,
    required this.show,
    required this.onOpenMenu,
    required this.onQuickReact,
    required this.child,
  });

  final bool me;
  final bool show;
  final VoidCallback onOpenMenu;
  final VoidCallback onQuickReact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Buttons sit on the trailing side of the bubble (right for others, left for
    // the user's own right-aligned bubbles).
    final buttons = AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: show ? 1 : 0,
      child: IgnorePointer(
        ignoring: !show,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HoverButton(
              icon: LucideIcons.smilePlus,
              tooltip: context.t('comments.react'),
              onTap: onQuickReact,
            ),
            const SizedBox(width: 4),
            _HoverButton(
              icon: LucideIcons.chevronDown,
              tooltip: context.t('comments.more'),
              onTap: onOpenMenu,
            ),
          ],
        ),
      ),
    );
    return Row(
      mainAxisAlignment: me ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: me
          ? [buttons, const SizedBox(width: 6), Flexible(child: child)]
          : [Flexible(child: child), const SizedBox(width: 6), buttons],
    );
  }
}

class _HoverButton extends StatelessWidget {
  const _HoverButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: dark ? const Color(0xFF23222F) : AppColors.surface,
        shape: CircleBorder(side: BorderSide(color: AppColors.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: AppColors.accent.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: AppColors.inkSoft),
          ),
        ),
      ),
    );
  }
}

/// A single comment bubble (text or voice), with an optional reply quote at the
/// top and a deep-link highlight flash.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.comment,
    required this.me,
    required this.tail,
    required this.pinned,
    required this.loadVoice,
    required this.replyAuthorName,
    required this.onTapReply,
    required this.highlight,
  });

  final IssueComment comment;
  final bool me;
  final bool tail;
  final bool pinned;
  final VoiceAudioLoader loadVoice;
  final String? replyAuthorName;
  final VoidCallback? onTapReply;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final bg = me
        ? (dark ? const Color(0xFF322C46) : const Color(0xFFEFEBF8))
        : (dark ? const Color(0xFF23222F) : AppColors.surface);
    final borderColor = me
        ? (dark ? const Color(0x40A98BFF) : const Color(0xFFDED6F2))
        : AppColors.hairline;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(!me && tail ? 5 : 16),
      bottomRight: Radius.circular(me && tail ? 5 : 16),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pinned)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.pin, size: 11, color: AppColors.accentStrong),
                const SizedBox(width: 4),
                Text(
                  context.t('comments.pinnedSection'),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: AppColors.accentStrong,
                  ),
                ),
              ],
            ),
          ),
        if (comment.isReply)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ReplyQuote(
              authorName: replyAuthorName ?? '',
              preview: comment.replyToPreview ?? '',
              onTap: onTapReply,
            ),
          ),
        comment.isVoice
            ? VoiceBubble(
                voice: comment.voice!,
                me: me,
                loader: loadVoice,
                createdAt: comment.createdAt,
              )
            : _TextBody(comment: comment, me: me),
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        decoration: BoxDecoration(
          color: highlight ? AppColors.accent.withValues(alpha: 0.22) : bg,
          borderRadius: radius,
          border: Border.all(
            color: highlight ? AppColors.accent : borderColor,
          ),
        ),
        padding: comment.isVoice
            ? const EdgeInsets.fromLTRB(8, 8, 12, 8)
            : const EdgeInsets.fromLTRB(13, 9, 13, 8),
        child: content,
      ),
    );
  }
}

/// A WhatsApp-style quoted reply header inside a bubble: an accent rule, the
/// replied-to author, and a one-line preview. Tapping jumps to the parent.
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.authorName,
    required this.preview,
    required this.onTap,
  });

  final String authorName;
  final String preview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          decoration: BoxDecoration(
            color: dark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(7),
            border: Border(
              left: BorderSide(color: AppColors.accent, width: 3),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                authorName,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentStrong,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── focused comment menu (iOS-style) ──────────────────────────────────────────

/// Opens the focused comment menu: a blurred, dimmed backdrop with the pressed
/// bubble lifted above it, a quick-reactions pill on top and the action menu
/// below. On desktop [bubbleImage] is null (no lift) and this is used as a plain
/// anchored popover; [showMenu]/[showQuickReactions] pick which parts appear.
Future<void> showFocusedCommentMenu(
  BuildContext context, {
  required IssueComment comment,
  required CommentInteractions interactions,
  required bool me,
  required bool canManage,
  required Rect bubbleRect,
  required ui.Image? bubbleImage,
  bool showQuickReactions = true,
  bool showMenu = true,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: bubbleImage != null ? 0.28 : 0.12),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => _FocusedCommentMenu(
      comment: comment,
      interactions: interactions,
      me: me,
      canManage: canManage,
      bubbleRect: bubbleRect,
      bubbleImage: bubbleImage,
      showQuickReactions: showQuickReactions,
      showMenu: showMenu,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

class _FocusedCommentMenu extends StatelessWidget {
  const _FocusedCommentMenu({
    required this.comment,
    required this.interactions,
    required this.me,
    required this.canManage,
    required this.bubbleRect,
    required this.bubbleImage,
    required this.showQuickReactions,
    required this.showMenu,
  });

  final IssueComment comment;
  final CommentInteractions interactions;
  final bool me;
  final bool canManage;
  final Rect bubbleRect;
  final ui.Image? bubbleImage;
  final bool showQuickReactions;
  final bool showMenu;

  static const double _menuWidth = 236;
  static const double _pillHeight = 54;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top + 12;
    final safeBottom = media.size.height - media.padding.bottom - 12;

    final rowCount = _menuRows(context).length;
    final menuHeight = showMenu ? rowCount * 46.0 + 12 : 0.0;
    final pillH = showQuickReactions ? _pillHeight + _gap : 0.0;
    final belowH = showMenu ? menuHeight + _gap : 0.0;

    // Shift the whole cluster vertically so the pill (above) and menu (below)
    // both fit on screen, keeping the bubble as close to its origin as possible.
    var bubbleTop = bubbleRect.top;
    final clusterTop = bubbleTop - pillH;
    if (clusterTop < safeTop) bubbleTop += safeTop - clusterTop;
    final clusterBottom = bubbleTop + bubbleRect.height + belowH;
    if (clusterBottom > safeBottom) bubbleTop -= clusterBottom - safeBottom;
    // Guard against a bubble taller than the space left for pill + menu (clamp
    // asserts when its bounds cross); pin to just below the pill in that case.
    final lower = safeTop + pillH;
    final upper = safeBottom - belowH - bubbleRect.height;
    bubbleTop = upper >= lower ? bubbleTop.clamp(lower, upper) : lower;

    // Horizontal anchor: align the menu/pill to the bubble's leading side.
    double leftFor(double width) {
      var left = me ? bubbleRect.right - width : bubbleRect.left;
      left = left.clamp(12.0, media.size.width - 12 - width);
      return left;
    }

    final children = <Widget>[];

    if (showQuickReactions) {
      children.add(
        Positioned(
          top: bubbleTop - pillH,
          left: leftFor(_pillWidth()),
          child: _QuickReactionsBar(
            selected: comment.myReaction(interactions.meId),
            onPick: (emoji) {
              Navigator.of(context).pop();
              interactions.onReact(comment, emoji);
            },
            onMore: () async {
              final picked = await _pickEmoji(context);
              if (picked != null && context.mounted) {
                Navigator.of(context).pop();
                interactions.onReact(comment, picked);
              }
            },
          ),
        ),
      );
    }

    // The lifted bubble (mobile) or a spacer at the original spot (desktop).
    if (bubbleImage != null) {
      children.add(
        Positioned(
          top: bubbleTop,
          left: bubbleRect.left,
          width: bubbleRect.width,
          height: bubbleRect.height,
          child: IgnorePointer(
            child: RawImage(
              image: bubbleImage,
              width: bubbleRect.width,
              height: bubbleRect.height,
            ),
          ),
        ),
      );
    }

    if (showMenu) {
      children.add(
        Positioned(
          top: bubbleTop + bubbleRect.height + _gap,
          left: leftFor(_menuWidth),
          child: _ContextMenuCard(rows: _menuRows(context)),
        ),
      );
    }

    return Stack(
      children: [
        // Blurred, tappable backdrop (mobile lifts the bubble → stronger blur).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: bubbleImage != null ? 14 : 3,
                sigmaY: bubbleImage != null ? 14 : 3,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  double _pillWidth() {
    // 6 emojis + "…" button, each ~40 wide, plus padding.
    return (kQuickReactions.length + 1) * 40 + 12;
  }

  List<_MenuRowData> _menuRows(BuildContext context) {
    final isVoice = comment.isVoice;
    return [
      _MenuRowData(
        LucideIcons.reply,
        context.t('comments.reply'),
        () => interactions.onReply(comment),
      ),
      if (!isVoice)
        _MenuRowData(
          LucideIcons.copy,
          context.t('comments.copy'),
          () => interactions.onCopy(comment),
        ),
      if (canManage)
        _MenuRowData(
          LucideIcons.circleCheck,
          context.t('comments.select'),
          () => interactions.onEnterSelection(comment),
        ),
      if (canManage && !isVoice)
        _MenuRowData(
          LucideIcons.pencil,
          context.t('common.edit'),
          () => interactions.onEdit(comment),
        ),
      _MenuRowData(
        LucideIcons.link,
        context.t('comments.copyLink'),
        () => interactions.onCopyLink(comment),
      ),
      _MenuRowData(
        comment.pinned ? LucideIcons.pinOff : LucideIcons.pin,
        comment.pinned ? context.t('comments.unpin') : context.t('comments.pin'),
        () => interactions.onTogglePin(comment),
      ),
      if (canManage)
        _MenuRowData(
          LucideIcons.trash2,
          context.t('common.delete'),
          () => interactions.onDelete(comment),
          danger: true,
        ),
    ];
  }
}

/// The quick-reactions pill (emoji row + "…" for the full picker).
class _QuickReactionsBar extends StatelessWidget {
  const _QuickReactionsBar({
    required this.selected,
    required this.onPick,
    required this.onMore,
  });

  final String? selected;
  final void Function(String emoji) onPick;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: _navGlass(dark),
      clipBehavior: Clip.antiAlias,
      shape: const LiquidRoundedSuperellipse(borderRadius: 27),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in kQuickReactions)
            _emojiButton(e, e == selected, () => onPick(e)),
          _moreButton(context),
        ],
      ),
    );
  }

  Widget _emojiButton(String emoji, bool active, VoidCallback onTap) {
    return Material(
      color: active ? AppColors.accent.withValues(alpha: 0.22) : Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
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

/// The Liquid-Glass context menu card below a focused bubble.
class _ContextMenuCard extends StatelessWidget {
  const _ContextMenuCard({required this.rows});
  final List<_MenuRowData> rows;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return GlassContainer(
      width: _FocusedCommentMenu._menuWidth,
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: _navGlass(dark),
      clipBehavior: Clip.antiAlias,
      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in rows)
              _row(context, r),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _MenuRowData r) {
    final color = r.danger ? AppColors.danger : AppColors.ink;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          r.onTap();
        },
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

/// Opens the device emoji picker (system emoji font) and returns the chosen
/// emoji, or null if dismissed.
Future<String?> _pickEmoji(BuildContext context) {
  final dark = AppColors.brightness == Brightness.dark;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: dark ? const Color(0xFF1A1A22) : Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.42,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) =>
            Navigator.of(ctx).pop(emoji.emoji),
        config: Config(
          height: MediaQuery.of(ctx).size.height * 0.42,
          emojiViewConfig: EmojiViewConfig(
            backgroundColor: dark ? const Color(0xFF1A1A22) : Colors.white,
            columns: 8,
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: dark ? const Color(0xFF1A1A22) : Colors.white,
            indicatorColor: AppColors.accent,
            iconColorSelected: AppColors.accent,
          ),
          bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
          searchViewConfig: SearchViewConfig(
            backgroundColor: dark ? const Color(0xFF23222F) : Colors.white,
          ),
        ),
      ),
    ),
  );
}

/// Text comment body — rendered through the shared Markdown parser so mentions,
/// smart-links and inline images keep working inside the bubble.
///
/// For the common case (a single plain paragraph) the time flows *inline* after
/// the text — WhatsApp-style — so short messages stay one line tall instead of
/// spending a whole extra row on the timestamp. Rich content (headings, lists,
/// code, tables, images) falls back to block layout with the time tucked under.
class _TextBody extends StatelessWidget {
  const _TextBody({required this.comment, required this.me});

  final IssueComment comment;
  final bool me;

  /// Matches any line that opens a block-level markdown construct.
  static final _blockLine = RegExp(
    r'^(#{1,6}\s|```|>\s?|\s*\|.*\||:::|(-{3,}|\*{3,}|_{3,})\s*$|(\s*([-*+]|\d+\.)\s+))',
  );
  static final _image = RegExp(r'!\[[^\]]*\]\([^)]+\)');

  /// True when the body is a single paragraph with no block-level markdown —
  /// safe to render as one inline run with a trailing timestamp.
  bool get _inlineOnly {
    if (_image.hasMatch(comment.text)) return false;
    final lines = comment.text.replaceAll('\r\n', '\n').split('\n');
    var sawText = false;
    var sawBlank = false;
    for (final l in lines) {
      if (l.trim().isEmpty) {
        if (sawText) sawBlank = true;
        continue;
      }
      if (sawBlank) return false; // a second paragraph → treat as block
      if (_blockLine.hasMatch(l)) return false;
      sawText = true;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final meta = _MetaLine(
      createdAt: comment.createdAt,
      me: me,
      edited: comment.isEdited,
    );

    if (_inlineOnly) {
      final parser = KbMarkdownParser(fontSize: 14);
      final base = parser.baseStyle.copyWith(height: 1.32);
      // Collapse the soft-wrapped paragraph into one line-flow (same as the
      // block parser) so the trailing time wraps naturally with the text.
      final body = comment.text
          .replaceAll('\r\n', '\n')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .join(' ');
      return Text.rich(
        TextSpan(
          children: [
            parser.inlineFor(body, base),
            WidgetSpan(
              alignment: PlaceholderAlignment.bottom,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: meta,
              ),
            ),
          ],
        ),
      );
    }

    final nodes = KbMarkdownParser(fontSize: 14).parse(comment.text).nodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...nodes,
        const SizedBox(height: 2),
        meta,
      ],
    );
  }
}

/// Time + optional "edited" marker + read tick, right-aligned under a bubble.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.createdAt,
    required this.me,
    this.edited = false,
  });

  final DateTime? createdAt;
  final bool me;
  final bool edited;

  @override
  Widget build(BuildContext context) {
    final color = me ? AppColors.accentStrong : AppColors.inkFaint;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (edited) ...[
          Text(
            context.t('issues.commentEdited'),
            style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint),
          ),
          const SizedBox(width: 5),
        ],
        Text(hhmm(createdAt), style: TextStyle(fontSize: 10.5, color: color)),
      ],
    );
  }
}

/// A playable voice message: amber play/pause, tappable/scrubbable waveform and
/// a live-updating timecode. Audio is fetched lazily on first play.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({
    super.key,
    required this.voice,
    required this.me,
    required this.loader,
    required this.createdAt,
  });

  final CommentVoice voice;
  final bool me;
  final VoiceAudioLoader loader;
  final DateTime? createdAt;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  late final VoicePlaybackController _controller = VoicePlaybackController(
    loader: widget.loader,
    fallbackDuration: widget.voice.duration,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _mmss(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final playing = _controller.playing;
        final loading = _controller.loading;
        final elapsed = _controller.position.inMilliseconds > 0
            ? _controller.position
            : Duration.zero;
        final total = _controller.duration;
        return SizedBox(
          width: 210,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _PlayButton(
                    playing: playing,
                    loading: loading,
                    failed: _controller.failed,
                    onTap: _controller.toggle,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 30,
                          child: _Waveform(
                            peaks: widget.voice.peaks,
                            progress: _controller.progress,
                            onSeek: _controller.seekFraction,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _mmss(
                                playing || elapsed > Duration.zero
                                    ? elapsed
                                    : total,
                              ),
                              style: TextStyle(
                                fontFamily: AppTheme.fontMono,
                                fontSize: 10.5,
                                color: AppColors.inkFaint,
                              ),
                            ),
                            Text(
                              _mmss(total),
                              style: TextStyle(
                                fontFamily: AppTheme.fontMono,
                                fontSize: 10.5,
                                color: AppColors.inkFaint,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              _MetaLine(createdAt: widget.createdAt, me: widget.me),
            ],
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.failed,
    required this.onTap,
  });

  final bool playing;
  final bool loading;
  final bool failed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF2A2410),
                  ),
                )
              : Icon(
                  failed
                      ? LucideIcons.rotateCw
                      : (playing ? LucideIcons.pause : LucideIcons.play),
                  size: 18,
                  color: const Color(0xFF2A2410),
                ),
        ),
      ),
    );
  }
}

/// Waveform bars: amber up to [progress], muted after; tap or drag to scrub.
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.peaks,
    required this.progress,
    required this.onSeek,
  });

  final List<int> peaks;
  final double progress;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final idle = dark ? const Color(0x3DFFFFFF) : const Color(0x33000000);
    final bars = peaks.isEmpty ? List<int>.filled(36, 30) : peaks;
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekAt(double dx) =>
            onSeek((dx / constraints.maxWidth).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekAt(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < bars.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.8),
                    child: Container(
                      height: (4 + bars[i] / 100 * 26).clamp(4, 30).toDouble(),
                      decoration: BoxDecoration(
                        color: (i + 0.5) / bars.length <= progress
                            ? AppColors.accent
                            : idle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Local time as `HH:mm` (24h). Comments store UTC; display in the device zone.
String hhmm(DateTime? dt) {
  if (dt == null) return '';
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
