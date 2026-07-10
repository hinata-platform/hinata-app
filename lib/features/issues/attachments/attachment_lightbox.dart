import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import 'package:printing/printing.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../search/search_tokens.dart';
import 'attachment_kind.dart';

/// Largest text file we'll fetch and render inline. Bigger files fall back to
/// the type card so we never pull a huge blob into memory just for a preview.
const int kMaxTextPreviewBytes = 2 * 1024 * 1024;

/// One entry shown in the lightbox. [url] is a resolved (presigned) URL used to
/// fetch the content for inline previews (images, PDFs, text); types we can't
/// preview render a type card instead.
class LightboxItem {
  const LightboxItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.size,
    this.url,
    this.mime,
    this.subtitle,
  });

  final String id;
  final String name;
  final String kind;
  final int size;
  final String? url;
  final String? mime;
  final String? subtitle;

  bool get isImage => kindIsImage(kind) && url != null;

  bool get isPdf => kindIsPdf(kind) && url != null;

  bool get isText =>
      url != null &&
      size <= kMaxTextPreviewBytes &&
      isTextPreviewable(name, mime);
}

/// Fetches an attachment's raw bytes through the authenticated [ApiClient] from
/// the server's `/download` endpoint. The object store is internal-only, so the
/// client never talks to it directly; [LightboxItem.url] holds the relative API
/// download path, not a storage URL.
Future<Uint8List> _fetchBytes(BuildContext context, String path) async {
  final res = await context.read<ApiClient>().getBytes(path);
  return Uint8List.fromList(res?.bytes ?? const []);
}

/// Opens the Liquid-Glass image lightbox (radius 22, blurred scrim, spring
/// entrance), paging across [items] from [initialIndex]. Mirrors the web
/// `Lightbox`: ←/→ + on-screen prev/next, Esc / tap-out to close, download.
Future<void> showAttachmentLightbox(
  BuildContext context, {
  required List<LightboxItem> items,
  required int initialIndex,
  required Future<void> Function(LightboxItem item) onDownload,
}) {
  if (items.isEmpty) return Future<void>.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, _, _) => _LightboxScaffold(
      items: items,
      initialIndex: initialIndex.clamp(0, items.length - 1),
      onDownload: onDownload,
    ),
    transitionBuilder: (_, _, _, child) => child,
  );
}

class _LightboxScaffold extends StatefulWidget {
  const _LightboxScaffold({
    required this.items,
    required this.initialIndex,
    required this.onDownload,
  });

  final List<LightboxItem> items;
  final int initialIndex;
  final Future<void> Function(LightboxItem item) onDownload;

  @override
  State<_LightboxScaffold> createState() => _LightboxScaffoldState();
}

class _LightboxScaffoldState extends State<_LightboxScaffold> {
  late int _index = widget.initialIndex;
  late final PageController _page = PageController(initialPage: _index);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _page.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0 || i >= widget.items.length) return;
    setState(() => _index = i);
    _page.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(_index + 1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(_index - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final phone = size.width < 610;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final anim = ModalRoute.of(context)!.animation!;
    final items = widget.items;
    final cur = items[_index];
    final multi = items.length > 1;

    final maxW = phone ? size.width - 24 : 880.0;
    final maxH = size.height * 0.88;

    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
      child: GlassPanelShadow(
        radius: BorderRadius.circular(22),
        shadows: tokens.panelShadow,
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          clipBehavior: Clip.antiAlias,
          shape: const LiquidRoundedSuperellipse(borderRadius: 22),
          // A touch more frost than the standard panel — this chrome sits
          // over full-bleed photos.
          settings: liquidGlassPanelSettings(
            glassFill: tokens.glassFill,
            dark: Theme.of(context).brightness == Brightness.dark,
            blur: 12,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: _stage(items)),
                    _bar(cur),
                  ],
                ),
                if (multi)
                  Positioned(
                    top: 14,
                    left: 16,
                    child: _Counter(label: '${_index + 1} / ${items.length}'),
                  ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: _GlassIconButton(
                    icon: LucideIcons.x,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                if (multi) ...[
                  Positioned(
                    left: 12,
                    top: 0,
                    bottom: 56,
                    child: Center(
                      child: _NavButton(
                        icon: LucideIcons.chevronLeft,
                        enabled: _index > 0,
                        onTap: () => _go(_index - 1),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 0,
                    bottom: 56,
                    child: Center(
                      child: _NavButton(
                        icon: LucideIcons.chevronRight,
                        enabled: _index < items.length - 1,
                        onTap: () => _go(_index + 1),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: anim,
            builder: (_, _) {
              final t = anim.value.clamp(0.0, 1.0);
              Widget scrim = ColoredBox(
                color: const Color(0xFF100E22).withValues(alpha: 0.46 * t),
                child: const SizedBox.expand(),
              );
              if (!reduceMotion) {
                scrim = BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12 * t, sigmaY: 12 * t),
                  child: scrim,
                );
              }
              return Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: scrim,
                ),
              );
            },
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(phone ? 12 : 28),
                  child: AnimatedBuilder(
                    animation: anim,
                    builder: (_, child) {
                      if (reduceMotion) {
                        return Opacity(opacity: anim.value, child: child);
                      }
                      final curved = const Cubic(0.34, 1.56, 0.64, 1)
                          .transform(anim.value.clamp(0.0, 1.0));
                      final fade = (anim.value / 0.6).clamp(0.0, 1.0);
                      return Opacity(
                        opacity: fade,
                        child: Transform.translate(
                          offset: Offset(0, (1 - curved) * 8),
                          child: Transform.scale(
                            scale: 0.95 + 0.05 * curved,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: GestureDetector(
                      onTap: () {},
                      behavior: HitTestBehavior.opaque,
                      child: panel,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stage(List<LightboxItem> items) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0x0F23223F)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: 220,
          maxHeight: MediaQuery.sizeOf(context).height * 0.64,
        ),
        child: PageView.builder(
          controller: _page,
          physics: items.length > 1
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          onPageChanged: (i) => setState(() => _index = i),
          itemCount: items.length,
          itemBuilder: (_, i) => _StagePage(item: items[i]),
        ),
      ),
    );
  }

  Widget _bar(LightboxItem cur) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cur.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cur.subtitle ?? formatBytes(cur.size),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _GlassIconButton(
            icon: LucideIcons.download,
            onTap: () => widget.onDownload(cur),
          ),
        ],
      ),
    );
  }
}

class _StagePage extends StatelessWidget {
  const _StagePage({required this.item});
  final LightboxItem item;

  @override
  Widget build(BuildContext context) {
    if (item.isImage) return _ImagePage(item: item);
    if (item.isPdf) return _PdfPage(item: item);
    if (item.isText) return _TextPage(item: item);
    return _FileCard(item: item);
  }
}

/// Inline image preview — fetches the bytes once through the authenticated
/// endpoint and renders them with [Image.memory].
class _ImagePage extends StatefulWidget {
  const _ImagePage({required this.item});
  final LightboxItem item;

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage> {
  Future<Uint8List>? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= _fetchBytes(context, widget.item.url!);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            final bytes = snap.data;
            if (bytes == null || bytes.isEmpty) {
              return _FileCard(item: widget.item);
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => _FileCard(item: widget.item),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Renders a PDF inline by rasterizing its pages (via the `printing` package's
/// platform renderer) into a vertically scrollable preview. The toolbar/actions
/// are hidden — download lives in the lightbox bar.
class _PdfPage extends StatefulWidget {
  const _PdfPage({required this.item});
  final LightboxItem item;

  @override
  State<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<_PdfPage> {
  // Fetch once; PdfPreview's build callback can fire repeatedly on relayout.
  Future<Uint8List>? _bytes;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= _fetchBytes(context, widget.item.url!);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _FileCard(item: widget.item);
    return PdfPreview(
      build: (_) => _bytes!,
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      allowPrinting: false,
      allowSharing: false,
      scrollViewDecoration: const BoxDecoration(color: Color(0x0F23223F)),
      pdfPreviewPageDecoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14122D).withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      loadingWidget: const Padding(
        padding: EdgeInsets.all(40),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      onError: (context, error) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _failed = true);
        });
        return _FileCard(item: widget.item);
      },
    );
  }
}

/// Fetches a text/JSON/CSV file and renders it as scrollable, selectable
/// monospace text. JSON is pretty-printed when it parses cleanly.
class _TextPage extends StatefulWidget {
  const _TextPage({required this.item});
  final LightboxItem item;

  @override
  State<_TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<_TextPage> {
  Future<String>? _text;
  final _scroll = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _text ??= _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<String> _load() async {
    final bytes = await _fetchBytes(context, widget.item.url!);
    // allowMalformed so a stray byte doesn't blow up the whole preview.
    final raw = utf8.decode(bytes, allowMalformed: true);
    return _maybePrettyJson(widget.item, raw);
  }

  static String _maybePrettyJson(LightboxItem item, String raw) {
    final isJson = (item.mime == 'application/json') ||
        item.name.toLowerCase().endsWith('.json');
    if (!isJson) return raw;
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw; // not valid JSON — show it verbatim
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _text,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snap.hasError) return _FileCard(item: widget.item);
        final text = snap.data ?? '';
        if (text.trim().isEmpty) return _FileCard(item: widget.item);
        return ColoredBox(
          color: const Color(0x0F23223F),
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.item});
  final LightboxItem item;

  @override
  Widget build(BuildContext context) {
    final km = kindMeta(item.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: km.color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(km.icon, size: 34, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(
            item.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.kind.toUpperCase()} · ${formatBytes(item.size)}',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 6),
          Text(
            context.t('issues.attachments.noPreview'),
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF14122D).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0,
      duration: const Duration(milliseconds: 140),
      child: IgnorePointer(
        ignoring: !enabled,
        child: Material(
          color: AppColors.surface.withValues(alpha: 0.55),
          shape: CircleBorder(
            side: BorderSide(color: AppColors.hairline.withValues(alpha: 0.7)),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, size: 22, color: AppColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}
