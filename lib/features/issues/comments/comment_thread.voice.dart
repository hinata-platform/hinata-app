part of 'comment_thread.dart';

/// Text comment body — rendered through the shared Markdown parser so mentions,
/// smart-links and inline images keep working. Flat, on a transparent
/// background (no bubble); the timestamp lives in the row header.
class _TextBody extends StatelessWidget {
  const _TextBody({required this.comment});

  final IssueComment comment;

  /// Matches any line that opens a block-level markdown construct.
  static final _blockLine = RegExp(
    r'^(#{1,6}\s|```|>\s?|\s*\|.*\||:::|(-{3,}|\*{3,}|_{3,})\s*$|(\s*([-*+]|\d+\.)\s+))',
  );
  static final _image = RegExp(r'!\[[^\]]*\]\([^)]+\)');

  /// True when the body is a single paragraph with no block-level markdown —
  /// rendered as one inline run instead of the heavier block layout.
  bool get _inlineOnly {
    if (_image.hasMatch(comment.text)) return false;
    final lines = comment.text.replaceAll('\r\n', '\n').split('\n');
    var sawText = false;
    var sawBlank = false;
    for (final l in lines) {
      if (l.trim().isEmpty) {
        if (sawText) sawBlank = true;
        continue;
      }
      if (sawBlank) return false; // a second paragraph → treat as block
      if (_blockLine.hasMatch(l)) return false;
      sawText = true;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_inlineOnly) {
      final parser = KbMarkdownParser(fontSize: 14);
      final base = parser.baseStyle.copyWith(height: 1.35);
      final body = comment.text
          .replaceAll('\r\n', '\n')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .join(' ');
      return Text.rich(TextSpan(children: [parser.inlineFor(body, base)]));
    }

    final nodes = KbMarkdownParser(fontSize: 14).parse(comment.text).nodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: nodes,
    );
  }
}

/// A playable voice message: amber play/pause, tappable/scrubbable waveform and
/// a live-updating timecode. Audio is fetched lazily on first play.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.voice, required this.loader});

  final CommentVoice voice;
  final VoiceAudioLoader loader;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  late VoicePlaybackController _controller = VoicePlaybackController(
    loader: widget.loader,
    fallbackDuration: widget.voice.duration,
  );

  @override
  void didUpdateWidget(VoiceBubble old) {
    super.didUpdateWidget(old);
    // If Flutter reuses this State for a different comment (the keyless 'All'
    // feed can reconcile adjacent voice rows by position after a live reorder),
    // rebuild the controller so a fresh, idle player fetches the new clip
    // instead of replaying the previous comment's audio.
    if (old.voice != widget.voice || old.loader != widget.loader) {
      _controller.dispose();
      _controller = VoicePlaybackController(
        loader: widget.loader,
        fallbackDuration: widget.voice.duration,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _mmss(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final playing = _controller.playing;
        final loading = _controller.loading;
        final elapsed = _controller.position.inMilliseconds > 0
            ? _controller.position
            : Duration.zero;
        final total = _controller.duration;
        final timeStyle = TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 10.5,
          color: AppColors.inkFaint,
        );
        return SizedBox(
          width: 230,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Play button and waveform share one centred row, so the play
              // glyph sits exactly on the waveform's centre line (WhatsApp-style
              // — the 40px button and 30px waveform both centre to the row).
              Row(
                children: [
                  _PlayButton(
                    playing: playing,
                    loading: loading,
                    failed: _controller.failed,
                    onTap: _controller.toggle,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: _Waveform(
                        peaks: widget.voice.peaks,
                        progress: _controller.progress,
                        onSeek: _controller.seekFraction,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Timecodes below the waveform, indented past the play button
              // (40px button + 11px gap) so they align under the peaks.
              Padding(
                padding: const EdgeInsets.only(left: 51),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _mmss(
                        playing || elapsed > Duration.zero ? elapsed : total,
                      ),
                      style: timeStyle,
                    ),
                    Text(_mmss(total), style: timeStyle),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.failed,
    required this.onTap,
  });

  final bool playing;
  final bool loading;
  final bool failed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF2A2410),
                  ),
                )
              : Icon(
                  failed
                      ? LucideIcons.rotateCw
                      : (playing ? LucideIcons.pause : LucideIcons.play),
                  size: 18,
                  color: const Color(0xFF2A2410),
                ),
        ),
      ),
    );
  }
}

/// Waveform bars: amber up to [progress], muted after; tap or drag to scrub.
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.peaks,
    required this.progress,
    required this.onSeek,
  });

  final List<int> peaks;
  final double progress;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final idle = dark ? const Color(0x3DFFFFFF) : const Color(0x33000000);
    final bars = peaks.isEmpty ? List<int>.filled(36, 30) : peaks;
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekAt(double dx) =>
            onSeek((dx / constraints.maxWidth).clamp(0.0, 1.0));
        // A CustomPaint keeps the static peaks out of the widget rebuild: the
        // enclosing AnimatedBuilder ticks many times a second during playback,
        // but only `progress` changes, so the painter just repaints the fill
        // instead of reconstructing ~36 Container widgets each frame.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekAt(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
          child: CustomPaint(
            size: Size.infinite,
            painter: _WaveformPainter(
              bars: bars,
              progress: progress,
              fill: AppColors.accent,
              idle: idle,
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.fill,
    required this.idle,
  });

  final List<int> bars;
  final double progress;
  final Color fill;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final n = bars.length;
    final cellW = size.width / n;
    const hPad = 0.8; // matches the former per-bar horizontal padding
    final barW = (cellW - hPad * 2).clamp(0.0, cellW);
    final fillPaint = Paint()..color = fill;
    final idlePaint = Paint()..color = idle;
    for (var i = 0; i < n; i++) {
      final h = (4 + bars[i] / 100 * 26).clamp(4, 30).toDouble();
      final cx = i * cellW + cellW / 2;
      final top = (size.height - h) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barW / 2, top, barW, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, (i + 0.5) / n <= progress ? fillPaint : idlePaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.fill != fill ||
      old.idle != idle ||
      !identical(old.bars, bars);
}

/// Local time as `HH:mm` (24h). Comments store UTC; display in the device zone.
String hhmm(DateTime? dt) {
  if (dt == null) return '';
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
