import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

// ════════════════════════════════════════════════════════════════════════
//  Lightweight, dependency-free Markdown for the issue description.
//  Renderer covers the common subset (headings, bold, italic, inline code,
//  fenced code blocks, bullet/ordered lists, clickable links, rules,
//  paragraphs); the editor pairs a plain multi-line field with a small
//  toolbar that inserts the matching syntax.
// ════════════════════════════════════════════════════════════════════════

/// Renders a Markdown [data] string as styled Flutter widgets.
class MarkdownText extends StatefulWidget {
  const MarkdownText(this.data, {super.key, this.baseStyle});

  final String data;
  final TextStyle? baseStyle;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  // Tap recognizers for links live as long as the rendered spans; track them
  // so they can be disposed and rebuilt whenever the markdown changes.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(MarkdownText old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data || old.baseStyle != widget.baseStyle) {
      _disposeRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final base = widget.baseStyle ??
        TextStyle(fontSize: 14, height: 1.55, color: AppColors.ink);
    final blocks = <Widget>[];
    final lines = widget.data.replaceAll('\r\n', '\n').split('\n');

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trimLeft();

      // Fenced code block: ```lang … ``` (consume until the closing fence).
      final fence = RegExp(r'^```+\s*([\w+-]*)\s*$').firstMatch(trimmed);
      if (fence != null) {
        final codeLines = <String>[];
        i++;
        while (i < lines.length &&
            !RegExp(r'^\s*```+\s*$').hasMatch(lines[i])) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // skip closing fence
        blocks.add(_codeBlock(codeLines.join('\n'), fence.group(1), base));
        continue;
      }

      // Blank line → paragraph gap.
      if (trimmed.isEmpty) {
        blocks.add(const SizedBox(height: 8));
        i++;
        continue;
      }

      // Horizontal rule.
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        blocks.add(Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: AppColors.hairline),
        ));
        i++;
        continue;
      }

      // ATX headings.
      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final size = switch (level) { 1 => 19.0, 2 => 16.5, _ => 14.5 };
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 8, bottom: 4),
          child: RichText(
            text: _inline(
              heading.group(2)!,
              base.copyWith(
                fontFamily: AppTheme.fontBrand,
                fontSize: size,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ));
        i++;
        continue;
      }

      // Bullet list (consume consecutive items).
      if (RegExp(r'^[-*]\s+').hasMatch(trimmed)) {
        while (i < lines.length &&
            RegExp(r'^\s*[-*]\s+').hasMatch(lines[i])) {
          final content = lines[i].replaceFirst(RegExp(r'^\s*[-*]\s+'), '');
          blocks.add(_listItem(context, '•', content, base));
          i++;
        }
        continue;
      }

      // Ordered list.
      if (RegExp(r'^\d+\.\s+').hasMatch(trimmed)) {
        var n = 1;
        while (i < lines.length &&
            RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i])) {
          final content = lines[i].replaceFirst(RegExp(r'^\s*\d+\.\s+'), '');
          blocks.add(_listItem(context, '$n.', content, base));
          n++;
          i++;
        }
        continue;
      }

      // Paragraph.
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(text: _inline(trimmed, base)),
      ));
      i++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  Widget _listItem(
      BuildContext context, String marker, String content, TextStyle base) {
    return Padding(
      padding: const EdgeInsets.only(top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(marker,
                style: base.copyWith(
                    color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: RichText(text: _inline(content, base))),
        ],
      ),
    );
  }

  /// Tokenises inline spans: **bold**, *italic*/_italic_, `code`, [text](url).
  TextSpan _inline(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\*\*([^*]+)\*\*)'
      r'|(__([^_]+)__)'
      r'|(\*([^*]+)\*)'
      r'|(_([^_]+)_)'
      r'|(`([^`]+)`)'
      r'|(\[([^\]]+)\]\(([^)]+)\))',
    );
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }
      if (m.group(2) != null || m.group(4) != null) {
        spans.add(TextSpan(
            text: m.group(2) ?? m.group(4),
            style: base.copyWith(fontWeight: FontWeight.w700)));
      } else if (m.group(6) != null || m.group(8) != null) {
        spans.add(TextSpan(
            text: m.group(6) ?? m.group(8),
            style: base.copyWith(fontStyle: FontStyle.italic)));
      } else if (m.group(10) != null) {
        spans.add(TextSpan(
          text: ' ${m.group(10)} ',
          style: base.copyWith(
            fontFamily: AppTheme.fontMono,
            fontSize: (base.fontSize ?? 14) - 1,
            color: AppColors.ink,
            backgroundColor: AppColors.surfaceMuted,
          ),
        ));
      } else if (m.group(12) != null) {
        // Link: accent text that opens the target URL on tap.
        final url = m.group(13)!;
        final recognizer = TapGestureRecognizer()..onTap = () => _openUrl(url);
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: m.group(12),
          recognizer: recognizer,
          style: base.copyWith(
            color: AppColors.stTodo,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.stTodo,
          ),
        ));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }
    return TextSpan(children: spans, style: base);
  }

  /// Renders a fenced code block with an optional language label.
  Widget _codeBlock(String code, String? lang, TextStyle base) {
    final mono = base.copyWith(
      fontFamily: AppTheme.fontMono,
      fontSize: (base.fontSize ?? 14) - 1,
      height: 1.45,
      color: AppColors.ink,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lang != null && lang.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.hairline)),
                ),
                child: Text(
                  lang,
                  style: base.copyWith(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11,
                    color: AppColors.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: SelectableText(code, style: mono),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    // Default to https:// when the scheme is omitted (e.g. "google.com").
    final uri = Uri.parse(
      RegExp(r'^[a-zA-Z][a-zA-Z\d+.-]*:').hasMatch(url) ? url : 'https://$url',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Multi-line Markdown editor: a thin formatting toolbar above a plain field.
class MarkdownEditorField extends StatelessWidget {
  const MarkdownEditorField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.minLines = 5,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Toolbar
          Container(
            decoration: BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: AppColors.hairline2)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                _ToolBtn(
                  icon: Icons.title_rounded,
                  tooltip: 'Heading',
                  onTap: () => _prefixLine('## '),
                ),
                _ToolBtn(
                  icon: Icons.format_bold_rounded,
                  tooltip: 'Bold',
                  onTap: () => _wrap('**', '**'),
                ),
                _ToolBtn(
                  icon: Icons.format_italic_rounded,
                  tooltip: 'Italic',
                  onTap: () => _wrap('_', '_'),
                ),
                _ToolBtn(
                  icon: Icons.format_list_bulleted_rounded,
                  tooltip: 'List',
                  onTap: () => _prefixLine('- '),
                ),
                _ToolBtn(
                  icon: Icons.code_rounded,
                  tooltip: 'Code',
                  onTap: () => _wrap('`', '`'),
                ),
                _ToolBtn(
                  icon: Icons.link_rounded,
                  tooltip: 'Link',
                  onTap: () => _wrap('[', '](https://)'),
                ),
              ],
            ),
          ),
          // Field
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: minLines,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 14, height: 1.5),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hintText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Wraps the current selection (or caret) with [before]/[after].
  void _wrap(String before, String after) {
    final value = controller.value;
    final sel = value.selection;
    final start = sel.start < 0 ? value.text.length : sel.start;
    final end = sel.end < 0 ? value.text.length : sel.end;
    final selected = value.text.substring(start, end);
    final newText =
        value.text.replaceRange(start, end, '$before$selected$after');
    controller.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(
          offset: start + before.length + selected.length),
    );
  }

  /// Inserts [prefix] at the start of the line the caret sits on.
  void _prefixLine(String prefix) {
    final value = controller.value;
    final sel = value.selection;
    final caret = sel.start < 0 ? value.text.length : sel.start;
    final lineStart = value.text.lastIndexOf('\n', caret - 1) + 1;
    final newText = value.text.replaceRange(lineStart, lineStart, prefix);
    controller.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: caret + prefix.length),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn(
      {required this.icon, required this.onTap, required this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        onTap();
        HapticFeedback.selectionClick();
      },
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      color: AppColors.inkSoft,
      icon: Icon(icon),
    );
  }
}
