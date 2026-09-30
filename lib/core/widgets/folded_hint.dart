import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'info_circle_button.dart';

/// Whether [text] in [style] fits on one line of [maxWidth], at the text scale
/// and direction [context] renders with.
///
/// Measured rather than counted: the same hint is one line in English, two in
/// German, and anything at 200 % text.
bool fitsOneLine(
  BuildContext context,
  String text,
  TextStyle style,
  double maxWidth,
) {
  if (!maxWidth.isFinite) return true;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout(maxWidth: maxWidth);
  final fits = !painter.didExceedMaxLines;
  painter.dispose();
  return fits;
}

/// A hint that stays in view only while it fits on one line.
///
/// Longer, it shows its first line cut short with an "i" at the end, and the
/// whole line opens the full text (see [showInfoText]). Meant for text that
/// stands on its own, like a page's introduction or a note; a hint that
/// belongs to a title goes through [TitledHint] instead.
class FoldedHint extends StatelessWidget {
  const FoldedHint(this.text, {super.key, this.style, this.title});

  final String text;

  /// Merged onto the ambient [DefaultTextStyle], like [Text.style].
  final TextStyle? style;

  /// Heads the full text once it is opened.
  final String? title;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style.merge(this.style);
      if (fitsOneLine(context, text, style, constraints.maxWidth)) {
        return Text(text, style: style);
      }
      return Semantics(
        button: true,
        label: text,
        hint: context.t('common.moreInfo'),
        excludeSemantics: true,
        child: Tooltip(
          message: context.t('common.moreInfo'),
          child: InkWell(
            onTap: () => showInfoText(context, title: title, message: text),
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              // Tall enough to hit, without the row growing past the line.
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const InfoRing(size: 22),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A title with its hint: the hint under the title while it fits on one
/// line, behind an "i" beside the title once it does not.
class TitledHint extends StatelessWidget {
  const TitledHint({
    super.key,
    required this.title,
    required this.titleStyle,
    required this.hint,
    required this.hintStyle,
    this.gap = 2,
  });

  final String title;
  final TextStyle titleStyle;
  final String? hint;
  final TextStyle hintStyle;

  /// Space between the title and a hint that stays in view.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    final titleText = Text(title, style: titleStyle);
    if (hint == null || hint.isEmpty) return titleText;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (fitsOneLine(context, hint, hintStyle, constraints.maxWidth)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleText,
              SizedBox(height: gap),
              Text(hint, style: hintStyle),
            ],
          );
        }
        return Row(
          children: [
            Flexible(child: titleText),
            InfoCircleButton(
              title: title,
              message: hint,
              tooltip: context.t('common.moreInfo'),
              compact: true,
            ),
          ],
        );
      },
    );
  }
}
