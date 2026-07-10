import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../data/knowledge_models.dart';
import '../knowledge_tokens.dart';
import 'markdown_image.dart';
import 'smart_link_chip.dart';

/// One Table-of-Contents entry (H1–H3). [key] anchors the matching heading
/// widget so the aside can `Scrollable.ensureVisible` it.
class TocEntry {
  TocEntry(this.id, this.lvl, this.txt) : key = GlobalKey();
  final String id;
  final int lvl;
  final String txt;
  final GlobalKey key;
}

/// Result of parsing a markdown body: the rendered block widgets plus the TOC.
class ParsedMarkdown {
  ParsedMarkdown(this.nodes, this.toc);
  final List<Widget> nodes;
  final List<TocEntry> toc;
}

/// Hand-rolled block + inline markdown parser — a 1:1 port of the reference
/// `renderMarkdown` (`app/markdown.jsx`). Supports headings, fenced code,
/// quotes, bullet/ordered/**task** lists, tables, `:::` callouts, rules, images
/// and links, plus the `{{…}}` smart-link tokens.
///
/// **Invariant (do not regress):** every branch of the block loop advances the
/// line cursor by ≥ 1, so a `#` heading or `---` rule can never spin forever.
class KbMarkdownParser {
  KbMarkdownParser({this.fontSize = 15, List<TapGestureRecognizer>? sink})
    : _recognizers = sink;

  final double fontSize;
  final List<TapGestureRecognizer>? _recognizers;
  int _key = 0;

  TextStyle get _base => TextStyle(
    fontFamily: AppTheme.fontUi,
    fontSize: fontSize,
    height: 1.68,
    color: AppColors.ink,
  );

  ParsedMarkdown parse(String src) {
    final toc = <TocEntry>[];
    final nodes = _parseBlocks(src, toc);
    return ParsedMarkdown(nodes, toc);
  }

  // ── block parser ──
  List<Widget> _parseBlocks(String src, List<TocEntry> toc) {
    final lines = src.replaceAll('\r\n', '\n').split('\n');
    final nodes = <Widget>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];

      // blank
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // fenced code
      final fence = RegExp(r'^```(\w*)\s*$').firstMatch(line);
      if (fence != null) {
        final lang = fence.group(1) ?? '';
        final buf = <String>[];
        i++;
        while (i < lines.length && !RegExp(r'^```\s*$').hasMatch(lines[i])) {
          buf.add(lines[i]);
          i++;
        }
        i++; // closing fence
        nodes.add(_codeBlock(buf.join('\n'), lang));
        continue;
      }

      // callout :::info / :::warn / :::note / :::tip
      final cal = RegExp(r'^:::(info|warn|note|tip)\s*$').firstMatch(line);
      if (cal != null) {
        final kind = cal.group(1)!;
        final buf = <String>[];
        i++;
        while (i < lines.length && !RegExp(r'^:::\s*$').hasMatch(lines[i])) {
          buf.add(lines[i]);
          i++;
        }
        i++;
        // Nested blocks; the inner TOC is intentionally discarded (mirrors ref).
        final inner = _parseBlocks(buf.join('\n'), <TocEntry>[]);
        nodes.add(_callout(kind, inner));
        continue;
      }

      // heading
      final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (h != null) {
        final lvl = h.group(1)!.length;
        final txt = h.group(2)!.trim();
        final id = '${_slug(txt)}-${_key++}';
        TocEntry? entry;
        if (lvl <= 3) {
          entry = TocEntry(id, lvl, txt);
          toc.add(entry);
        }
        nodes.add(_heading(lvl, txt, entry?.key ?? ValueKey(id)));
        i++;
        continue;
      }

      // horizontal rule
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) {
        nodes.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Divider(height: 1, color: AppColors.hairline),
          ),
        );
        i++;
        continue;
      }

      // table: header row + separator row
      if (RegExp(r'^\s*\|.*\|\s*$').hasMatch(line) &&
          i + 1 < lines.length &&
          RegExp(r'^\s*\|?[\s:|-]+\|?\s*$').hasMatch(lines[i + 1])) {
        final head = _splitRow(line);
        i += 2;
        final rows = <List<String>>[];
        while (i < lines.length &&
            RegExp(r'^\s*\|.*\|\s*$').hasMatch(lines[i])) {
          rows.add(_splitRow(lines[i]));
          i++;
        }
        nodes.add(_MdTable(head: head, rows: rows, parser: this));
        continue;
      }

      // blockquote
      if (RegExp(r'^>\s?').hasMatch(line)) {
        final buf = <String>[];
        while (i < lines.length && RegExp(r'^>\s?').hasMatch(lines[i])) {
          buf.add(lines[i].replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        final inner = _parseBlocks(buf.join('\n'), <TocEntry>[]);
        nodes.add(_quote(inner));
        continue;
      }

      // lists (task / unordered / ordered) — one nesting level via indent
      if (RegExp(r'^(\s*)([-*+]|\d+\.)\s+').hasMatch(line)) {
        final ordered = RegExp(r'^\s*\d+\.\s+').hasMatch(line);
        final items = <_ListItem>[];
        while (i < lines.length &&
            RegExp(r'^(\s*)([-*+]|\d+\.)\s+').hasMatch(lines[i])) {
          final lm = RegExp(
            r'^(\s*)([-*+]|\d+\.)\s+(.*)$',
          ).firstMatch(lines[i])!;
          final indent = lm.group(1)!.length;
          final content = lm.group(3)!;
          final task = RegExp(r'^\[([ xX])\]\s+(.*)$').firstMatch(content);
          items.add(
            _ListItem(
              indent: indent,
              isTask: task != null,
              checked: task != null && task.group(1)!.toLowerCase() == 'x',
              content: task != null ? task.group(2)! : content,
            ),
          );
          i++;
        }
        nodes.add(_list(ordered, items));
        continue;
      }

      // paragraph (gather until blank / block start)
      final buf = <String>[line];
      i++;
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !RegExp(
            r'^(#{1,6}\s|```|>\s?|\s*\|.*\||:::|(-{3,})|(\s*([-*+]|\d+\.)\s+))',
          ).hasMatch(lines[i])) {
        buf.add(lines[i]);
        i++;
      }
      nodes.add(_paragraph(buf.join(' ')));
    }
    return nodes;
  }

  // ── block builders ──
  Widget _heading(int lvl, String txt, Key key) {
    final style =
        switch (lvl) {
          1 => const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          2 => const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          3 => const TextStyle(
            fontSize: 17.5,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
          _ => TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        }.copyWith(
          fontFamily: AppTheme.fontBrand,
          letterSpacing: -0.4,
          color: lvl > 3 ? AppColors.inkSoft : AppColors.ink,
        );
    final text = Text.rich(_inline(txt, style), key: key);
    if (lvl == 2) {
      return Padding(
        padding: const EdgeInsets.only(top: 27, bottom: 10),
        child: Container(
          padding: const EdgeInsets.only(bottom: 7),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.hairline2)),
          ),
          child: text,
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: lvl == 1 ? 22 : 24, bottom: 9),
      child: text,
    );
  }

  Widget _paragraph(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Text.rich(_inline(text, _base)),
  );

  Widget _codeBlock(String code, String lang) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(KbTokens.radiusCard),
      child: Container(
        color: KbTokens.codeBlockBg,
        child: Stack(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 13,
                  height: 1.6,
                  color: KbTokens.codeBlockInk,
                ),
              ),
            ),
            if (lang.isNotEmpty)
              Positioned(
                top: 9,
                right: 12,
                child: Text(
                  lang.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 10.5,
                    letterSpacing: 0.6,
                    color: KbTokens.codeBlockFaint,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _quote(List<Widget> inner) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Container(
      padding: const EdgeInsets.fromLTRB(18, 4, 8, 4),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: AppColors.inkSoft, fontStyle: FontStyle.italic),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: inner,
        ),
      ),
    ),
  );

  Widget _callout(String kind, List<Widget> inner) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: KbTokens.calloutBg(kind),
        borderRadius: BorderRadius.circular(KbTokens.radiusCard),
        border: Border.all(color: KbTokens.calloutBorder(kind)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 12),
            child: Icon(
              lucideIcon(KbTokens.calloutIcon(kind)),
              size: 18,
              color: KbTokens.calloutInk(kind),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: inner,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _list(bool ordered, List<_ListItem> items) {
    // Build a flat structure with one nesting level (indent ≥ 2 → child).
    final top = <_ListItem>[];
    for (final it in items) {
      if (it.indent >= 2 && top.isNotEmpty) {
        top.last.children.add(it);
      } else {
        top.add(it);
      }
    }
    final hasTask = items.any((it) => it.isTask);
    final rows = <Widget>[];
    var n = 1;
    for (final it in top) {
      rows.add(_listRow(it, ordered ? '${n++}.' : '•'));
      var cn = 1;
      for (final c in it.children) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: _listRow(c, ordered ? '${cn++}.' : '◦'),
          ),
        );
      }
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(hasTask ? 3 : 4, 8, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }

  Widget _listRow(_ListItem it, String marker) {
    if (it.isTask) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 1, right: 9),
              decoration: BoxDecoration(
                color: it.checked ? AppColors.success : AppColors.surface,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: it.checked ? AppColors.success : AppColors.hairline,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: it.checked
                  ? Icon(lucideIcon('check'), size: 12, color: Colors.white)
                  : null,
            ),
            Expanded(
              child: Text.rich(
                _inline(
                  it.content,
                  it.checked
                      ? _base.copyWith(
                          color: AppColors.inkFaint,
                          decoration: TextDecoration.lineThrough,
                        )
                      : _base,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              marker,
              style: _base.copyWith(
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text.rich(_inline(it.content, _base))),
        ],
      ),
    );
  }

  // ── inline parser ──
  InlineSpan _inline(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final re = RegExp(
      r'\{\{(issue|doc|user):([^}]+)\}\}'
      r'|!\[([^\]]*)\]\(([^)]+)\)'
      r'|\[([^\]]+)\]\(([^)]+)\)'
      r'|`([^`]+)`'
      r'|\*\*([^*]+)\*\*'
      r'|~~([^~]+)~~'
      r'|\*([^*]+)\*'
      r'|_([^_]+)_',
    );
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }
      if (m.group(1) != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: SmartLinkChip(kind: m.group(1)!, id: m.group(2)!),
          ),
        );
      } else if (m.group(3) != null) {
        // Image `![alt](url)` — rendered via [MarkdownImage] so URL images
        // actually show on Flutter web (authenticated bytes / server proxy)
        // instead of silently failing through a plain Image.network.
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: MarkdownImage(url: m.group(4)!, alt: m.group(3)),
          ),
        );
      } else if (m.group(5) != null) {
        spans.add(_link(m.group(5)!, m.group(6)!, base));
      } else if (m.group(7) != null) {
        spans.add(
          TextSpan(
            text: m.group(7),
            style: base.copyWith(
              fontFamily: AppTheme.fontMono,
              fontSize: (base.fontSize ?? 15) * 0.86,
              color: KbTokens.inlineCode,
              backgroundColor: KbTokens.inlineCodeBg,
            ),
          ),
        );
      } else if (m.group(8) != null) {
        spans.add(
          TextSpan(
            text: m.group(8),
            style: base.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        );
      } else if (m.group(9) != null) {
        spans.add(
          TextSpan(
            text: m.group(9),
            style: base.copyWith(
              decoration: TextDecoration.lineThrough,
              color: AppColors.inkFaint,
            ),
          ),
        );
      } else if (m.group(10) != null) {
        spans.add(
          TextSpan(
            text: m.group(10),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else if (m.group(11) != null) {
        spans.add(
          TextSpan(
            text: m.group(11),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }
    return TextSpan(children: spans, style: base);
  }

  InlineSpan _link(String text, String url, TextStyle base) {
    final recognizer = TapGestureRecognizer()..onTap = () => _openUrl(url);
    _recognizers?.add(recognizer);
    return TextSpan(
      text: text,
      recognizer: recognizer,
      style: base.copyWith(
        color: KbTokens.accent,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.accentLine,
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(
      RegExp(r'^[a-zA-Z][a-zA-Z\d+.-]*:').hasMatch(url) ? url : 'https://$url',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Exposed for the table cell builder.
  InlineSpan inlineFor(String text, TextStyle base) => _inline(text, base);
  TextStyle get baseStyle => _base;

  static List<String> _splitRow(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((c) => c.trim()).toList();
  }

  static String _slug(String s) {
    final out = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    return out.length > 60 ? out.substring(0, 60) : out;
  }
}

class _ListItem {
  _ListItem({
    required this.indent,
    required this.isTask,
    required this.checked,
    required this.content,
  });
  final int indent;
  final bool isTask;
  final bool checked;
  final String content;
  final List<_ListItem> children = [];
}

/// A markdown table that scrolls horizontally inside a rounded clip (never
/// pushes the page wide). Columns size to content but stretch to fill the
/// available width when narrower.
class _MdTable extends StatelessWidget {
  const _MdTable({
    required this.head,
    required this.rows,
    required this.parser,
  });

  final List<String> head;
  final List<List<String>> rows;
  final KbMarkdownParser parser;

  @override
  Widget build(BuildContext context) {
    final cols = head.length;
    final headStyle = const TextStyle(
      fontFamily: AppTheme.fontUi,
      fontSize: 12,
      height: 1.4,
    ).copyWith(fontWeight: FontWeight.w700, color: AppColors.ink);
    final cellStyle = TextStyle(
      fontFamily: AppTheme.fontUi,
      fontSize: 13.5,
      height: 1.5,
      color: AppColors.ink,
    );

    TableRow buildRow(List<String> cells, {required bool header}) => TableRow(
      decoration: header ? BoxDecoration(color: AppColors.surfaceMuted) : null,
      children: [
        for (var c = 0; c < cols; c++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text.rich(
              parser.inlineFor(
                c < cells.length ? cells[c] : '',
                header ? headStyle : cellStyle,
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KbTokens.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.hairline),
            borderRadius: BorderRadius.circular(KbTokens.radiusCard),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  border: TableBorder.symmetric(
                    inside: BorderSide(color: AppColors.hairline2),
                  ),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    buildRow(head, header: true),
                    for (final r in rows) buildRow(r, header: false),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
