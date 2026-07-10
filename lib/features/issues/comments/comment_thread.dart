import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassMenuAlignment, GlassPopover, GlassQuality, LiquidGlassSettings;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../knowledge/markdown/markdown_renderer.dart';
import 'voice/voice_player.dart';

/// The quick-reaction emojis offered by the reaction popover (before the "…"
/// opens the full device picker). Mirrors WhatsApp/iMessage.
const List<String> kQuickReactions = ['❤️', '👍', '😂', '😮', '😢', '🙏'];

/// Opaque glass for the reaction/menu popovers: they float over the feed, so —
/// like the composer — they need a strong tint (transparent nav glass would be
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

/// How top-level comments are ordered. Reply threads are *always* oldest-first,
/// independent of this.
enum CommentSort {
  newest,
  oldest;

  /// The `sort` query value the backend expects.
  String get api => this == CommentSort.oldest ? 'oldest' : 'newest';
}

/// Compact "Newest first ▾" selector that opens a two-option glass popover.
class CommentSortButton extends StatelessWidget {
  const CommentSortButton({
    super.key,
    required this.sort,
    required this.onChanged,
  });

  final CommentSort sort;
  final ValueChanged<CommentSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final label = sort == CommentSort.newest
        ? context.t('comments.sortNewest')
        : context.t('comments.sortOldest');
    return GlassPopover(
      alignment: GlassMenuAlignment.bottomRight,
      popoverWidth: 200,
      popoverBorderRadius: 18,
      settings: _navGlass(dark),
      quality: GlassQuality.standard,
      triggerBuilder: (context, toggle) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: toggle,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.arrowUpDown,
                  size: 14,
                  color: AppColors.inkSoft,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  LucideIcons.chevronDown,
                  size: 14,
                  color: AppColors.inkSoft,
                ),
              ],
            ),
          ),
        ),
      ),
      contentBuilder: (context, close) => _ContextMenuCard(
        rows: [
          _MenuRowData(
            sort == CommentSort.newest
                ? LucideIcons.check
                : LucideIcons.arrowDown,
            context.t('comments.sortNewest'),
            () {
              close();
              onChanged(CommentSort.newest);
            },
          ),
          _MenuRowData(
            sort == CommentSort.oldest
                ? LucideIcons.check
                : LucideIcons.arrowUp,
            context.t('comments.sortOldest'),
            () {
              close();
              onChanged(CommentSort.oldest);
            },
          ),
        ],
      ),
    );
  }
}

/// View-state of one root comment's (lazily loaded) reply thread. Owned by the
/// issue sheet and handed to the thread via [CommentInteractions.threadOf].
class ReplyThread {
  const ReplyThread({
    this.expanded = false,
    this.loading = false,
    this.replies = const [],
    this.total = 0,
  });

  /// Whether the thread is currently unfolded.
  final bool expanded;

  /// Whether a page of replies is in flight.
  final bool loading;

  /// Loaded replies, oldest-first (newest at the bottom).
  final List<IssueComment> replies;

  /// Total replies on the backend (known once a page has loaded).
  final int total;

  /// More older-than-loaded… no — more *newer* replies remain to page in.
  bool get hasMore => replies.length < total;

  ReplyThread copyWith({
    bool? expanded,
    bool? loading,
    List<IssueComment>? replies,
    int? total,
  }) => ReplyThread(
    expanded: expanded ?? this.expanded,
    loading: loading ?? this.loading,
    replies: replies ?? this.replies,
    total: total ?? this.total,
  );
}

/// The per-comment actions + directory lookups the thread needs, bundled so both
/// [CommentThread] and a single [CommentBubbleRow] (the "All" tab) share one
/// wiring. Callbacks are dispatched by the persistent action row + popovers.
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
    required this.threadOf,
    required this.onToggleReplies,
    required this.onLoadMoreReplies,
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

  /// The reply-thread view-state for a root comment (empty if never expanded).
  final ReplyThread Function(String rootId) threadOf;

  /// Expand (loading the first page) / collapse a root's reply thread.
  final void Function(IssueComment root) onToggleReplies;

  /// Load the next page of a root's replies.
  final void Function(IssueComment root) onLoadMoreReplies;
}

/// Jira-style comment feed (flat text, always left-aligned). Each top-level
/// comment renders a header (author · date), its body, reactions and a
/// persistent action row, followed by its own collapsible reply thread.
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

  /// Comment to flash (deep-link / reply-jump highlight).
  final String? highlightedId;

  /// Stable keys per comment id so a jump can scroll to a specific row.
  final Map<String, GlobalKey>? commentKeys;

  /// The pinned section renders each comment standalone (no reply threads).
  final bool pinnedSection;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var idx = 0; idx < comments.length; idx++) {
      final c = comments[idx];
      final hasThread = !pinnedSection && c.isRoot;
      final thread = hasThread
          ? interactions.threadOf(c.id)
          : const ReplyThread();
      final row = CommentBubbleRow(
        comment: c,
        interactions: interactions,
        pinned: pinnedSection,
        selectionMode: selectionMode,
        selected: selectedIds.contains(c.id),
        onToggleSelected: onToggleSelected,
        highlight: highlightedId == c.id,
        trunkBelow: thread.expanded && thread.replies.isNotEmpty,
      );
      final key = commentKeys?[c.id];
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: idx == 0 ? 0 : 18),
          child: key == null ? row : KeyedSubtree(key: key, child: row),
        ),
      );
      // A root comment carries its own flat reply thread (never in the pinned
      // section, and never for a reply row).
      if (hasThread) {
        rows.add(
          _ReplyThreadView(
            root: c,
            interactions: interactions,
            selectionMode: selectionMode,
            selectedIds: selectedIds,
            onToggleSelected: onToggleSelected,
            highlightedId: highlightedId,
            commentKeys: commentKeys,
          ),
        );
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// One comment in the feed — flat text (or a playable voice bubble) on a
/// transparent background, always left-aligned: avatar, an author · date header,
/// the body, reaction chips and a persistent action row (Reply · react · more).
class CommentBubbleRow extends StatelessWidget {
  const CommentBubbleRow({
    super.key,
    required this.comment,
    required this.interactions,
    this.isReply = false,
    this.pinned = false,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
    this.highlight = false,
    this.trunkBelow = false,
  });

  final IssueComment comment;
  final CommentInteractions interactions;

  /// A reply row: a smaller avatar and no reply-thread of its own.
  final bool isReply;
  final bool pinned;
  final bool selectionMode;
  final bool selected;
  final void Function(IssueComment comment)? onToggleSelected;
  final bool highlight;

  /// Draw a "main branch" line down from this (root) comment's avatar to its
  /// reply thread below — set when the thread is expanded with replies.
  final bool trunkBelow;

  IssueComment get _c => comment;
  CommentInteractions get _x => interactions;
  bool get _canManage => _x.canManage(_c);

  @override
  Widget build(BuildContext context) {
    final avatarSize = isReply ? 26.0 : 32.0;
    final name = _x.nameFor(_c.authorId);

    final leading = selectionMode
        ? (_canManage
              ? Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: _SelectDot(selected: selected),
                )
              : SizedBox(width: avatarSize))
        : HiveAvatar(
            name: name,
            imageUrl: _x.avatarFor(_c.authorId),
            size: avatarSize,
          );

    final body = _c.isVoice
        ? VoiceBubble(voice: _c.voice!, loader: _x.loadVoice(_c))
        : _TextBody(comment: _c);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context, name),
        const SizedBox(height: 5),
        // A subtle wash flashes the row on a deep-link / reply jump.
        AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          decoration: BoxDecoration(
            color: highlight
                ? AppColors.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: body,
        ),
        if (_c.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: _ReactionChips(
              comment: _c,
              meId: _x.meId,
              onTap: (emoji) => _x.onReact(_c, emoji),
            ),
          ),
        if (!selectionMode) ...[
          const SizedBox(height: 3),
          _CommentActions(comment: _c, interactions: _x, canManage: _canManage),
        ],
      ],
    );

    Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading,
        const SizedBox(width: 10),
        Expanded(child: content),
      ],
    );

    // A root with visible replies grows a vertical "main branch" line from just
    // below its 32px avatar (centre x = 16) down to the reply thread; the reply
    // rows continue it at the same x. Painted in a Stack so no IntrinsicHeight
    // is needed — the Positioned line stretches to the row's height.
    if (trunkBelow) {
      row = Stack(
        children: [
          row,
          Positioned(
            left: 15.25, // 32/2 − half of the 1.5px stroke
            top: 35, // just below the 32px avatar
            bottom: 0,
            child: Container(width: 1.5, color: AppColors.hairline),
          ),
        ],
      );
    }

    // In selection mode the whole row toggles the checkbox for own comments.
    if (selectionMode && _canManage) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onToggleSelected?.call(_c),
        child: row,
      );
    }
    return row;
  }

  Widget _header(BuildContext context, String name) {
    final dt = _c.createdAt?.toLocal();
    final when = dt == null
        ? ''
        : '${MaterialLocalizations.of(context).formatMediumDate(dt)} '
              '${context.t('comments.at')} ${hhmm(dt)}';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 7,
      children: [
        if (pinned)
          Icon(LucideIcons.pin, size: 12, color: AppColors.accentStrong),
        Text(
          name,
          style: TextStyle(
            fontSize: isReply ? 12.5 : 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        if (when.isNotEmpty)
          Text(
            when,
            style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
          ),
        if (_c.isEdited)
          Text(
            '· ${context.t('issues.commentEdited')}',
            style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
          ),
      ],
    );
  }
}

/// The persistent action row under a comment: Reply, a reaction popover and a
/// "more" popover (edit/copy/pin/…). Left-aligned to the body on every platform.
class _CommentActions extends StatelessWidget {
  const _CommentActions({
    required this.comment,
    required this.interactions,
    required this.canManage,
  });

  final IssueComment comment;
  final CommentInteractions interactions;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: LucideIcons.reply,
          label: context.t('comments.reply'),
          onTap: () => interactions.onReply(comment),
        ),
        const SizedBox(width: 2),
        // Quick reactions (emoji row + "…" for the full picker).
        GlassPopover(
          alignment: GlassMenuAlignment.topLeft,
          popoverWidth: (kQuickReactions.length + 1) * 40 + 12,
          popoverBorderRadius: 27,
          settings: _navGlass(dark),
          quality: GlassQuality.standard,
          triggerBuilder: (context, toggle) => _ActionButton(
            icon: LucideIcons.smilePlus,
            tooltip: context.t('comments.react'),
            onTap: toggle,
          ),
          contentBuilder: (context, close) => _QuickReactionsBar(
            selected: comment.myReaction(interactions.meId),
            onPick: (emoji) {
              close();
              interactions.onReact(comment, emoji);
            },
            onMore: () async {
              final picked = await _pickEmoji(context);
              if (picked != null && context.mounted) {
                close();
                interactions.onReact(comment, picked);
              }
            },
          ),
        ),
        const SizedBox(width: 2),
        // Overflow menu.
        GlassPopover(
          alignment: GlassMenuAlignment.topLeft,
          popoverWidth: 236,
          popoverBorderRadius: 22,
          settings: _navGlass(dark),
          quality: GlassQuality.standard,
          triggerBuilder: (context, toggle) => _ActionButton(
            icon: LucideIcons.chevronDown,
            tooltip: context.t('comments.more'),
            onTap: toggle,
          ),
          contentBuilder: (context, close) =>
              _ContextMenuCard(rows: _menuRows(context, close)),
        ),
      ],
    );
  }

  List<_MenuRowData> _menuRows(BuildContext context, VoidCallback close) {
    final isVoice = comment.isVoice;
    void run(void Function() action) {
      close();
      action();
    }

    return [
      _MenuRowData(
        LucideIcons.reply,
        context.t('comments.reply'),
        () => run(() => interactions.onReply(comment)),
      ),
      if (!isVoice)
        _MenuRowData(
          LucideIcons.copy,
          context.t('comments.copy'),
          () => run(() => interactions.onCopy(comment)),
        ),
      if (canManage)
        _MenuRowData(
          LucideIcons.circleCheck,
          context.t('comments.select'),
          () => run(() => interactions.onEnterSelection(comment)),
        ),
      if (canManage && !isVoice)
        _MenuRowData(
          LucideIcons.pencil,
          context.t('common.edit'),
          () => run(() => interactions.onEdit(comment)),
        ),
      _MenuRowData(
        LucideIcons.link,
        context.t('comments.copyLink'),
        () => run(() => interactions.onCopyLink(comment)),
      ),
      _MenuRowData(
        comment.pinned ? LucideIcons.pinOff : LucideIcons.pin,
        comment.pinned ? context.t('comments.unpin') : context.t('comments.pin'),
        () => run(() => interactions.onTogglePin(comment)),
      ),
      if (canManage)
        _MenuRowData(
          LucideIcons.trash2,
          context.t('common.delete'),
          () => run(() => interactions.onDelete(comment)),
          danger: true,
        ),
    ];
  }
}

/// A compact text/icon action button (Reply) or icon-only button (react/more).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: AppColors.accent.withValues(alpha: 0.10),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label != null ? 8 : 6,
            vertical: 5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.inkSoft),
              if (label != null) ...[
                const SizedBox(width: 5),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// The collapsible reply thread under a root comment: a "show replies (N)"
/// affordance, then the flat replies (oldest-first) with connector lines, a
/// "load more" control and a "hide replies" control.
class _ReplyThreadView extends StatelessWidget {
  const _ReplyThreadView({
    required this.root,
    required this.interactions,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelected,
    required this.highlightedId,
    required this.commentKeys,
  });

  final IssueComment root;
  final CommentInteractions interactions;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(IssueComment comment)? onToggleSelected;
  final String? highlightedId;
  final Map<String, GlobalKey>? commentKeys;

  /// Indent of the reply block; the connector line lives in this gutter.
  static const double _indent = 40;

  @override
  Widget build(BuildContext context) {
    final thread = interactions.threadOf(root.id);
    // Nothing to show: no known replies and never expanded.
    if (root.replyCount == 0 && thread.replies.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!thread.expanded) {
      final count = root.replyCount;
      return Padding(
        padding: const EdgeInsets.only(left: _indent, top: 8),
        child: _ThreadControl(
          icon: LucideIcons.messageCircle,
          loading: thread.loading,
          label: context.t(
            'comments.showReplies',
            count: count,
            variables: {'count': '$count'},
          ),
          onTap: () => interactions.onToggleReplies(root),
        ),
      );
    }

    final replies = thread.replies;
    // No top gap: the first reply's rail must continue the root's branch stem.
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < replies.length; i++)
            _replyRow(replies[i], last: i == replies.length - 1 && !thread.hasMore),
          Padding(
            padding: const EdgeInsets.only(left: _indent, top: 6),
            child: Row(
              children: [
                if (thread.hasMore)
                  _ThreadControl(
                    icon: LucideIcons.chevronDown,
                    loading: thread.loading,
                    label: context.t('comments.loadMoreReplies'),
                    onTap: () => interactions.onLoadMoreReplies(root),
                  ),
                if (thread.hasMore) const SizedBox(width: 8),
                _ThreadControl(
                  icon: LucideIcons.chevronUp,
                  loading: false,
                  label: context.t('comments.hideReplies'),
                  onTap: () => interactions.onToggleReplies(root),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyRow(IssueComment reply, {required bool last}) {
    final row = CommentBubbleRow(
      comment: reply,
      interactions: interactions,
      isReply: true,
      selectionMode: selectionMode,
      selected: selectedIds.contains(reply.id),
      onToggleSelected: onToggleSelected,
      highlight: highlightedId == reply.id,
    );
    final keyed = commentKeys?[reply.id];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _indent,
            child: CustomPaint(
              painter: _ReplyConnectorPainter(
                last: last,
                color: AppColors.hairline,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: keyed == null
                  ? row
                  : KeyedSubtree(key: keyed, child: row),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the reply connector: a vertical rail down the gutter with a curved
/// elbow into each reply's avatar. The rail stops at the elbow on the last row.
class _ReplyConnectorPainter extends CustomPainter {
  _ReplyConnectorPainter({required this.last, required this.color});

  final bool last;
  final Color color;

  // Where the elbow meets the avatar row (aligns with the reply avatar centre:
  // 8px top padding + ~13 to the avatar's vertical middle).
  static const double _elbowY = 21;
  // Rail x = the ROOT avatar's centre (32/2), so the branch continues the root's
  // main-branch stem in a straight, unbroken line.
  static const double _railX = 16;
  // The elbow reaches across the gutter to the reply avatar's left edge.
  static const double _avatarEdgeX = 36;
  // Radius of the rounded corner where the rail turns into the elbow.
  static const double _corner = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Vertical rail (continues the root's main branch). For the LAST reply it
    // stops exactly where the rounded corner begins — no straight overshoot — so
    // the branch closes with a clean quarter-round; otherwise it runs full
    // height down to the next reply.
    canvas.drawLine(
      const Offset(_railX, 0),
      Offset(_railX, last ? _elbowY - _corner : size.height),
      paint,
    );
    // Rounded corner from the rail across to the reply avatar.
    final elbow = Path()
      ..moveTo(_railX, _elbowY - _corner)
      ..quadraticBezierTo(_railX, _elbowY, _avatarEdgeX, _elbowY);
    canvas.drawPath(elbow, paint);
  }

  @override
  bool shouldRepaint(_ReplyConnectorPainter old) =>
      old.last != last || old.color != color;
}

/// A subtle text-button used by the reply thread ("show replies", "load more",
/// "hide replies"), with an optional inline spinner.
class _ThreadControl extends StatelessWidget {
  const _ThreadControl({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(1),
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    : Icon(icon, size: 14, color: AppColors.accentStrong),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

/// Reaction chips (emoji + count) shown under a comment. The user's own reaction
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
        children: [
          for (final r in rows) _row(context, r),
        ],
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
/// smart-links and inline images keep working. Flat, on a transparent
/// background (no bubble); the timestamp lives in the row header.
class _TextBody extends StatelessWidget {
  const _TextBody({required this.comment});

  final IssueComment comment;

  /// Matches any line that opens a block-level markdown construct.
  static final _blockLine = RegExp(
    r'^(#{1,6}\s|```|>\s?|\s*\|.*\||:::|(-{3,}|\*{3,}|_{3,})\s*$|(\s*([-*+]|\d+\.)\s+))',
  );
  static final _image = RegExp(r'!\[[^\]]*\]\([^)]+\)');

  /// True when the body is a single paragraph with no block-level markdown —
  /// rendered as one inline run instead of the heavier block layout.
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
    if (_inlineOnly) {
      final parser = KbMarkdownParser(fontSize: 14);
      final base = parser.baseStyle.copyWith(height: 1.35);
      final body = comment.text
          .replaceAll('\r\n', '\n')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .join(' ');
      return Text.rich(TextSpan(children: [parser.inlineFor(body, base)]));
    }

    final nodes = KbMarkdownParser(fontSize: 14).parse(comment.text).nodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: nodes,
    );
  }
}

/// A playable voice message: amber play/pause, tappable/scrubbable waveform and
/// a live-updating timecode. Audio is fetched lazily on first play.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.voice, required this.loader});

  final CommentVoice voice;
  final VoiceAudioLoader loader;

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
        final timeStyle = TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 10.5,
          color: AppColors.inkFaint,
        );
        return SizedBox(
          width: 230,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Play button and waveform share one centred row, so the play
              // glyph sits exactly on the waveform's centre line (WhatsApp-style
              // — the 40px button and 30px waveform both centre to the row).
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
                    child: SizedBox(
                      height: 30,
                      child: _Waveform(
                        peaks: widget.voice.peaks,
                        progress: _controller.progress,
                        onSeek: _controller.seekFraction,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Timecodes below the waveform, indented past the play button
              // (40px button + 11px gap) so they align under the peaks.
              Padding(
                padding: const EdgeInsets.only(left: 51),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _mmss(
                        playing || elapsed > Duration.zero ? elapsed : total,
                      ),
                      style: timeStyle,
                    ),
                    Text(_mmss(total), style: timeStyle),
                  ],
                ),
              ),
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
