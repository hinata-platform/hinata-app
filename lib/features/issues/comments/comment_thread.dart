import 'package:flutter/material.dart';
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

/// Chat-style activity feed (Liquid-Glass comment section). Text comments render
/// as bubbles; voice comments as playable waveform bubbles.
///
/// Alignment is responsive per the design: on **compact** (phone) the signed-in
/// user's own comments sit on the right (classic chat), everyone else on the
/// left. On **medium/expanded** (tablet + desktop) *every* bubble — including the
/// user's own — aligns left, which reads more naturally in a wide column.
class CommentThread extends StatelessWidget {
  const CommentThread({
    super.key,
    required this.comments,
    required this.meId,
    required this.nameFor,
    required this.avatarFor,
    required this.loadVoice,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final List<IssueComment> comments;
  final String? meId;
  final String Function(String authorId) nameFor;
  final String? Function(String authorId) avatarFor;

  /// Fetches a voice comment's audio bytes through the authenticated proxy.
  final VoiceAudioLoader Function(IssueComment comment) loadVoice;

  final bool Function(IssueComment comment) canManage;
  final void Function(IssueComment comment) onEdit;
  final void Function(IssueComment comment) onDelete;

  /// Whether the signed-in user's own comments sit on the right (chat style).
  /// Only on compact (phone); wide layouts left-align everything.
  static bool chatMode(BuildContext context) =>
      context.layoutSize == LayoutSize.compact;

  /// Consecutive comments from the same author within this window are treated as
  /// one WhatsApp-style group: name shown once on top, avatar once at the bottom.
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
      final prev = idx > 0 ? comments[idx - 1] : null;
      final next = idx < comments.length - 1 ? comments[idx + 1] : null;
      final firstOfGroup = prev == null || !_grouped(prev, c);
      final lastOfGroup = next == null || !_grouped(c, next);
      rows.add(
        Padding(
          // Tight within a group, roomier between groups — the vertical rhythm
          // that keeps the feed from feeling bulky.
          padding: EdgeInsets.only(top: idx == 0 ? 0 : (firstOfGroup ? 14 : 3)),
          child: CommentBubbleRow(
            comment: c,
            // Right-align only in chat mode, and only for the current user.
            me: chat && meId != null && c.authorId == meId,
            name: nameFor(c.authorId),
            avatarUrl: avatarFor(c.authorId),
            loadVoice: loadVoice(c),
            canManage: canManage(c),
            // Author name only atop a group; avatar + tail only on its last
            // bubble, so stacked messages read as one thread.
            showName: firstOfGroup,
            showAvatar: lastOfGroup,
            tail: lastOfGroup,
            onEdit: () => onEdit(c),
            onDelete: () => onDelete(c),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// One comment in the feed (text bubble or playable voice bubble). Reused by
/// every activity tab so comments look identical in Comments, All and History.
class CommentBubbleRow extends StatelessWidget {
  const CommentBubbleRow({
    super.key,
    required this.comment,
    required this.me,
    required this.name,
    required this.avatarUrl,
    required this.loadVoice,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    this.showName = true,
    this.showAvatar = true,
    this.tail = true,
  });

  final IssueComment comment;
  final bool me;
  final String name;
  final String? avatarUrl;
  final VoiceAudioLoader loadVoice;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Author name atop the bubble — only the first message of a group shows it.
  final bool showName;

  /// Avatar in the gutter — only the last message of a group shows it; earlier
  /// ones reserve the gutter width so the column stays aligned.
  final bool showAvatar;

  /// Whether this bubble draws the small "tail" corner (last of a group).
  final bool tail;

  @override
  Widget build(BuildContext context) {
    // Compact (phone) = chat layout + long-press moderation. On tablet/desktop
    // long-press is unintuitive, so own comments get explicit edit/delete
    // buttons pinned to the row's trailing edge instead.
    final compact = CommentThread.chatMode(context);
    final inlineActions = !compact && canManage;

    final avatar = showAvatar
        ? HiveAvatar(name: name, imageUrl: avatarUrl, size: 30)
        : const SizedBox(width: 30);
    Widget bubble = _Bubble(
      comment: comment,
      me: me,
      tail: tail,
      loadVoice: loadVoice,
      canManage: canManage,
      // Long-press menu only in chat (compact) mode.
      enableMenu: compact && canManage,
      onEdit: onEdit,
      onDelete: onDelete,
    );
    if (inlineActions) {
      // Bubble hugs its content on the left; the actions sit at a *fixed* right
      // edge so every row's buttons line up in one column — putting the empty
      // space between them (via Expanded on the bubble) instead of after them.
      bubble = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: bubble,
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: _RowActions(
              canEdit: !comment.isVoice,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
        ],
      );
    }

    final column = Flexible(
      child: Column(
        crossAxisAlignment: me
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (showName && !me)
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
        ],
      ),
    );

    final children = me
        ? [column, const SizedBox(width: 9), avatar]
        : [avatar, const SizedBox(width: 9), column];

    return Row(
      mainAxisAlignment: me ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: children,
    );
  }
}

/// Explicit edit/delete controls shown beside a user's own comment on
/// tablet/desktop (where long-press moderation would be unintuitive).
class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canEdit)
          _iconButton(
            context,
            icon: LucideIcons.pencil,
            tooltip: context.t('common.edit'),
            color: AppColors.inkFaint,
            onTap: onEdit,
          ),
        _iconButton(
          context,
          icon: LucideIcons.trash2,
          tooltip: context.t('common.delete'),
          color: AppColors.inkFaint,
          hoverColor: AppColors.danger,
          onTap: onDelete,
        ),
      ],
    );
  }

  Widget _iconButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required Color color,
    Color? hoverColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: (hoverColor ?? AppColors.accent).withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      ),
    );
  }
}

/// A single comment bubble (text or voice). Long-press on a bubble the user owns
/// opens an edit/delete menu, so moderation survives the chat-style redesign.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.comment,
    required this.me,
    required this.tail,
    required this.loadVoice,
    required this.canManage,
    required this.enableMenu,
    required this.onEdit,
    required this.onDelete,
  });

  final IssueComment comment;
  final bool me;

  /// Draw the small "tail" corner on the sender's side (last of a group only).
  final bool tail;
  final VoiceAudioLoader loadVoice;
  final bool canManage;

  /// Whether long-press opens the edit/delete menu (compact/chat mode only).
  final bool enableMenu;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: Border.all(color: borderColor),
        ),
        padding: comment.isVoice
            ? const EdgeInsets.fromLTRB(8, 8, 12, 8)
            : const EdgeInsets.fromLTRB(13, 9, 13, 8),
        child: comment.isVoice
            ? VoiceBubble(
                voice: comment.voice!,
                me: me,
                loader: loadVoice,
                createdAt: comment.createdAt,
              )
            : _TextBody(comment: comment, me: me),
      ),
    );

    if (!enableMenu) return bubble;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _openMenu(context),
      onSecondaryTapDown: (d) => _openMenu(context, d.globalPosition),
      child: bubble,
    );
  }

  Future<void> _openMenu(BuildContext context, [Offset? at]) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = at ?? box.localToGlobal(box.size.center(Offset.zero));
    final selected = await _showGlassBubbleMenu(
      context,
      origin,
      canEdit: !comment.isVoice,
    );
    if (selected == 'edit') {
      onEdit();
    } else if (selected == 'delete') {
      onDelete();
    }
  }
}

/// Liquid-Glass long-press menu for a comment bubble (compact mode). Shown as a
/// positioned glass card at the press point, matching the composer's "+" popup.
Future<String?> _showGlassBubbleMenu(
  BuildContext context,
  Offset globalPos, {
  required bool canEdit,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.14),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (ctx, _, _) {
      final media = MediaQuery.of(ctx);
      const menuW = 224.0;
      final menuH = 12.0 + (canEdit ? 2 : 1) * 48.0;
      var left = globalPos.dx;
      var top = globalPos.dy;
      if (left + menuW > media.size.width - 12) {
        left = media.size.width - 12 - menuW;
      }
      if (left < 12) left = 12;
      // Open below the press; flip above if it would overflow the bottom.
      if (top + menuH > media.size.height - 12) {
        top = (top - menuH).clamp(12.0, media.size.height - 12 - menuH);
      }
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: _GlassBubbleMenu(canEdit: canEdit),
          ),
        ],
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          alignment: Alignment.topLeft,
          child: child,
        ),
      );
    },
  );
}

class _GlassBubbleMenu extends StatelessWidget {
  const _GlassBubbleMenu({required this.canEdit});

  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return GlassContainer(
      width: 224,
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
            if (canEdit)
              _menuRow(
                context,
                LucideIcons.pencil,
                context.t('common.edit'),
                () => Navigator.of(context).pop('edit'),
              ),
            _menuRow(
              context,
              LucideIcons.trash2,
              context.t('common.delete'),
              () => Navigator.of(context).pop('delete'),
              danger: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuRow(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final color = danger ? AppColors.danger : AppColors.ink;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Text(
                label,
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
