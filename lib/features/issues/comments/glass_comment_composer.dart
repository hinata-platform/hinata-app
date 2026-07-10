import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        GlassButton,
        GlassContainer,
        GlassMenuAlignment,
        GlassPopover,
        GlassQuality,
        LiquidGlassSettings,
        LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/markdown_toolbar.dart';
import '../../knowledge/markdown/markdown_renderer.dart';
import '../../knowledge/markdown/mention_field.dart';
import 'voice/voice_recorder.dart';

/// The composer floats over the scrolling comment feed (phone sticky bar /
/// desktop panel footer), so — unlike the bottom nav, which sits over the solid
/// canvas — its glass must be far more **opaque** or the feed bleeds through and
/// the input becomes unreadable. Same refraction/lighting as the nav preset, but
/// a strong tint (dark slate / near-solid frost) so the field + buttons read
/// clearly in both themes. See `kNavGlassDark/Light` for the transparent siblings.
const _composerGlassDark = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345, // 0.75π — Apple key light
  glassColor: Color(0xD91A1A22), // ~0.85 opaque dark slate
);
const _composerGlassLight = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345, // 0.75π — Apple key light
  glassColor: Color(0xF2FFFFFF), // ~0.95 near-solid frost
);

LiquidGlassSettings _composerGlass(bool dark) =>
    dark ? _composerGlassDark : _composerGlassLight;

/// A rounded composer surface (field pill, popup, recording bar, format editor).
///
/// Always real Liquid Glass — but pinned to [GlassQuality.standard] (the
/// lightweight fragment shader with universal Skia/Impeller/Web support that
/// renders correctly while scrolling). The default `premium` Impeller pipeline
/// is unreadable in dark mode (its refraction samples the dark feed → dark-on-
/// dark) and its captured texture corrupts on device rotation — the composer
/// floats over a scrolling feed, exactly the context `premium` warns against.
/// The strong [_composerGlass] tint then keeps the field legible in both themes.
Widget _composerSurface({
  required bool dark,
  required double radius,
  required Widget child,
  EdgeInsetsGeometry? padding,
  double? width,
  double? height,
}) {
  return GlassContainer(
    width: width,
    height: height,
    useOwnLayer: true,
    quality: GlassQuality.standard,
    settings: _composerGlass(dark),
    clipBehavior: Clip.antiAlias,
    shape: LiquidRoundedSuperellipse(borderRadius: radius),
    padding: padding,
    child: child,
  );
}

const Color _onAccent = Color(0xFF2A2410);

/// Round composer button size. On phones it's a fat 52 touch target; on the
/// wider tablet/desktop/web layouts (macOS + Web included) the composer is
/// pointer-driven, so we trim the [+]/mic/send circles a touch — at 52 they
/// read too large next to the field pill. Keyed off the same compact-width
/// signal the comment thread uses to split phone-chat from desktop layout.
double _composerButtonSize(BuildContext context) => context.isCompact ? 52 : 46;

/// Attachment sources offered by the composer's "+" menu.
enum ComposerAttach { camera, gallery, file }

/// The Liquid-Glass comment composer from the design. Morphs through:
///   • idle     → [+] · field · mic
///   • typing   → mic becomes the honey-amber send button
///   • popup    → glass "+" menu (camera / gallery / attachment / format)
///   • format   → grows *in place* into a Markdown editor (Edit/Preview switch,
///                drag-to-resize, toolbar pinned) — no modal. Because the
///                composer is always bottom-anchored in its region (the phone
///                sticky bar or the desktop comment panel's footer), the editor
///                expands *upward* with the toolbar staying put.
///   • recording → live-waveform voice recorder with cancel / send
///
/// It wraps a [MentionField] so `@`-mentions and smart-links keep working, and
/// drives formatting through the shared [MarkdownEditingActions]. The parent
/// owns the [controller] (so it can read/clear the text on submit) and handles
/// attachment picking + voice/text sending via the callbacks. When [editing] is
/// set, the composer is editing an existing comment inline — it shows a banner
/// and the parent's submit saves the edit.
class GlassCommentComposer extends StatefulWidget {
  const GlassCommentComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.actions,
    required this.onSubmitText,
    required this.onSendVoice,
    required this.onAttach,
    this.editing = false,
    this.onCancelEdit,
    this.replyingToName,
    this.replyingToPreview,
    this.onCancelReply,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final MarkdownEditingActions actions;
  final VoidCallback onSubmitText;
  final void Function(VoiceRecording recording) onSendVoice;
  final void Function(ComposerAttach kind) onAttach;

  /// True while editing an existing comment inline (shows the edit banner).
  final bool editing;
  final VoidCallback? onCancelEdit;

  /// When set, a WhatsApp-style "replying to …" quote bar floats above the
  /// field; the parent's submit attaches the reply.
  final String? replyingToName;
  final String? replyingToPreview;
  final VoidCallback? onCancelReply;

  final bool enabled;

  @override
  State<GlassCommentComposer> createState() => _GlassCommentComposerState();
}

enum _Mode { idle, recording, format }

class _GlassCommentComposerState extends State<GlassCommentComposer> {
  _Mode _mode = _Mode.idle;

  // Format mode: the drag-resizable field height + the Edit/Preview toggle.
  double _formatHeight = 200;
  bool _preview = false;

  VoiceRecorder? _recorder;
  Timer? _recTimer;
  Duration _recElapsed = Duration.zero;
  bool _starting = false;

  bool get _canSend => widget.controller.text.trim().isNotEmpty;

  // Last computed send-ability, so a keystroke only rebuilds this composer (which
  // hosts liquid-glass buttons) when the mic↔send affordance actually flips —
  // not on every character. Typing rebuilt the glass buttons per keystroke
  // before, a measurable source of input lag in the comment field.
  bool _sendable = false;

  @override
  void initState() {
    super.initState();
    _sendable = _canSend;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _recTimer?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Rebuild only when the mic↔send swap actually changes (empty ↔ non-empty),
    // not on every keystroke.
    final sendable = _canSend;
    if (sendable == _sendable) return;
    _sendable = sendable;
    if (mounted) setState(() {});
  }

  // ── recording ──────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (_starting) return;
    _starting = true;
    final recorder = VoiceRecorder();
    bool ok;
    try {
      ok = await recorder.start();
    } catch (_) {
      // Some platforms throw instead of returning false when the mic is
      // unavailable (e.g. no device / permission race) — treat as denied.
      ok = false;
    }
    _starting = false;
    if (!ok) {
      await recorder.dispose();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.t('comments.micDenied'))),
        );
      }
      return;
    }
    _recorder = recorder;
    _recElapsed = Duration.zero;
    _recTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() => _recElapsed += const Duration(milliseconds: 100));
      }
    });
    if (mounted) setState(() => _mode = _Mode.recording);
  }

  Future<void> _cancelRecording() async {
    _recTimer?.cancel();
    final r = _recorder;
    _recorder = null;
    if (mounted) setState(() => _mode = _Mode.idle);
    await r?.cancel();
    await r?.dispose();
  }

  Future<void> _sendRecording() async {
    _recTimer?.cancel();
    final r = _recorder;
    _recorder = null;
    if (mounted) setState(() => _mode = _Mode.idle);
    if (r == null) return;
    final recording = await r.stop();
    await r.dispose();
    if (recording != null && recording.durationMs > 300) {
      widget.onSendVoice(recording);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == _Mode.recording) {
      return _RecordingBar(
        elapsed: _recElapsed,
        amplitude: _recorder?.liveAmplitude ?? const Stream.empty(),
        buttonSize: _composerButtonSize(context),
        onCancel: _cancelRecording,
        onSend: _sendRecording,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.editing)
          _EditingBanner(onCancel: widget.onCancelEdit ?? () {}),
        if (!widget.editing && widget.replyingToName != null)
          _ReplyBanner(
            name: widget.replyingToName!,
            preview: widget.replyingToPreview ?? '',
            onCancel: widget.onCancelReply ?? () {},
          ),
        if (_mode == _Mode.format) _formatEditor(context) else _idleRow(),
      ],
    );
  }

  /// The single-line composer row: [+] · field · mic/send. While editing an
  /// existing comment, the leading "+" becomes an "×" that abandons the edit.
  Widget _idleRow() {
    return Row(
      // Single-line field and the buttons share one baseline; when the
      // field grows, buttons stay pinned to the bottom edge.
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _leadingButton(),
        const SizedBox(width: 10),
        Expanded(child: _fieldPill()),
        const SizedBox(width: 10),
        _trailingButton(),
      ],
    );
  }

  /// Leading circle: an "×" cancel-edit button while editing, otherwise the "+"
  /// attachment menu trigger.
  ///
  /// The "+" is wrapped in a [GlassPopover] so the attachment menu opens with
  /// the package's full iOS-26 dual-blob metaball morph — the glass literally
  /// pulls a teardrop neck out of the button and rubber-bands into the panel
  /// (and collapses back on close), instead of a plain scale/fade. The popover
  /// owns its own overlay, spring physics, positioning and screen-edge
  /// clamping; we only feed it the trigger, the content, and our dark composer
  /// glass so it matches the rest of the chrome. Pinned to
  /// [GlassMenuAlignment.bottomLeft] so it always grows upward-left out of the
  /// button (the composer is bottom-anchored), never downward over the field.
  Widget _leadingButton() {
    final size = _composerButtonSize(context);
    if (widget.editing) {
      return _CircleButton(
        icon: LucideIcons.x,
        size: size,
        onTap: widget.enabled ? widget.onCancelEdit : null,
      );
    }
    final dark = AppColors.brightness == Brightness.dark;
    return GlassPopover(
      alignment: GlassMenuAlignment.bottomLeft,
      popoverWidth: 268,
      popoverBorderRadius: 24,
      // Same near-opaque dark-slate / frost tint as the rest of the composer so
      // the morphing panel reads identically to the field pill and "+" menu of
      // old — the metaball just adds the liquid growth on top.
      settings: _composerGlass(dark),
      // The metaball neck (SDF blend of the two blobs) only renders on the
      // premium Impeller pipeline; standard silently drops the blend. This is a
      // transient, heavily-tinted overlay (not a surface floating over the
      // scrolling feed), so the usual reasons the composer avoids premium don't
      // apply here — and it degrades gracefully to a plain morph on Skia/web.
      quality: GlassQuality.premium,
      triggerBuilder: (context, toggle) => _CircleButton(
        icon: LucideIcons.plus,
        size: size,
        onTap: widget.enabled ? toggle : null,
      ),
      contentBuilder: (context, close) => _ActionPopup(
        onPick: (kind) {
          close();
          widget.onAttach(kind);
        },
        onFormat: () {
          close();
          _openFormat();
        },
      ),
    );
  }

  /// A single-line glass pill the same height (52) as the buttons; it grows a
  /// little as you type. Short placeholder so the empty state stays on one line.
  Widget _fieldPill() {
    final dark = AppColors.brightness == Brightness.dark;
    return _composerSurface(
      dark: dark,
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: MentionField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        commentMode: true,
        minLines: 1,
        maxLines: 5,
        hintText: context.t('comments.placeholder'),
        onSubmit: _submitText,
      ),
    );
  }

  Widget _trailingButton() {
    final size = _composerButtonSize(context);
    if (_canSend) {
      return _CircleButton(
        icon: LucideIcons.send,
        size: size,
        send: true,
        onTap: widget.enabled ? _submitText : null,
      );
    }
    return _CircleButton(
      icon: LucideIcons.mic,
      size: size,
      onTap: widget.enabled ? _startRecording : null,
    );
  }

  void _submitText() {
    if (!_canSend) return;
    widget.onSubmitText();
  }

  /// Enters the inline Markdown editor. It replaces the single-line row and,
  /// because the composer is bottom-anchored in its region, grows *upward* when
  /// the drag handle is pulled — the toolbar stays pinned at the bottom.
  void _openFormat() {
    setState(() {
      _mode = _Mode.format;
      _preview = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  /// Collapses the editor back to the single-line pill.
  void _closeFormat() {
    if (mounted) setState(() => _mode = _Mode.idle);
  }

  /// The inline Markdown editor shown in format mode. Layout (top→bottom):
  /// drag handle + Edit/Preview switch · resizable field/preview · pinned
  /// toolbar. Bottom-anchored in its parent, so growing the field pushes the
  /// handle up while the toolbar stays put.
  Widget _formatEditor(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    // Cap the field so the editor can't overrun its region — the phone sticky
    // bar or the desktop comment panel, whose height tracks the same viewport
    // fraction (mind the keyboard).
    final maxField = (media.size.height * 0.34 - media.viewInsets.bottom).clamp(
      140.0,
      360.0,
    );
    final fieldHeight = _formatHeight.clamp(140.0, maxField);
    final canSend = widget.controller.text.trim().isNotEmpty;

    return _composerSurface(
      dark: dark,
      radius: 28,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _DragHandle(
                  onDrag: (dy) => setState(() {
                    // Drag up (dy<0) grows the field; clamp to the viewport cap.
                    _formatHeight = (fieldHeight - dy).clamp(140.0, maxField);
                  }),
                ),
              ),
              _EditPreviewSwitch(
                preview: _preview,
                onChanged: (v) {
                  setState(() => _preview = v);
                  if (!v) widget.focusNode.requestFocus();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: fieldHeight,
            child: _preview
                ? _previewBody(context)
                : MentionField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    commentMode: true,
                    expands: true,
                    hintText: context.t('comments.placeholder'),
                  ),
          ),
          const SizedBox(height: 8),
          _FormatToolbar(
            actions: widget.actions,
            canSend: canSend,
            onClose: _closeFormat,
            onSend: () {
              if (!canSend) return;
              widget.onSubmitText();
              _closeFormat();
            },
          ),
        ],
      ),
    );
  }

  /// Live Markdown preview of the current draft (mentions / smart-links / images
  /// render as they will in the posted comment).
  Widget _previewBody(BuildContext context) {
    final text = widget.controller.text.trim();
    if (text.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            context.t('issues.previewEmpty'),
            style: TextStyle(fontSize: 14, color: AppColors.inkFaint),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: KbMarkdownParser(fontSize: 14).parse(text).nodes,
      ),
    );
  }
}

// ── circle buttons ─────────────────────────────────────────────────────────
/// A round composer button. The honey-amber [send] state is intentionally solid
/// accent; every other state is real Liquid Glass ([GlassButton]) so it refracts
/// like the rest of the app's chrome.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    this.onTap,
    this.send = false,
    this.danger = false,
    this.size = 52,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool send;
  final bool danger;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;

    // Solid accent send button.
    if (send) {
      final decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE7B24A), AppColors.accent, AppColors.accentStrong],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.5),
            blurRadius: 16,
            spreadRadius: -5,
            offset: const Offset(0, 6),
          ),
        ],
      );
      return Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: decoration,
            child: Icon(icon, size: 22, color: _onAccent),
          ),
        ),
      );
    }

    // Real Liquid Glass for the idle "+", mic, trash and format-close buttons —
    // pinned to the standard (lightweight) shader so it renders correctly over
    // the scrolling feed and on rotation, unlike the default premium pipeline.
    //
    // Shape: a superellipse with radius = size/2 (a perfect circle), NOT the
    // default LiquidOval. An oval glass surface is clipped with ClipPath, which
    // the engine can't forward to the descendant BackdropFilter layer — so the
    // backdrop blur stays a rectangle behind the circle and its vertical edges
    // leak as faint seams beside the button (worst over the bright desktop/web
    // footer). ClipRRect (used for the superellipse) forwards the clip, killing
    // the halo. See lightweight_liquid_glass.dart's LiquidOval note.
    return GlassButton(
      icon: Icon(icon, size: 22),
      iconColor: danger ? AppColors.danger : AppColors.ink,
      onTap: onTap ?? () {},
      enabled: onTap != null,
      width: size,
      height: size,
      iconSize: 22,
      shape: LiquidRoundedSuperellipse(borderRadius: size / 2),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: _composerGlass(dark),
      glowColor: AppColors.accent,
      stretch: 0.15,
    );
  }
}

/// Inline-edit banner shown above the composer while editing an existing
/// comment, with a quick way to abandon the edit.
class _EditingBanner extends StatelessWidget {
  const _EditingBanner({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Row(
        children: [
          Icon(LucideIcons.pencil, size: 14, color: AppColors.accentStrong),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.t('comments.editingComment'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          InkWell(
            onTap: onCancel,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                context.t('common.cancel'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// WhatsApp-style "replying to …" quote bar shown above the composer field: an
/// accent rule, the replied-to author and a one-line preview, plus a dismiss.
class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({
    required this.name,
    required this.preview,
    required this.onCancel,
  });

  final String name;
  final String preview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(9),
          border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            Icon(LucideIcons.reply, size: 14, color: AppColors.accentStrong),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.t('comments.replyingTo', variables: {'name': name}),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentStrong,
                    ),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onCancel,
              visualDensity: VisualDensity.compact,
              icon: Icon(LucideIcons.x, size: 16, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

// ── drag handle (format mode only) ──────────────────────────────────────────
/// Grip shown above the editor while formatting: drag up to grow the text area,
/// down to shrink it.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.onDrag});

  final void Function(double dy) onDrag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.inkFaint.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── "+" action popup ────────────────────────────────────────────────────────
class _ActionPopup extends StatelessWidget {
  const _ActionPopup({required this.onPick, required this.onFormat});

  final void Function(ComposerAttach kind) onPick;
  final VoidCallback onFormat;

  @override
  Widget build(BuildContext context) {
    // No glass here: this content is rendered directly inside the
    // [GlassPopover]'s morphing glass container, which supplies the tint, blur
    // and the metaball shape. Wrapping it in our own [_composerSurface] would
    // double-stack the glass. mainAxisSize.min so the popover can measure the
    // intrinsic height and morph to exactly the right size.
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(
              context,
              LucideIcons.camera,
              context.t('comments.actionCamera'),
              () => onPick(ComposerAttach.camera),
            ),
            _row(
              context,
              LucideIcons.image,
              context.t('comments.actionGallery'),
              () => onPick(ComposerAttach.gallery),
            ),
            _row(
              context,
              LucideIcons.paperclip,
              context.t('comments.actionFile'),
              () => onPick(ComposerAttach.file),
            ),
            _row(
              context,
              LucideIcons.baseline,
              context.t('comments.actionFormat'),
              onFormat,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Icon(icon, size: 22, color: AppColors.inkSoft),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Markdown format toolbar ─────────────────────────────────────────────────
class _FormatToolbar extends StatelessWidget {
  const _FormatToolbar({
    required this.actions,
    required this.canSend,
    required this.onClose,
    required this.onSend,
  });

  final MarkdownEditingActions actions;
  final bool canSend;
  final VoidCallback onClose;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    // Only the tools the Markdown renderer actually supports (no underline).
    final tools = <(IconData, VoidCallback)>[
      (LucideIcons.bold, actions.bold),
      (LucideIcons.italic, actions.italic),
      (LucideIcons.strikethrough, actions.strikethrough),
      (LucideIcons.link, actions.link),
      (LucideIcons.code, actions.inlineCode),
      (LucideIcons.list, actions.bulletList),
      (LucideIcons.listOrdered, actions.numberedList),
    ];
    return Row(
      children: [
        _CircleButton(icon: LucideIcons.x, size: 46, onTap: onClose),
        const SizedBox(width: 5),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (icon, run) in tools)
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    child: InkWell(
                      onTap: run,
                      borderRadius: BorderRadius.circular(11),
                      child: SizedBox(
                        height: 44,
                        child: Icon(icon, size: 19, color: AppColors.inkSoft),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        _CircleButton(
          icon: LucideIcons.send,
          size: 46,
          send: true,
          onTap: canSend ? onSend : null,
        ),
      ],
    );
  }
}

/// Segmented Editor / Preview switcher shown top-right in the format editor.
class _EditPreviewSwitch extends StatelessWidget {
  const _EditPreviewSwitch({required this.preview, required this.onChanged});

  final bool preview;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(
            context,
            context.t('issues.tabEditor'),
            !preview,
            () => onChanged(false),
          ),
          _seg(
            context,
            context.t('issues.tabPreview'),
            preview,
            () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _seg(
    BuildContext context,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? _onAccent : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

// ── recording bar ───────────────────────────────────────────────────────────
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.amplitude,
    required this.buttonSize,
    required this.onCancel,
    required this.onSend,
  });

  final Duration elapsed;
  final Stream<double> amplitude;
  final double buttonSize;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final s = elapsed.inMilliseconds ~/ 1000;
    final tenths = (elapsed.inMilliseconds % 1000) ~/ 100;
    final time = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')},$tenths';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CircleButton(
          icon: LucideIcons.trash2,
          size: buttonSize,
          danger: true,
          onTap: onCancel,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: _composerSurface(
            dark: dark,
            radius: 26,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const _PulsingDot(),
                const SizedBox(width: 12),
                Text(
                  time,
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 14,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _LiveWave(amplitude: amplitude)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 11),
        _CircleButton(
          icon: LucideIcons.send,
          size: buttonSize,
          send: true,
          onTap: onSend,
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25).animate(_c),
      child: Container(
        width: 11,
        height: 11,
        decoration: const BoxDecoration(
          color: Color(0xFFE5675C),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Scrolling live waveform driven by the recorder's amplitude stream (newest
/// bars on the right, WhatsApp-style).
class _LiveWave extends StatefulWidget {
  const _LiveWave({required this.amplitude});

  final Stream<double> amplitude;

  @override
  State<_LiveWave> createState() => _LiveWaveState();
}

class _LiveWaveState extends State<_LiveWave> {
  final List<double> _bars = [];
  StreamSubscription<double>? _sub;

  /// Each bar is 3px wide + 1px margin either side (see [_barSlot]). Capped so a
  /// long recording doesn't grow an unbounded backing list.
  static const double _barSlot = 5;
  static const int _hardCap = 60;

  @override
  void initState() {
    super.initState();
    _sub = widget.amplitude.listen((v) {
      if (!mounted) return;
      setState(() {
        _bars.add(v);
        if (_bars.length > _hardCap) _bars.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fit the bar count to the space the Expanded actually hands us, so the
    // waveform never overruns the pill (the timer/dot leave little room on a
    // narrow phone). Newest bars stay on the right; older ones scroll off.
    return LayoutBuilder(
      builder: (context, constraints) {
        final capacity = constraints.maxWidth.isFinite
            ? (constraints.maxWidth ~/ _barSlot).clamp(0, _hardCap)
            : _hardCap;
        final visible = _bars.length > capacity
            ? _bars.sublist(_bars.length - capacity)
            : _bars;
        return SizedBox(
          height: 30,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final v in visible)
                Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: (4 + v * 24).clamp(4, 28).toDouble(),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
