import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:web/web.dart' as web;

import 'file_download_types.dart';

/// Web: there is no path to stream a file to, so a caller fetches the bytes and
/// uses [downloadBytes] instead.
Future<DownloadResult> downloadFile(
  String filename,
  String mimeType,
  Future<void> Function(String path) fetch, {
  Rect? sharePositionOrigin,
}) => throw UnsupportedError(
  'downloadFile streams to a path, which the web does not have; use downloadBytes',
);

/// Web: trigger a browser download via an in-memory Blob + a temporary
/// download anchor. The browser owns the save dialog, so [sharePositionOrigin]
/// is ignored here.
Future<DownloadResult> downloadBytes(
  String filename,
  Uint8List bytes,
  String mimeType, {
  Rect? sharePositionOrigin,
}) async {
  final type = mimeType.isEmpty ? 'application/octet-stream' : mimeType;
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: type));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return DownloadResult.browser;
}
