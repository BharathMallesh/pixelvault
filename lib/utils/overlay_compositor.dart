import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/text_overlay.dart';
import '../models/sticker_overlay.dart';
import '../models/draw_stroke.dart';

/// Renders text / drawing / sticker overlays onto a photo at the photo's FULL
/// resolution, using a dart:ui Canvas (GPU-backed, fast). This replaces the old
/// approach of screenshotting the on-screen preview, which capped exports at
/// screen resolution.
///
/// Overlay positions are normalized (0..1), so they map directly to the output.
/// Overlay *sizes* (font size, brush width, sticker size) are in the editor's
/// screen pixels, so they're scaled by (outputWidth / canvasWidth).
class OverlayCompositor {
  /// [photoBytes] is the already-processed full-resolution image (JPEG/PNG).
  /// [canvasSize] is the on-screen preview area the overlays were laid out in.
  /// Returns PNG bytes of the photo with overlays burned in.
  static Future<Uint8List> compose({
    required Uint8List photoBytes,
    required Size canvasSize,
    required List<DrawStroke> strokes,
    required List<TextOverlay> texts,
    required List<StickerOverlay> stickers,
  }) async {
    // Decode the processed photo to a ui.Image to get its real dimensions.
    final codec = await ui.instantiateImageCodec(photoBytes);
    final frame = await codec.getNextFrame();
    final photo = frame.image;
    final outW = photo.width.toDouble();
    final outH = photo.height.toDouble();

    // Scale factor from on-screen sizes to output pixels. The preview uses
    // BoxFit.contain, so the photo fills one axis; scale by width fraction.
    final scale = canvasSize.width > 0 ? outW / canvasSize.width : 1.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, outW, outH));

    // 1. The photo itself.
    canvas.drawImage(photo, Offset.zero, Paint());

    // Drawing strokes need their own layer so eraser (BlendMode.clear) only
    // affects the strokes, not the photo beneath.
    if (strokes.isNotEmpty) {
      canvas.saveLayer(Rect.fromLTWH(0, 0, outW, outH), Paint());
      for (final s in strokes) {
        _paintStroke(canvas, s, outW, outH, scale);
      }
      canvas.restore();
    }

    // 2. Stickers.
    for (final s in stickers) {
      _paintSticker(canvas, s, outW, outH, scale);
    }

    // 3. Text overlays.
    for (final t in texts) {
      _paintText(canvas, t, outW, outH, scale);
    }

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(outW.round(), outH.round());
    final bd = await outImage.toByteData(format: ui.ImageByteFormat.png);
    photo.dispose();
    outImage.dispose();
    return bd!.buffer.asUint8List();
  }

  static void _paintStroke(
      Canvas canvas, DrawStroke stroke, double w, double h, double scale) {
    if (stroke.points.length < 2) return;
    final paint = Paint()
      ..color = stroke.isEraser ? Colors.transparent : stroke.color
      ..strokeWidth = stroke.width * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;

    final path = Path()
      ..moveTo(stroke.points[0].x * w, stroke.points[0].y * h);
    for (int i = 1; i < stroke.points.length - 1; i++) {
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];
      path.quadraticBezierTo(
        p1.x * w, p1.y * h,
        (p1.x + p2.x) / 2 * w, (p1.y + p2.y) / 2 * h,
      );
    }
    canvas.drawPath(path, paint);
  }

  static void _paintSticker(
      Canvas canvas, StickerOverlay s, double w, double h, double scale) {
    final fontSize = s.size * 0.8 * scale;
    final tp = TextPainter(
      text: TextSpan(text: s.emoji, style: TextStyle(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = Offset(s.x * w, s.y * h);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (s.rotation != 0) canvas.rotate(s.rotation);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  static void _paintText(
      Canvas canvas, TextOverlay t, double w, double h, double scale) {
    final isBold = t.style == TextStyle2.bold || t.style == TextStyle2.boldItalic;
    final isItalic = t.style == TextStyle2.italic || t.style == TextStyle2.boldItalic;
    final tp = TextPainter(
      text: TextSpan(
        text: t.text,
        style: TextStyle(
          color: t.color,
          fontSize: t.fontSize * scale,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textAlign: t.alignment == TextAlignment2.left
          ? TextAlign.left
          : t.alignment == TextAlignment2.right
              ? TextAlign.right
              : TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);

    final center = Offset(t.x * w, t.y * h);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (t.rotation != 0) canvas.rotate(t.rotation);
    final topLeft = Offset(-tp.width / 2, -tp.height / 2);
    if (t.hasBackground) {
      final pad = 8.0 * scale;
      canvas.drawRect(
        Rect.fromLTWH(topLeft.dx - pad, topLeft.dy - pad,
            tp.width + pad * 2, tp.height + pad * 2),
        Paint()..color = t.backgroundColor,
      );
    }
    tp.paint(canvas, topLeft);
    canvas.restore();
  }
}
