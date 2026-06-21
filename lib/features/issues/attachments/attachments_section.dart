import 'dart:async';
import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/hinata_repository.dart';
import '../../../core/api/sse.dart';
import '../../../core/blocs/app_config_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'attachment_kind.dart';
import 'attachment_lightbox.dart';
import 'upload_source_sheet.dart';

/// A picked/dropped source file, abstracting file_picker's `PlatformFile` and
/// desktop_drop's `DropItem` into the bits the upload needs.
class _Src {
  _Src({required this.name, required this.size, this.path, this.bytes});
  final String name;
  final int size;
  final String? path;
  final Uint8List? bytes;
}

/// An in-flight (or failed) upload shown optimistically as a tile.
class _Upload {
  _Upload(this.src) : kind = kindFromName(src.name);
  final _Src src;
  final String kind;
  double progress = 0;
  bool failed = false;
  CancelToken cancel = CancelToken();

  String get id => 'up:${identityHashCode(this)}';
}

/// Issue attachments: drag-drop + click upload, a responsive image/file grid
/// with per-tile upload progress, download/remove actions, a Liquid-Glass
/// lightbox, and live sync over SSE. Mirrors `view_attachments.jsx`.
class AttachmentsSection extends StatefulWidget {
  const AttachmentsSection({
    super.key,
    required this.issueId,
    required this.initial,
    this.userNames = const {},
    this.onChanged,
  });

  final String issueId;
  final List<IssueAttachment> initial;
  final Map<String, String> userNames;
  final VoidCallback? onChanged;

  @override
  State<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends State<AttachmentsSection> {
  late List<IssueAttachment> _server = List.of(widget.initial);
  final List<_Upload> _uploads = [];
  final Map<String, Future<String?>> _urlCache = {};

  bool _dragging = false;
  bool _disposed = false;

  CancelToken? _sseCancel;
  StreamSubscription<SseEvent>? _sseSub;
  Timer? _reconnect;
  int _reconnectAttempts = 0;

  HinataRepository get _repo => context.read<HinataRepository>();

  UploadLimits get _limits {
    try {
      return context.read<AppConfigBloc>().state.meta?.uploadLimits ??
          const UploadLimits();
    } catch (_) {
      return const UploadLimits();
    }
  }

  @override
  void initState() {
    super.initState();
    _connectSse();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _sseSub?.cancel();
    _sseCancel?.cancel();
    for (final u in _uploads) {
      if (!u.cancel.isCancelled) u.cancel.cancel();
    }
    super.dispose();
  }

  // ── SSE live sync ─────────────────────────────────────────────────────────
  Future<void> _connectSse() async {
    if (_disposed) return;
    _sseCancel = CancelToken();
    try {
      final bytes = await _repo.attachmentEventStream(
        widget.issueId,
        cancelToken: _sseCancel,
      );
      _reconnectAttempts = 0; // connected — reset the backoff
      _sseSub = parseSse(bytes).listen(
        _onSseEvent,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _sseSub?.cancel();
    _sseSub = null;
    if (_disposed) return;
    _reconnect?.cancel();
    // Exponential backoff (3s → 30s cap) so a persistently failing stream
    // (e.g. SSE not streamable on the web platform) doesn't hammer the server.
    final secs = (3 * (1 << _reconnectAttempts)).clamp(3, 30);
    _reconnectAttempts = (_reconnectAttempts + 1).clamp(0, 4);
    _reconnect = Timer(Duration(seconds: secs), _connectSse);
  }

  void _onSseEvent(SseEvent ev) {
    if (_disposed) return;
    try {
      final data = jsonDecode(ev.data);
      if (ev.event == 'added' && data is Map<String, dynamic>) {
        final att = IssueAttachment.fromJson(data);
        if (!_server.any((a) => a.id == att.id)) {
          setState(() => _server = [..._server, att]);
          widget.onChanged?.call();
        }
      } else if (ev.event == 'removed' && data is Map<String, dynamic>) {
        final id = data['id'] as String?;
        if (id != null && _server.any((a) => a.id == id)) {
          setState(() {
            _server = _server.where((a) => a.id != id).toList();
            _urlCache.remove(id);
          });
          widget.onChanged?.call();
        }
      }
    } catch (_) {
      // Malformed frame — ignore, the next event reconciles state.
    }
  }

  // ── Pick / drop / validate ────────────────────────────────────────────────

  /// Whether to offer the native gallery/camera source chooser. Only touch
  /// platforms have a photo library + camera distinct from the file browser;
  /// desktop and web go straight to the document picker.
  bool get _offersMediaSources =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Entry point for every "add" affordance (header button + empty dropzone).
  /// On mobile it asks the user where to source from; elsewhere it opens the
  /// document picker directly.
  Future<void> _add() async {
    if (!_offersMediaSources) {
      await _pickFiles();
      return;
    }
    final source = await showUploadSourceSheet(context);
    if (source == null || _disposed) return;
    switch (source) {
      case UploadSource.gallery:
        await _pickFromGallery();
      case UploadSource.photo:
        await _capture(ImageSource.camera, video: false);
      case UploadSource.video:
        await _capture(ImageSource.camera, video: true);
      case UploadSource.files:
        await _pickFiles();
    }
  }

  /// System document picker (PDF, Office docs, archives, …). Allows any type and
  /// multiple selection; the kind/size/blocked-extension gate runs in [_enqueue].
  Future<void> _pickFiles() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb, // web has no file path; we need the bytes
      );
    } catch (_) {
      if (mounted) _toast(context.t('issues.attachments.pickFailed'));
      return;
    }
    if (result == null || _disposed) return;
    // On web `PlatformFile.path` throws — only the bytes are available there.
    _enqueue([
      for (final f in result.files)
        _Src(
          name: f.name,
          size: f.size,
          path: kIsWeb ? null : f.path,
          bytes: f.bytes,
        ),
    ]);
  }

  /// Photo library: images *and* videos, multi-select.
  Future<void> _pickFromGallery() async {
    final List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultipleMedia();
    } on Exception {
      if (mounted) _toast(context.t('issues.attachments.pickFailed'));
      return;
    }
    if (picked.isEmpty || _disposed) return;
    final srcs = await Future.wait(picked.map(_srcFromXFile));
    if (!_disposed) _enqueue(srcs);
  }

  /// Camera capture — a single new photo or video.
  Future<void> _capture(ImageSource source, {required bool video}) async {
    final XFile? file;
    try {
      file = video
          ? await ImagePicker().pickVideo(source: source)
          : await ImagePicker().pickImage(source: source);
    } on Exception {
      if (mounted) _toast(context.t('issues.attachments.pickFailed'));
      return;
    }
    if (file == null || _disposed) return;
    _enqueue([await _srcFromXFile(file)]);
  }

  /// Adapts an [XFile] (from image_picker) into the upload's [_Src]. On web
  /// there is no usable path, so the bytes are read eagerly; on native the path
  /// is streamed straight from disk by [_multipart].
  Future<_Src> _srcFromXFile(XFile f) async {
    final bytes = kIsWeb ? await f.readAsBytes() : null;
    final size = bytes?.length ?? await f.length();
    return _Src(
      name: f.name,
      size: size,
      path: kIsWeb ? null : f.path,
      bytes: bytes,
    );
  }

  Future<void> _onDrop(DropDoneDetails detail) async {
    final srcs = <_Src>[];
    for (final item in detail.files) {
      final len = await item.length();
      final bytes = kIsWeb ? await item.readAsBytes() : null;
      srcs.add(_Src(
        name: item.name,
        size: len,
        path: kIsWeb ? null : item.path,
        bytes: bytes,
      ));
    }
    if (!_disposed) _enqueue(srcs);
  }

  void _enqueue(List<_Src> files) {
    if (files.isEmpty) return;
    final limits = _limits;
    final accepted = <_Src>[];
    for (final f in files) {
      if (isBlockedFileName(f.name)) {
        _toast(context.t('issues.attachments.blocked', variables: {'name': f.name}));
        continue;
      }
      if (f.size > limits.maxFileBytes) {
        _toast(context.t('issues.attachments.tooLarge',
            variables: {'name': f.name, 'size': limits.maxFileMb}));
        continue;
      }
      accepted.add(f);
    }
    if (accepted.isEmpty) return;
    if (accepted.length > limits.maxFiles) {
      _toast(context.t('issues.attachments.tooManyFiles',
          variables: {'count': limits.maxFiles}));
      accepted.removeRange(limits.maxFiles, accepted.length);
    }
    final total = accepted.fold<int>(0, (sum, f) => sum + f.size);
    if (total > limits.maxRequestBytes) {
      _toast(context.t('issues.attachments.batchTooLarge',
          variables: {'size': limits.maxRequestMb}));
      return;
    }
    final ups = accepted.map(_Upload.new).toList();
    setState(() => _uploads.insertAll(0, ups));
    for (final u in ups) {
      _startUpload(u);
    }
  }

  Future<void> _startUpload(_Upload u) async {
    try {
      final file = await _multipart(u.src);
      final issue = await _repo.uploadAttachment(
        widget.issueId,
        file,
        cancelToken: u.cancel,
        onProgress: (p) {
          if (!_disposed) setState(() => u.progress = p);
        },
      );
      if (_disposed) return;
      setState(() {
        _server = issue.attachments; // authoritative list (atomic on server)
        _uploads.remove(u);
      });
      widget.onChanged?.call();
    } on ApiFailure catch (e) {
      if (_disposed) return;
      setState(() => u.failed = true);
      _toast(e.message);
    } catch (_) {
      if (_disposed) return;
      setState(() => u.failed = true);
    }
  }

  Future<MultipartFile> _multipart(_Src s) async {
    if (!kIsWeb && (s.path?.isNotEmpty ?? false)) {
      return MultipartFile.fromFile(s.path!, filename: s.name);
    }
    if (s.bytes != null) {
      return MultipartFile.fromBytes(s.bytes!, filename: s.name);
    }
    throw ApiFailure('errors.unexpected');
  }

  void _retry(_Upload u) {
    setState(() {
      u.failed = false;
      u.progress = 0;
      u.cancel = CancelToken();
    });
    _startUpload(u);
  }

  void _cancelUpload(_Upload u) {
    if (!u.cancel.isCancelled) u.cancel.cancel();
    setState(() => _uploads.remove(u));
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Future<String?> _resolveUrl(String id) => _urlCache.putIfAbsent(id, () async {
        try {
          return await _repo.attachmentDownloadUrl(widget.issueId, id);
        } catch (_) {
          return null;
        }
      });

  Future<void> _download(IssueAttachment a) async {
    final url = await _resolveUrl(a.id);
    if (url == null) {
      if (mounted) _toast(context.t('errors.unexpected'));
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _delete(IssueAttachment a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: Text(ctx.t('issues.attachments.removeConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.t('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.t('issues.attachments.remove')),
          ),
        ],
      ),
    );
    if (confirmed != true || _disposed) return;
    final prev = _server;
    setState(() => _server = _server.where((x) => x.id != a.id).toList());
    widget.onChanged?.call();
    try {
      await _repo.deleteAttachment(widget.issueId, a.id);
      _urlCache.remove(a.id);
    } on ApiFailure catch (e) {
      if (_disposed) return;
      setState(() => _server = prev);
      _toast(e.message);
    }
  }

  Future<void> _open(IssueAttachment tapped) async {
    final kind = kindFromName(tapped.fileName, tapped.contentType);
    if (kindIsImage(kind)) {
      final images = _server
          .where((a) => kindIsImage(kindFromName(a.fileName, a.contentType)))
          .toList();
      final urls = await Future.wait(images.map((a) => _resolveUrl(a.id)));
      if (!mounted) return;
      final items = [
        for (var i = 0; i < images.length; i++)
          _toLightboxItem(images[i], urls[i]),
      ];
      final idx = images.indexWhere((a) => a.id == tapped.id);
      await showAttachmentLightbox(
        context,
        items: items,
        initialIndex: idx < 0 ? 0 : idx,
        onDownload: (it) => _downloadById(it.id, it.name),
      );
    } else {
      // PDFs and text/JSON/CSV preview inline too — resolve the presigned URL
      // so the lightbox can fetch the content. Other types just show a card.
      final previewable = kindIsPdf(kind) ||
          isTextPreviewable(tapped.fileName, tapped.contentType);
      final url = previewable ? await _resolveUrl(tapped.id) : null;
      if (!mounted) return;
      await showAttachmentLightbox(
        context,
        items: [_toLightboxItem(tapped, url)],
        initialIndex: 0,
        onDownload: (it) => _downloadById(it.id, it.name),
      );
    }
  }

  Future<void> _downloadById(String id, String name) async {
    final att = _server.firstWhere(
      (a) => a.id == id,
      orElse: () => IssueAttachment(id: id, fileName: name, size: 0),
    );
    await _download(att);
  }

  LightboxItem _toLightboxItem(IssueAttachment a, String? url) {
    final kind = kindFromName(a.fileName, a.contentType);
    return LightboxItem(
      id: a.id,
      name: a.fileName,
      kind: kind,
      size: a.size,
      url: url,
      mime: a.contentType,
      subtitle: _subtitle(a),
    );
  }

  String _subtitle(IssueAttachment a) {
    final parts = <String>[formatBytes(a.size)];
    final by = a.uploaderId == null ? null : widget.userNames[a.uploaderId];
    if (by != null && by.isNotEmpty) parts.add(by);
    if (a.uploadedAt != null) {
      parts.add('${relativeAge(a.uploadedAt!.toLocal())} ago');
    }
    return parts.join(' · ');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final count = _server.length + _uploads.length;
    final phone = MediaQuery.sizeOf(context).width < 610;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(count),
        const SizedBox(height: 12),
        DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (d) {
            setState(() => _dragging = false);
            _onDrop(d);
          },
          child: Stack(
            children: [
              if (count == 0) _empty() else _grid(phone),
              if (_dragging)
                Positioned.fill(child: const _DropOverlay()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(int count) {
    return Row(
      children: [
        Text(
          context.t('issues.attachments.title').toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.inkFaint,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.canvas2,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
        const Spacer(),
        // Always-available add affordance (the empty dropzone only shows when
        // there are no attachments yet).
        if (count > 0)
          _AddButton(
            onTap: _add,
            label: context.t('issues.attachments.add'),
          ),
      ],
    );
  }

  Widget _empty() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: _add,
      child: DottedBorderBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.canvas2,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(LucideIcons.paperclip,
                    size: 18, color: AppColors.inkSoft),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.t('issues.attachments.emptyTitle'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      context.t('issues.attachments.emptyHint',
                          variables: {'size': _limits.maxFileMb}),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.inkFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(bool phone) {
    final extent = phone ? 140.0 : 168.0;
    final mainAxisExtent = (extent * 10 / 16).ceilToDouble() + 56;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: extent,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: mainAxisExtent,
      ),
      itemCount: _uploads.length + _server.length,
      itemBuilder: (context, i) {
        if (i < _uploads.length) {
          final u = _uploads[i];
          return _AttachmentTile.uploading(
            upload: u,
            onRetry: () => _retry(u),
            onCancel: () => _cancelUpload(u),
          );
        }
        // Server attachments newest-first below the in-flight uploads.
        final a = _server[_server.length - 1 - (i - _uploads.length)];
        return _AttachmentTile.done(
          attachment: a,
          subtitle: _subtitle(a),
          resolveImageUrl: _resolveUrl,
          onOpen: () => _open(a),
          onDownload: () => _download(a),
          onDelete: () => _delete(a),
        );
      },
    );
  }
}

// ════════════════════════════ Tile ════════════════════════════════════════
class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile.uploading({
    required this.upload,
    required this.onRetry,
    required this.onCancel,
  })  : attachment = null,
        subtitle = '',
        resolveImageUrl = null,
        onOpen = null,
        onDownload = null,
        onDelete = null;

  const _AttachmentTile.done({
    required this.attachment,
    required this.subtitle,
    required this.resolveImageUrl,
    required this.onOpen,
    required this.onDownload,
    required this.onDelete,
  })  : upload = null,
        onRetry = null,
        onCancel = null;

  final _Upload? upload;
  final IssueAttachment? attachment;
  final String subtitle;
  final Future<String?> Function(String id)? resolveImageUrl;
  final VoidCallback? onOpen;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _hover = false;

  bool get _touch {
    final p = Theme.of(context).platform;
    return p == TargetPlatform.iOS || p == TargetPlatform.android;
  }

  @override
  Widget build(BuildContext context) {
    final up = widget.upload;
    final att = widget.attachment;
    final name = up?.src.name ?? att!.fileName;
    final size = up?.src.size ?? att!.size;
    final kind = up?.kind ?? kindFromName(att!.fileName, att.contentType);
    final km = kindMeta(kind);
    final showActions = att != null && (_hover || _touch);

    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: _hover ? AppColors.accentLine : AppColors.hairline,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumb / preview.
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _thumb(att, kind, km),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _KindTag(label: kindTag(kind, name)),
                  ),
                  if (up != null) _progressOverlay(up),
                ],
              ),
            ),
            // Meta footer.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      up != null ? formatBytes(size) : widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 10.5, color: AppColors.inkFaint),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor:
          att != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Stack(
          children: [
            tile,
            if (showActions)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    _TileAction(
                      icon: LucideIcons.download,
                      tooltip: context.t('issues.attachments.download'),
                      onTap: widget.onDownload!,
                    ),
                    const SizedBox(width: 6),
                    _TileAction(
                      icon: LucideIcons.trash2,
                      tooltip: context.t('issues.attachments.remove'),
                      danger: true,
                      onTap: widget.onDelete!,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(IssueAttachment? att, String kind, AttachmentKindMeta km) {
    final glyph = ColoredBox(
      color: AppColors.canvas2,
      child: Center(
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: km.color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(km.icon, size: 22, color: Colors.white),
        ),
      ),
    );
    if (att == null || !kindIsImage(kind) || widget.resolveImageUrl == null) {
      return glyph;
    }
    return FutureBuilder<String?>(
      future: widget.resolveImageUrl!(att.id),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) return glyph;
        return Image.network(
          url,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => glyph,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : glyph,
        );
      },
    );
  }

  Widget _progressOverlay(_Upload up) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.82),
        ),
        child: Center(
          child: up.failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TileAction(
                          icon: LucideIcons.refreshCw,
                          tooltip: context.t('issues.attachments.retry'),
                          onTap: widget.onRetry!,
                        ),
                        const SizedBox(width: 6),
                        _TileAction(
                          icon: LucideIcons.x,
                          tooltip: context.t('common.cancel'),
                          danger: true,
                          onTap: widget.onCancel!,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('issues.attachments.uploadFailed'),
                      style: TextStyle(
                          fontSize: 11, color: AppColors.danger),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: up.progress <= 0 ? null : up.progress,
                        strokeWidth: 4,
                        backgroundColor: AppColors.hairline,
                        valueColor: AlwaysStoppedAnimation(
                            AppColors.accentStrong),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(up.progress * 100).round()}%',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _KindTag extends StatelessWidget {
  const _KindTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF14122D).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TileAction extends StatelessWidget {
  const _TileAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
        ),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            onTap();
          },
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon,
                size: 15, color: danger ? AppColors.danger : AppColors.ink),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════ Chrome ══════════════════════════════════════
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap, required this.label});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: const BorderSide(color: AppColors.accentLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.paperclip,
                  size: 14, color: AppColors.accentStrong),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.accentSoft.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: AppColors.accent,
          width: 2,
          style: BorderStyle.solid,
        ),
      ),
      // Scale the contents down when the zone is shorter than the icon+label
      // stack (e.g. the compact empty dropzone) so the overlay never overflows.
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.5),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(LucideIcons.cloudUpload,
                      size: 22, color: AppColors.accentStrong),
                ),
                const SizedBox(height: 8),
                Text(
                  context.t('issues.attachments.dropHere'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentStrong,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed-border rounded box for the empty dropzone (Flutter has no native
/// dashed border, so it is painted).
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: AppColors.hairline,
        radius: AppTheme.radiusCard,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + dash).clamp(0, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
