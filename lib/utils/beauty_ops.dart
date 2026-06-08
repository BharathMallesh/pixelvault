import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'face_detector.dart';

/// Phase 9.2 / 9.4 — portrait beauty operations applied within a detected
/// [Face] region. Pure pixel math, headless-testable. Heavy variants run on a
/// background isolate.
///
/// - skinSmooth: edge-preserving (selective) blur restricted to skin pixels.
/// - teethWhiten: brighten + desaturate the mouth band.
/// - eyeBrighten: lift the eye band slightly.
class BeautyOps {
  /// Edge-preserving smooth: blend each skin pixel toward a local box-blur,
  /// but only where the neighbourhood is low-contrast (skin), preserving edges
  /// like eyes/lips. [amount] 0..1, [face] gives the region + skin mask.
  static img.Image skinSmooth(img.Image src, Face face, double amount,
      {int radius = 3}) {
    if (amount <= 0) return src;
    final w = src.width, h = src.height;
    final dst = img.Image.from(src);

    // Region of interest = face bounding box (in src px).
    final x0 = (face.left * w).floor().clamp(0, w - 1);
    final x1 = (face.right * w).ceil().clamp(0, w - 1);
    final y0 = (face.top * h).floor().clamp(0, h - 1);
    final y1 = (face.bottom * h).ceil().clamp(0, h - 1);

    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        final p = src.getPixel(x, y);
        if (!_skinAt(face, src, x, y)) continue;
        // Local mean + variance over the box.
        double sr = 0, sg = 0, sb = 0, sv = 0;
        int cnt = 0;
        for (int dy = -radius; dy <= radius; dy++) {
          final yy = (y + dy).clamp(0, h - 1);
          for (int dx = -radius; dx <= radius; dx++) {
            final xx = (x + dx).clamp(0, w - 1);
            final q = src.getPixel(xx, yy);
            sr += q.r;
            sg += q.g;
            sb += q.b;
            final lum = 0.299 * q.r + 0.587 * q.g + 0.114 * q.b;
            sv += lum;
            cnt++;
          }
        }
        final mr = sr / cnt, mg = sg / cnt, mb = sb / cnt;
        final meanLum = sv / cnt;
        final pl = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        // Edge factor: if this pixel deviates a lot from the local mean, it's
        // an edge — smooth less. 0 (edge) .. 1 (flat skin).
        final dev = (pl - meanLum).abs();
        final edge = (1.0 - (dev / 40.0)).clamp(0.0, 1.0);
        final t = amount * edge;
        dst.setPixelRgb(
          x,
          y,
          (p.r + (mr - p.r) * t).round().clamp(0, 255),
          (p.g + (mg - p.g) * t).round().clamp(0, 255),
          (p.b + (mb - p.b) * t).round().clamp(0, 255),
        );
      }
    }
    return dst;
  }

  /// Brighten + desaturate teeth in the mouth band. [amount] 0..1.
  static img.Image teethWhiten(img.Image src, Face face, double amount) {
    if (amount <= 0) return src;
    final w = src.width, h = src.height;
    final dst = img.Image.from(src);
    final m = face.mouthBand;
    final x0 = (m.l * w).floor().clamp(0, w - 1);
    final x1 = (m.r * w).ceil().clamp(0, w - 1);
    final y0 = (m.t * h).floor().clamp(0, h - 1);
    final y1 = (m.b * h).ceil().clamp(0, h - 1);
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        final p = src.getPixel(x, y);
        final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
        // Teeth ~ bright and not strongly red/coloured.
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        final maxc = math.max(r, math.max(g, b));
        final minc = math.min(r, math.min(g, b));
        final sat = maxc <= 0 ? 0 : (maxc - minc) / maxc;
        if (lum < 90 || sat > 0.55) continue; // skip lips/dark
        final gray = lum;
        // Desaturate toward gray + brighten.
        dst.setPixelRgb(
          x,
          y,
          (r + (gray - r) * amount * 0.6 + 18 * amount).round().clamp(0, 255),
          (g + (gray - g) * amount * 0.6 + 18 * amount).round().clamp(0, 255),
          (b + (gray - b) * amount * 0.6 + 22 * amount).round().clamp(0, 255),
        );
      }
    }
    return dst;
  }

  /// Brighten the eye band (whites of eyes + general lift). [amount] 0..1.
  static img.Image eyeBrighten(img.Image src, Face face, double amount) {
    if (amount <= 0) return src;
    final w = src.width, h = src.height;
    final dst = img.Image.from(src);
    final e = face.eyeBand;
    final x0 = (e.l * w).floor().clamp(0, w - 1);
    final x1 = (e.r * w).ceil().clamp(0, w - 1);
    final y0 = (e.t * h).floor().clamp(0, h - 1);
    final y1 = (e.b * h).ceil().clamp(0, h - 1);
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        final p = src.getPixel(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        // Lift brighter (sclera/highlight) pixels more than dark (iris/lash).
        final wgt = (lum / 255.0);
        final lift = 1.0 + amount * 0.35 * wgt;
        dst.setPixelRgb(
          x,
          y,
          (p.r * lift).round().clamp(0, 255),
          (p.g * lift).round().clamp(0, 255),
          (p.b * lift).round().clamp(0, 255),
        );
      }
    }
    return dst;
  }

  static bool _skinAt(Face face, img.Image src, int x, int y) {
    final mask = face.skinAlpha;
    if (mask != null && face.maskW > 0 && face.maskH > 0) {
      // Map src coords into mask coords.
      final mx = (x * face.maskW / src.width).floor().clamp(0, face.maskW - 1);
      final my = (y * face.maskH / src.height).floor().clamp(0, face.maskH - 1);
      return mask[my * face.maskW + mx] > 127;
    }
    return true; // no mask -> treat whole ROI as skin
  }

  /// Apply all enabled beauty ops in order. Returns the modified image.
  static img.Image applyAll(
    img.Image src,
    Face face, {
    double smooth = 0,
    double teeth = 0,
    double eyes = 0,
  }) {
    var out = src;
    if (smooth > 0) out = skinSmooth(out, face, smooth);
    if (teeth > 0) out = teethWhiten(out, face, teeth);
    if (eyes > 0) out = eyeBrighten(out, face, eyes);
    return out;
  }
}

// ── Isolate-backed full apply (decode + detect-supplied face + encode) ──────

class BeautyJob {
  final Uint8List bytes;
  final Face face;
  final double smooth, teeth, eyes;
  final bool asPng;
  final int jpegQuality;
  const BeautyJob({
    required this.bytes,
    required this.face,
    this.smooth = 0,
    this.teeth = 0,
    this.eyes = 0,
    this.asPng = false,
    this.jpegQuality = 95,
  });
}

Future<Uint8List> applyBeauty(BeautyJob job) => compute(_beautyEntry, job);

Future<Uint8List> _beautyEntry(BeautyJob job) async {
  var im = img.decodeImage(job.bytes);
  if (im == null) throw Exception('Could not decode image for beauty');
  if (im.numChannels < 3 || im.hasPalette) im = im.convert(numChannels: 3);
  final out = BeautyOps.applyAll(im, job.face,
      smooth: job.smooth, teeth: job.teeth, eyes: job.eyes);
  return job.asPng
      ? img.encodePng(out)
      : img.encodeJpg(out, quality: job.jpegQuality);
}
