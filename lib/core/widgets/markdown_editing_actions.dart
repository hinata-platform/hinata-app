import 'package:flutter/material.dart';

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
