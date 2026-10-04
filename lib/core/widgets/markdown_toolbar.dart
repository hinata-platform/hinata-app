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

  // ── inline image upload ──
  // A placeholder `![alt](hinata-uploading:<token>)` is inserted at the caret
  // the moment an upload starts, then swapped for the real `![alt](url)` when it
  // resolves — so the caret is freed immediately and the user can keep typing.
  int _imgSeq = 0;
  final Map<String, String> _pendingImages = {};

  /// Inserts an upload placeholder for [fileName] and returns its token. The
  /// alt text is derived from the file name (extension stripped).
  String beginImageUpload(String fileName) {
    final token = 'img${_imgSeq++}';
    final alt = _imageAlt(fileName);
    final placeholder = '![$alt](hinata-uploading:$token)';
    _pendingImages[token] = placeholder;
    final v = controller.value;
    final s = v.selection.start < 0 ? v.text.length : v.selection.start;
    // Keep the image on its own line so it renders as a block, not mid-sentence.
    final pre = (s > 0 && v.text[s - 1] != '\n') ? '\n' : '';
    final insert = '$pre$placeholder\n';
    controller.value = TextEditingValue(
      text: v.text.replaceRange(s, s, insert),
      selection: TextSelection.collapsed(offset: s + insert.length),
    );
    focusNode.requestFocus();
    return token;
  }

  /// Swaps the placeholder for [token] with the final image markdown at [url].
  void completeImageUpload(String token, String url, String fileName) {
    final placeholder = _pendingImages.remove(token);
    if (placeholder == null || !controller.text.contains(placeholder)) return;
    controller.text = controller.text.replaceFirst(
      placeholder,
      '![${_imageAlt(fileName)}]($url)',
    );
  }

  /// Removes the placeholder for [token] after a failed/cancelled upload.
  void failImageUpload(String token) {
    final placeholder = _pendingImages.remove(token);
    if (placeholder == null) return;
    final text = controller.text;
    // Drop the placeholder and the blank line we padded it with.
    for (final variant in ['$placeholder\n', placeholder]) {
      if (text.contains(variant)) {
        controller.text = text.replaceFirst(variant, '');
        return;
      }
    }
  }

  String _imageAlt(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    return base.trim().isEmpty ? 'image' : base.trim();
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
    this.onImage,
  });

  final MarkdownEditingActions actions;

  /// When false, buttons are greyed and inert (e.g. while previewing).
  final bool enabled;

  /// When set, an "insert image" button is shown that runs this async pick →
  /// upload → insert flow (see `markdown_image_upload.dart`).
  final Future<void> Function()? onImage;

  /// Optional right-aligned widget (kept on one row with the buttons).
  final Widget? trailing;

  /// Command groups; defaults to [defaultMarkdownGroups].
  final List<List<MarkdownCommand>>? groups;

  /// Slightly smaller hit targets for compact surfaces.
  final bool dense;

  Widget _button(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback? onTap,
    double size,
  ) {
    final label = context.t(tooltip);
    // Named here, so the tooltip stays out of the tree and is not read twice.
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: dense ? 16 : 17,
              color: onTap != null ? AppColors.inkSoft : AppColors.inkFaint,
            ),
          ),
        ),
      ),
    );
  }

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
          _button(
            context,
            cmd.icon,
            cmd.tooltip,
            enabled ? () => cmd.run(actions) : null,
            size,
          ),
        );
      }
    }

    if (onImage != null) {
      children.add(
        Container(
          width: 1,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          color: AppColors.hairline,
        ),
      );
      children.add(
        _button(
          context,
          LucideIcons.image,
          'md.image',
          enabled ? () => onImage!() : null,
          size,
        ),
      );
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
