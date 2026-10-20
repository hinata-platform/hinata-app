import 'dart:typed_data';

/// The files an event's shift plan comes out as (HIN-163).
enum ShiftPlanFormat {
  pdf('pdf', 'application/pdf'),
  docx(
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  xlsx(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );

  const ShiftPlanFormat(this.extension, this.mimeType);

  /// The `format` parameter and the file's extension.
  final String extension;
  final String mimeType;
}

/// A shift plan fetched into memory.
///
/// [fileName] is the name the server put in `Content-Disposition`, null when
/// the response carried none. [truncated] says the server stopped at the
/// format's ceiling and said so in the file.
class ShiftPlanFile {
  const ShiftPlanFile({
    required this.bytes,
    this.truncated = false,
    this.fileName,
  });

  final Uint8List bytes;
  final bool truncated;
  final String? fileName;
}

/// The file name out of a `Content-Disposition` header, or null.
///
/// Prefers the RFC 5987 `filename*=UTF-8''…` form, which is the one that
/// carries umlauts and other scripts intact; the plain `filename="…"` is taken
/// only when it is not an RFC 2047 encoded word. Anything with a path in it is
/// cut to its last segment, so a header can never point outside the folder
/// the file is saved in.
String? fileNameFromDisposition(String? header) {
  if (header == null || header.isEmpty) return null;
  String? found;
  final extended = RegExp(
    r"""filename\*\s*=\s*([^']*)'[^']*'([^;]+)""",
    caseSensitive: false,
  ).firstMatch(header);
  if (extended != null) {
    try {
      found = Uri.decodeComponent(extended.group(2)!.trim());
    } on ArgumentError {
      found = null;
    }
  }
  if (found == null) {
    final plain = RegExp(
      r'filename\s*=\s*"([^"]*)"|filename\s*=\s*([^;\s]+)',
      caseSensitive: false,
    ).firstMatch(header);
    final value = (plain?.group(1) ?? plain?.group(2))?.trim();
    if (value != null && !value.startsWith('=?')) found = value;
  }
  final name = found?.split(RegExp(r'[/\\]')).last.trim();
  return name == null || name.isEmpty || name == '.' || name == '..'
      ? null
      : name;
}

/// Longest stem of the event title in a file name: the server's own ceiling,
/// so both sides cut a long title at the same place.
const int _kTitleChars = 80;

/// The plan's file name by the rule the server names it with:
/// `<word>-<title slug>-<yyyyMMdd>.<ext>`, [word] in the caller's language,
/// the date the event's first day in its own zone ([startsLocal]).
///
/// For the paths that have to name the file before the answer arrives (a file
/// streamed to disk), and as the fallback when a response names none.
String shiftPlanFileName({
  required String word,
  required String title,
  required DateTime startsLocal,
  required ShiftPlanFormat format,
}) {
  var stem = title
      .trim()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (stem.length > _kTitleChars) {
    stem = stem.substring(0, _kTitleChars).replaceAll(RegExp(r'-+$'), '');
  }
  String two(int n) => n.toString().padLeft(2, '0');
  final day =
      '${startsLocal.year.toString().padLeft(4, '0')}'
      '${two(startsLocal.month)}${two(startsLocal.day)}';
  return '$word-${stem.isEmpty ? 'event' : stem}-$day.${format.extension}';
}
