import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../../core/api/hinata_repository.dart';
import '../../../core/models/work_models.dart';

/// What a comment copy actually put on the clipboard.
enum CommentCopyKind { text, image }

/// A comment whose entire body is a single inline image `![alt](url)`.
final _singleImage = RegExp(r'^\s*!\[[^\]]*\]\(([^)]+)\)\s*$');

/// Copies a comment to the OS clipboard: a comment that is just one inline image
/// copies as the actual image bytes (via super_clipboard); anything else copies
/// its text/markdown. Voice comments are never copied (the caller hides the
/// action). Falls back to text if the image can't be fetched or the platform
/// lacks a rich clipboard.
Future<CommentCopyKind> copyComment(
  HinataRepository repo,
  IssueComment comment,
) async {
  final url = _singleImage.firstMatch(comment.text)?.group(1);
  if (url != null) {
    final copied = await _copyImage(repo, url);
    if (copied) return CommentCopyKind.image;
  }
  await Clipboard.setData(ClipboardData(text: comment.text));
  return CommentCopyKind.text;
}

Future<bool> _copyImage(HinataRepository repo, String url) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return false; // platform without a rich clipboard
  try {
    final data = await repo.mediaBytes(url);
    if (data == null || data.bytes.isEmpty) return false;
    final bytes = Uint8List.fromList(data.bytes);
    final ct = data.contentType.toLowerCase();
    final item = DataWriterItem();
    if (ct.contains('jpeg') || ct.contains('jpg')) {
      item.add(Formats.jpeg(bytes));
    } else if (ct.contains('gif')) {
      item.add(Formats.gif(bytes));
    } else {
      // Default to PNG (covers png/webp/others most viewers accept).
      item.add(Formats.png(bytes));
    }
    await clipboard.write([item]);
    return true;
  } catch (_) {
    return false;
  }
}
