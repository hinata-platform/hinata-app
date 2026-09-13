import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/lexical/hinata_markdown_preview.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// The operator's privacy notice for the time-tracking module, as Markdown with
/// a live preview.
///
/// Markdown because that is what the server stores and what every client renders
/// — the built-in template is Markdown too, in nine languages. The preview is the
/// app's Lexical rendering of it (`HinataMarkdownPreview`), the same conversion the
/// sheet uses when a member opens the notice, so what the operator sees here is
/// what everybody else will read. The rich editor has no Markdown output, and a
/// second conversion would be a second opinion on the same text.
///
/// Holds its own controller and reports quietly: rebuilding the whole admin
/// section on every keystroke repaints two dozen policy controls under the
/// shell's blur and changes nothing on screen. Only the preview follows the text,
/// and it follows it a moment later.
class AdminPrivacyNoticeField extends StatefulWidget {
  const AdminPrivacyNoticeField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;

  /// Null when the field is empty, which means "the built-in template".
  final ValueChanged<String?> onChanged;

  /// Mirrors the server's limit on the stored notice.
  static const maxLength = 20000;

  @override
  State<AdminPrivacyNoticeField> createState() =>
      _AdminPrivacyNoticeFieldState();
}

class _AdminPrivacyNoticeFieldState extends State<AdminPrivacyNoticeField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value ?? '',
  );
  late String _preview = _text.text;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String text) {
    widget.onChanged(text.trim().isEmpty ? null : text);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _preview = text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          minLines: 6,
          maxLines: 14,
          maxLength: AdminPrivacyNoticeField.maxLength,
          keyboardType: TextInputType.multiline,
          onChanged: _changed,
          decoration: InputDecoration(
            labelText: context.t('admin.timeTracking.privacyNoticeLabel'),
            helperText: context.t('admin.timeTracking.privacyNoticeHint'),
            helperMaxLines: 4,
            alignLabelWithHint: true,
          ),
        ),
        if (_preview.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            context.t('admin.timeTracking.privacyNoticePreview'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: HinataMarkdownPreview(markdown: _preview, fontSize: 13.5),
          ),
        ],
      ],
    );
  }
}
