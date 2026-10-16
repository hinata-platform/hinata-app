import 'package:flutter/material.dart';

import '../theme/tint_palette.dart';

/// The picture on the style tiles of the Customize panel (HIN-150): an app
/// tile with a sun rising over two hills. Hinata is a place in the sun, so
/// the sun carries the colour, and it is a picture of its own, not the logo.
///
/// [tinted] paints it the way iOS paints tinted icons: a dark pane in the
/// tint, the sun in the accent and the hills in the tint's light ink, so the
/// tile shows the colour before it is applied. The standard tile keeps the
/// brand: navy pane, honey sun, warm paper hills.
///
/// Decorative: the tile's name says what it is.
class TintSymbol extends StatelessWidget {
  const TintSymbol({
    super.key,
    required this.palette,
    this.tinted = false,
    this.size = 72,
  });

  final TintPalette palette;
  final bool tinted;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: TintSymbolPainter(palette: palette, tinted: tinted),
    ),
  );
}

class TintSymbolPainter extends CustomPainter {
  const TintSymbolPainter({required this.palette, required this.tinted});

  final TintPalette palette;
  final bool tinted;

  static const _paperTop = Color(0xFFFFFAEE);
  static const _paperBottom = Color(0xFFEBDDBF);
  static const _paperBack = Color(0xFFD9C79F);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final tile = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(tile, Radius.circular(s * 0.235));

    // A soft drop under the tile, as the icons sit on the glass.
    canvas.drawRRect(
      shape.shift(Offset(0, s * 0.03)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.05),
    );

    canvas.save();
    canvas.clipRRect(shape);

    // The pane.
    final pane = Color.lerp(palette.rail, Colors.black, tinted ? 0.35 : 0)!;
    canvas.drawRect(
      tile,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(pane, Colors.white, 0.12)!, pane],
        ).createShader(tile),
    );

    // The sun, with a halo, half behind the hills.
    final sunCenter = Offset(s * 0.6, s * 0.5);
    final sunRadius = s * 0.215;
    final sun = palette.accent;
    canvas.drawCircle(
      sunCenter,
      sunRadius * 1.75,
      Paint()
        ..shader =
            RadialGradient(
              colors: [sun.withValues(alpha: 0.45), sun.withValues(alpha: 0)],
            ).createShader(
              Rect.fromCircle(center: sunCenter, radius: sunRadius * 1.75),
            ),
    );
    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(sun, Colors.white, 0.45)!, sun],
        ).createShader(Rect.fromCircle(center: sunCenter, radius: sunRadius)),
    );

    // Two hills: a far one in shade, a near one in light.
    final ink = palette.railInk;
    final back = Path()
      ..moveTo(0, s * 0.66)
      ..quadraticBezierTo(s * 0.3, s * 0.5, s * 0.62, s * 0.66)
      ..quadraticBezierTo(s * 0.82, s * 0.74, s, s * 0.64)
      ..lineTo(s, s)
      ..lineTo(0, s)
      ..close();
    canvas.drawPath(
      back,
      Paint()..color = tinted ? ink.withValues(alpha: 0.42) : _paperBack,
    );
    final front = Path()
      ..moveTo(0, s * 0.8)
      ..quadraticBezierTo(s * 0.45, s * 0.6, s, s * 0.78)
      ..lineTo(s, s)
      ..lineTo(0, s)
      ..close();
    final frontRect = Rect.fromLTWH(0, s * 0.6, s, s * 0.4);
    canvas.drawPath(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: tinted
              ? [ink, ink.withValues(alpha: 0.78)]
              : const [_paperTop, _paperBottom],
        ).createShader(frontRect),
    );

    // Light on the glass: a sheen across the top half and a rim.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s, s * 0.55),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, s, s * 0.55)),
    );
    canvas.restore();
    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(TintSymbolPainter old) =>
      old.palette != palette || old.tinted != tinted;
}
