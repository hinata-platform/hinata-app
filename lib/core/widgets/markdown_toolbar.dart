import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';

/// Reusable Markdown editing primitives bound to a [TextEditingController] +
/// [FocusNode]. Centralises the `surround` / `linePrefix` / `insertBlock`
/// helpers (formerly duplicated in the KB article editor and the issue
/// description editor) so every Markdown surface inserts identical syntax.
class MarkdownEditingActions {
  MarkdownEditingActions(this.controller, this.focusNode);

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Wraps the selection (or [placeholder] when empty) in [before]/[after].
  void surround(String before, String after, String placeholder) {
    final v = controller.value;
    final s = v.selection.start < 0 ? v.text.length : v.selection.start;
    final e = v.selection.end < 0 ? v.text.length : v.selection.end;
    final sel = e > s ? v.text.substring(s, e) : placeholder;
    final next = v.text.replaceRange(s, e, '$before$sel$after');
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: s + before.length,
        extentOffset: s + before.length + sel.length,
      ),
    );
    focusNode.requestFocus();
  }

  /// Prefixes each selected line with [prefix]; `%` is replaced by the 1-based
  /// line number (for ordered lists).
  void linePrefix(String prefix) {
    final v = controller.value;
    final s = v.selection.start < 0 ? v.text.length : v.selection.start;
    final e = v.selection.end < 0 ? v.text.length : v.selection.end;
    final lineStart = v.text.lastIndexOf('\n', s - 1) + 1;
    final block = v.text.substring(lineStart, e);
    final fixed = block
        .split('\n')
        .asMap()
        .entries
        .map((x) => prefix.replaceFirst('%', '${x.key + 1}') + x.value)
        .join('\n');
    final next = v.text.replaceRange(lineStart, e, fixed);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: lineStart + fixed.length),
    );
    focusNode.requestFocus();
  }

  /// Inserts a standalone block at the caret, padded with blank lines.
  void insertBlock(String text) {
    final v = controller.value;
    final s = v.selection.start < 0 ? v.text.length : v.selection.start;
    final pre = (s > 0 && v.text[s - 1] != '\n') ? '\n\n' : '';
    final next = v.text.replaceRange(s, s, '$pre$text');
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: s + pre.length + text.length),
    );
    focusNode.requestFocus();
  }

  /// Types a literal `@` to trigger the `@`-mention menu at the caret.
  void insertMention() {
    final v = controller.value;
    final s = v.selection.start < 0 ? v.text.length : v.selection.start;
    final next = v.text.replaceRange(s, s, '@');
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: s + 1),
    );
    focusNode.requestFocus();
  }

  // ── named commands (so callers read intent, not raw syntax) ──
  void heading(int level) => linePrefix('${'#' * level} ');
  void bold() => surround('**', '**', 'bold');
  void italic() => surround('*', '*', 'italic');
  void strikethrough() => surround('~~', '~~', 'strike');
  void inlineCode() => surround('`', '`', 'code');
  void bulletList() => linePrefix('- ');
  void numberedList() => linePrefix('%. ');
  void taskList() => linePrefix('- [ ] ');
  void quote() => linePrefix('> ');
  void link() => surround('[', '](https://)', 'text');
  void codeBlock() => insertBlock('```ts\n\n```');
  void table() =>
      insertBlock('| Column | Column |\n| --- | --- |\n| Cell | Cell |');
  void infoPanel() => insertBlock(':::info\n\n:::');
}

/// A single toolbar command.
class MarkdownCommand {
  const MarkdownCommand(this.icon, this.tooltip, this.run);
  final IconData icon;
  final String tooltip;
  final void Function(MarkdownEditingActions a) run;
}

/// The default command groups (headings · inline · lists/blocks · insert).
/// Exposed so callers can trim/extend, but the defaults suit every surface.
List<List<MarkdownCommand>> defaultMarkdownGroups({bool mention = true}) => [
  const [
    MarkdownCommand(LucideIcons.bold, 'md.bold', _bold),
    MarkdownCommand(LucideIcons.italic, 'md.italic', _italic),
    MarkdownCommand(LucideIcons.strikethrough, 'md.strikethrough', _strike),
    MarkdownCommand(LucideIcons.code, 'md.inlineCode', _inlineCode),
  ],
  const [
    MarkdownCommand(LucideIcons.list, 'md.bulletList', _bullet),
    MarkdownCommand(LucideIcons.listOrdered, 'md.numberedList', _ordered),
    MarkdownCommand(LucideIcons.listChecks, 'md.taskList', _task),
    MarkdownCommand(LucideIcons.quote, 'md.quote', _quote),
  ],
  [
    const MarkdownCommand(LucideIcons.link, 'md.link', _link),
    const MarkdownCommand(LucideIcons.squareCode, 'md.codeBlock', _codeBlock),
    const MarkdownCommand(LucideIcons.table, 'md.table', _table),
    const MarkdownCommand(LucideIcons.info, 'md.infoPanel', _info),
    if (mention)
      const MarkdownCommand(LucideIcons.atSign, 'md.mention', _mention),
  ],
];

// Top-level command callbacks (so the groups can stay `const`).
void _bold(MarkdownEditingActions a) => a.bold();
void _italic(MarkdownEditingActions a) => a.italic();
void _strike(MarkdownEditingActions a) => a.strikethrough();
void _inlineCode(MarkdownEditingActions a) => a.inlineCode();
void _bullet(MarkdownEditingActions a) => a.bulletList();
void _ordered(MarkdownEditingActions a) => a.numberedList();
void _task(MarkdownEditingActions a) => a.taskList();
void _quote(MarkdownEditingActions a) => a.quote();
void _link(MarkdownEditingActions a) => a.link();
void _codeBlock(MarkdownEditingActions a) => a.codeBlock();
void _table(MarkdownEditingActions a) => a.table();
void _info(MarkdownEditingActions a) => a.infoPanel();
void _mention(MarkdownEditingActions a) => a.insertMention();

/// A reusable, grouped Markdown formatting toolbar. Drop it above any
/// [MentionField]/[TextField] and pass its [MarkdownEditingActions]; an optional
/// [trailing] widget (e.g. a Write/Preview switcher) sits on the right.
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({
    super.key,
    required this.actions,
    this.enabled = true,
    this.trailing,
    this.groups,
    this.dense = false,
  });

  final MarkdownEditingActions actions;

  /// When false, buttons are greyed and inert (e.g. while previewing).
  final bool enabled;

  /// Optional right-aligned widget (kept on one row with the buttons).
  final Widget? trailing;

  /// Command groups; defaults to [defaultMarkdownGroups].
  final List<List<MarkdownCommand>>? groups;

  /// Slightly smaller hit targets for compact surfaces.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final groups = this.groups ?? defaultMarkdownGroups();
    final size = dense ? 30.0 : 32.0;
    final children = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      if (g > 0) {
        children.add(
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            color: AppColors.hairline,
          ),
        );
      }
      for (final cmd in groups[g]) {
        children.add(
          Tooltip(
            message: context.t(cmd.tooltip),
            child: InkWell(
              onTap: enabled ? () => cmd.run(actions) : null,
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  cmd.icon,
                  size: dense ? 16 : 17,
                  color: enabled ? AppColors.inkSoft : AppColors.inkFaint,
                ),
              ),
            ),
          ),
        );
      }
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          // Single row of commands that scrolls horizontally so every option
          // stays reachable on narrow screens instead of wrapping to a second
          // line. A faded edge hints that more commands lie off-screen. The
          // optional [trailing] stays pinned (non-scrolling) on the right.
          Expanded(child: _ScrollFadeRow(children: children)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Horizontally-scrolling row that overlays a soft fade on whichever edge has
/// content scrolled past it — the cue that the toolbar can be scrolled.
class _ScrollFadeRow extends StatefulWidget {
  const _ScrollFadeRow({required this.children});

  final List<Widget> children;

  @override
  State<_ScrollFadeRow> createState() => _ScrollFadeRowState();
}

class _ScrollFadeRowState extends State<_ScrollFadeRow> {
  final _controller = ScrollController();
  bool _atStart = true;
  bool _atEnd = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    // Positions aren't attached until after first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    final atStart = p.pixels <= p.minScrollExtent + 0.5;
    final atEnd = p.pixels >= p.maxScrollExtent - 0.5;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-sync on size changes (e.g. orientation / available width).
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
        return false;
      },
      child: ShaderMask(
        shaderCallback: (rect) {
          // dstIn keeps content where the shader is opaque and fades it where
          // the shader is transparent. Only the edges with more content to
          // reveal get faded.
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              _atStart ? Colors.black : Colors.transparent,
              Colors.black,
              Colors.black,
              _atEnd ? Colors.black : Colors.transparent,
            ],
            stops: const [0.0, 0.06, 0.94, 1.0],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: widget.children,
          ),
        ),
      ),
    );
  }
}
