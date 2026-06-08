import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Phase 9.5 — liquify / reshape via forward-warp brush strokes.
///
/// Each [WarpStroke] is a localized displacement: within [radius] of the centre
/// the image is pushed by ([dx],[dy]) (push mode), or pulled toward/away from
/// the centre (pinch/bloat). We build a displacement field from the strokes,
/// then resample the source with bilinear interpolation. Pure + isolate-safe.
enum WarpMode { push, bloat, pinch }

/// Normalized (0..1) warp action. For push, [dx]/[dy] are the normalized
/// drag vector; for bloat/pinch they're unused (strength drives it).
class WarpStroke {
  final double x, y, radius, dx, dy, strength;
  final WarpMode mode;
  const WarpStroke({
    required this.x,
    required this.y,
    required this.radius,
    this.dx = 0,
    this.dy = 0,
    this.strength = 0.5,
    this.mode = WarpMode.push,
  });
}

class LiquifyOps {
  /// Apply [strokes] to [src], returning a warped copy.
  static img.Image warp(img.Image src, List<WarpStroke> strokes) {
    if (strokes.isEmpty) return src;
    final w = src.width, h = src.height;
    // Displacement field in pixels: where each output pixel samples FROM.
    final fieldX = Float32List(w * h);
    final fieldY = Float32List(w * h);

    for (final s in strokes) {
      final cx = s.x * w, cy = s.y * h;
      final r = s.radius * math.max(w, h);
      if (r <= 0) continue;
      final r2 = r * r;
      final pushX = s.dx * w, pushY = s.dy * h;
      final minX = math.max(0, (cx - r).floor());
      final maxX = math.min(w - 1, (cx + r).ceil());
      final minY = math.max(0, (cy - r).floor());
      final maxY = math.min(h - 1, (cy + r).ceil());
      for (int y = minY; y <= maxY; y++) {
        for (int x = minX; x <= maxX; x++) {
          final ddx = x - cx, ddy = y - cy;
          final d2 = ddx * ddx + ddy * ddy;
          if (d2 > r2) continue;
          // Smooth falloff 1 at centre -> 0 at edge.
          final f = (1.0 - math.sqrt(d2) / r);
          final fall = f * f;
          final i = y * w + x;
          switch (s.mode) {
            case WarpMode.push:
              fieldX[i] -= pushX * fall;
              fieldY[i] -= pushY * fall;
              break;
            case WarpMode.bloat:
              // sample from closer to centre -> expands outward
              fieldX[i] -= ddx * fall * s.strength;
              fieldY[i] -= ddy * fall * s.strength;
              break;
            case WarpMode.pinch:
              fieldX[i] += ddx * fall * s.strength;
              fieldY[i] += ddy * fall * s.strength;
              break;
          }
        }
      }
    }

    final out = img.Image(width: w, height: h, numChannels: src.numChannels);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = y * w + x;
        final sx = (x + fieldX[i]).clamp(0.0, w - 1.0);
        final sy = (y + fieldY[i]).clamp(0.0, h - 1.0);
        _bilinear(src, out, sx, sy, x, y);
      }
    }
    return out;
  }

  static void _bilinear(
      img.Image src, img.Image out, double sx, double sy, int dx, int dy) {
    final x0 = sx.floor(), y0 = sy.floor();
    final x1 = math.min(x0 + 1, src.width - 1);
    final y1 = math.min(y0 + 1, src.height - 1);
    final fx = sx - x0, fy = sy - y0;
    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);
    double lerp(num a, num b, double t) => a + (b - a) * t;
    double ch(num a, num b, num c, num d) =>
        lerp(lerp(a, b, fx), lerp(c, d, fx), fy);
    out.setPixelRgb(
      dx,
      dy,
      ch(p00.r, p10.r, p01.r, p11.r).round().clamp(0, 255),
      ch(p00.g, p10.g, p01.g, p11.g).round().clamp(0, 255),
      ch(p00.b, p10.b, p01.b, p11.b).round().clamp(0, 255),
    );
  }
}

class LiquifyJob {
  final Uint8List bytes;
  final List<WarpStroke> strokes;
  final bool asPng;
  final int jpegQuality;
  const LiquifyJob({
    required this.bytes,
    required this.strokes,
    this.asPng = false,
    this.jpegQuality = 95,
  });
}

Future<Uint8List> applyLiquify(LiquifyJob job) => compute(_liquifyEntry, job);

Future<Uint8List> _liquifyEntry(LiquifyJob job) async {
  var im = img.decodeImage(job.bytes);
  if (im == null) throw Exception('Could not decode image for liquify');
  if (im.numChannels < 3 || im.hasPalette) im = im.convert(numChannels: 3);
  final out = LiquifyOps.warp(im, job.strokes);
  return job.asPng
      ? img.encodePng(out)
      : img.encodeJpg(out, quality: job.jpegQuality);
}
