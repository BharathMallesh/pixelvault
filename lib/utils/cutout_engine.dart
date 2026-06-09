import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'ai_service.dart';
import 'tflite_segmenter.dart';

/// On-device subject/background segmentation. Produces a soft alpha matte with
/// no network call. Uses a real TFLite model when one is bundled
/// (assets/models/cutout.tflite), and otherwise falls back to the classical,
/// model-free algorithm below — so it always works offline.
///
/// HOW IT WORKS (classical, model-free):
///   1. Downscale for speed.
///   2. Build a "probably subject" seed region from the hint rect (or a
///      centered ellipse) and a "probably background" seed from the border.
///   3. Learn rough foreground/background colour statistics from the seeds and
///      score every pixel by which model it matches better, biased by distance
///      to the subject centre.
///   4. Threshold, keep the largest connected blob, fill holes, then feather
///      the edge so the matte is soft rather than jagged.
///   5. Upscale the matte back to full resolution.
///
/// This is intentionally a classical algorithm: it works offline today with no
/// model download. [_seamForTfliteModel] marks exactly where a TFLite
/// segmentation model (U^2-Net / MODNet) would replace steps 2-4 for
/// dramatically better edges — the engine's public contract stays identical.
class CutoutEngine {
  /// Max working dimension during segmentation (matte is upscaled afterward).
  static const int _work = 384;

  static Future<CutoutResult> segment(
    Uint8List imageBytes, {
    List<double>? hintRect,
  }) async {
    // 1. Try real on-device ML first. TFLite needs platform channels, so it
    //    must run on the main isolate (not inside compute()). If no model is
    //    bundled or inference fails, this returns null and we fall back.
    final ml = await _tryMlSegment(imageBytes);
    if (ml != null) return ml;

    // 2. Classical fallback on a background isolate (model-free, always works).
    return compute(
      _segmentEntry,
      _SegmentJob(bytes: imageBytes, hintRect: hintRect),
    );
  }

  /// Whether genuine ML segmentation is active (a model is bundled & loaded).
  static Future<bool> get mlAvailable => TfliteSegmenter.ensureLoaded();

  static Future<CutoutResult?> _tryMlSegment(Uint8List bytes) async {
    try {
      var image = img.decodeImage(bytes);
      if (image == null) return null;
      if (image.numChannels < 3 || image.hasPalette) {
        image = image.convert(numChannels: 3);
      }
      final alpha = await TfliteSegmenter.segment(image);
      if (alpha == null) return null; // no model -> caller falls back
      return CutoutResult(
          alpha: alpha, width: image.width, height: image.height);
    } catch (_) {
      return null;
    }
  }

  // ── Classical seam (model-free fallback) ────────────────────────────
  static Uint8List _seamForTfliteModel(img.Image small, _Seeds seeds) =>
      _classicalMatte(small, seeds);

  /// Apply a [matte] (alpha, 0..255) to [imageBytes], producing a PNG with a
  /// transparent background (subject kept). Runs off the UI thread.
  static Future<Uint8List> applyTransparent(
    Uint8List imageBytes,
    CutoutResult matte,
  ) {
    return compute(
      _applyEntry,
      _ApplyJob(bytes: imageBytes, matte: matte, mode: _ApplyMode.transparent),
    );
  }

  /// Apply a [matte] to [imageBytes], keeping the subject sharp and blurring
  /// the background by [blurRadius] px (working scale). Encodes JPEG/PNG.
  static Future<Uint8List> applyBackgroundBlur(
    Uint8List imageBytes,
    CutoutResult matte, {
    int blurRadius = 12,
    bool asPng = false,
  }) {
    return compute(
      _applyEntry,
      _ApplyJob(
        bytes: imageBytes,
        matte: matte,
        mode: _ApplyMode.blur,
        blurRadius: blurRadius,
        asPng: asPng,
      ),
    );
  }
}

enum _ApplyMode { transparent, blur }

class _ApplyJob {
  final Uint8List bytes;
  final CutoutResult matte;
  final _ApplyMode mode;
  final int blurRadius;
  final bool asPng;
  const _ApplyJob({
    required this.bytes,
    required this.matte,
    required this.mode,
    this.blurRadius = 12,
    this.asPng = false,
  });
}

Future<Uint8List> _applyEntry(_ApplyJob job) async {
  var im = img.decodeImage(job.bytes);
  if (im == null) throw Exception('Could not decode image for cutout apply');
  if (im.numChannels < 3 || im.hasPalette) im = im.convert(numChannels: 3);
  final m = job.matte;
  // Matte should already match full resolution; guard anyway.
  if (m.width != im.width || m.height != im.height) {
    im = img.copyResize(im, width: m.width, height: m.height);
  }
  final w = im.width, h = im.height;

  switch (job.mode) {
    case _ApplyMode.transparent:
      final out = img.Image(width: w, height: h, numChannels: 4);
      for (int y = 0, i = 0; y < h; y++) {
        for (int x = 0; x < w; x++, i++) {
          final px = im.getPixel(x, y);
          out.setPixelRgba(x, y, px.r, px.g, px.b, m.alpha[i]);
        }
      }
      return img.encodePng(out);

    case _ApplyMode.blur:
      final blurred = img.gaussianBlur(im.clone(), radius: job.blurRadius);
      final out = img.Image(width: w, height: h, numChannels: 3);
      for (int y = 0, i = 0; y < h; y++) {
        for (int x = 0; x < w; x++, i++) {
          final a = m.alpha[i] / 255.0;
          final sp = im.getPixel(x, y);
          final bp = blurred.getPixel(x, y);
          out.setPixelRgb(
            x,
            y,
            (sp.r * a + bp.r * (1 - a)).round(),
            (sp.g * a + bp.g * (1 - a)).round(),
            (sp.b * a + bp.b * (1 - a)).round(),
          );
        }
      }
      return job.asPng
          ? img.encodePng(out)
          : img.encodeJpg(out, quality: 95);
  }
}

class _SegmentJob {
  final Uint8List bytes;
  final List<double>? hintRect;
  const _SegmentJob({required this.bytes, this.hintRect});
}

Future<CutoutResult> _segmentEntry(_SegmentJob job) async {
  var image = img.decodeImage(job.bytes);
  if (image == null) throw Exception('Could not decode image for cutout');
  if (image.numChannels < 3 || image.hasPalette) {
    image = image.convert(numChannels: 3);
  }
  final fullW = image.width, fullH = image.height;

  // Downscale to working resolution (longest side -> _work).
  final scale = CutoutEngine._work / math.max(fullW, fullH);
  final sw = math.max(1, (fullW * scale).round());
  final sh = math.max(1, (fullH * scale).round());
  final small = img.copyResize(image, width: sw, height: sh);

  final seeds = _Seeds.fromHint(sw, sh, job.hintRect);
  final smallMatte = CutoutEngine._seamForTfliteModel(small, seeds); // sw*sh

  // Upscale matte to full resolution with bilinear interpolation.
  final full = _upscaleMatte(smallMatte, sw, sh, fullW, fullH);
  return CutoutResult(alpha: full, width: fullW, height: fullH);
}

/// Seed regions + subject centre derived from a hint rect (normalized) or a
/// centered default.
class _Seeds {
  final int cx, cy; // subject centre (working px)
  final double rx, ry; // subject ellipse radii (working px)
  _Seeds(this.cx, this.cy, this.rx, this.ry);

  factory _Seeds.fromHint(int w, int h, List<double>? hint) {
    if (hint != null && hint.length == 4) {
      final l = hint[0] * w, t = hint[1] * h, r = hint[2] * w, b = hint[3] * h;
      final cx = ((l + r) / 2).round();
      final cy = ((t + b) / 2).round();
      return _Seeds(cx, cy, (r - l).abs() / 2, (b - t).abs() / 2);
    }
    // Default: centered subject occupying ~62% of frame.
    return _Seeds(w ~/ 2, h ~/ 2, w * 0.31, h * 0.42);
  }
}

/// Classical foreground/background matte. Returns one alpha byte per pixel.
Uint8List _classicalMatte(img.Image im, _Seeds s) {
  final w = im.width, h = im.height;
  final n = w * h;

  // Cache RGB.
  final r = Uint8List(n), g = Uint8List(n), b = Uint8List(n);
  for (int y = 0, i = 0; y < h; y++) {
    for (int x = 0; x < w; x++, i++) {
      final px = im.getPixel(x, y);
      r[i] = px.r.toInt();
      g[i] = px.g.toInt();
      b[i] = px.b.toInt();
    }
  }

  // 1) Learn FG colour model from the inner ellipse, BG from the border ring.
  final fg = _ColorStats();
  final bg = _ColorStats();
  const border = 0.06; // fraction of frame treated as definite background
  final bx = (w * border).ceil(), by = (h * border).ceil();
  for (int y = 0, i = 0; y < h; y++) {
    for (int x = 0; x < w; x++, i++) {
      final inBorder = x < bx || y < by || x >= w - bx || y >= h - by;
      if (inBorder) {
        bg.add(r[i], g[i], b[i]);
        continue;
      }
      final dx = (x - s.cx) / (s.rx * 0.6);
      final dy = (y - s.cy) / (s.ry * 0.6);
      if (dx * dx + dy * dy <= 1.0) fg.add(r[i], g[i], b[i]);
    }
  }
  fg.finalize();
  bg.finalize();

  // 2) Score each pixel: prefer the closer colour model, biased toward the
  //    subject centre so background-coloured pixels far out stay background.
  final score = Float32List(n); // >0 => foreground
  for (int y = 0, i = 0; y < h; y++) {
    for (int x = 0; x < w; x++, i++) {
      final df = fg.dist2(r[i], g[i], b[i]);
      final db = bg.dist2(r[i], g[i], b[i]);
      final colorBias = (db - df); // positive => looks more like FG
      final dx = (x - s.cx) / s.rx;
      final dy = (y - s.cy) / s.ry;
      final dist = math.sqrt(dx * dx + dy * dy); // 1.0 at ellipse edge
      final spatial = (1.0 - dist) * 1800.0; // strong centre prior
      score[i] = colorBias + spatial;
    }
  }

  // 3) Hard threshold -> binary mask.
  final mask = Uint8List(n);
  for (int i = 0; i < n; i++) mask[i] = score[i] > 0 ? 1 : 0;

  // 4) Keep the largest connected component (drops stray background blobs).
  _keepLargestComponent(mask, w, h);
  // 5) Fill interior holes so textured subjects stay solid.
  _fillHoles(mask, w, h);

  // 6) Feather the edge: alpha = blurred binary mask.
  final alpha = Uint8List(n);
  for (int i = 0; i < n; i++) alpha[i] = mask[i] == 1 ? 255 : 0;
  return _featherBlur(alpha, w, h, radius: math.max(1, (w / 120).round()));
}

/// Running mean colour + spread, used as a crude single-Gaussian model.
class _ColorStats {
  double sr = 0, sg = 0, sb = 0;
  int count = 0;
  double mr = 0, mg = 0, mb = 0;
  void add(int r, int g, int b) {
    sr += r;
    sg += g;
    sb += b;
    count++;
  }

  void finalize() {
    if (count == 0) count = 1;
    mr = sr / count;
    mg = sg / count;
    mb = sb / count;
  }

  double dist2(int r, int g, int b) {
    final dr = r - mr, dg = g - mg, db = b - mb;
    return dr * dr + dg * dg + db * db;
  }
}

/// In-place: keep only the largest 4-connected component of value 1.
void _keepLargestComponent(Uint8List mask, int w, int h) {
  final n = w * h;
  final label = Int32List(n);
  final stack = <int>[];
  int best = -1, bestSize = 0, cur = 0;
  for (int start = 0; start < n; start++) {
    if (mask[start] != 1 || label[start] != 0) continue;
    cur++;
    int size = 0;
    stack
      ..clear()
      ..add(start);
    label[start] = cur;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      size++;
      final x = p % w, y = p ~/ w;
      if (x > 0 && mask[p - 1] == 1 && label[p - 1] == 0) {
        label[p - 1] = cur;
        stack.add(p - 1);
      }
      if (x < w - 1 && mask[p + 1] == 1 && label[p + 1] == 0) {
        label[p + 1] = cur;
        stack.add(p + 1);
      }
      if (y > 0 && mask[p - w] == 1 && label[p - w] == 0) {
        label[p - w] = cur;
        stack.add(p - w);
      }
      if (y < h - 1 && mask[p + w] == 1 && label[p + w] == 0) {
        label[p + w] = cur;
        stack.add(p + w);
      }
    }
    if (size > bestSize) {
      bestSize = size;
      best = cur;
    }
  }
  if (best < 0) return;
  for (int i = 0; i < n; i++) mask[i] = label[i] == best ? 1 : 0;
}

/// In-place: flood background from the border; anything value-0 not reached is
/// an interior hole -> set to 1.
void _fillHoles(Uint8List mask, int w, int h) {
  final n = w * h;
  final reached = Uint8List(n);
  final stack = <int>[];
  void seed(int p) {
    if (mask[p] == 0 && reached[p] == 0) {
      reached[p] = 1;
      stack.add(p);
    }
  }

  for (int x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (int y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % w, y = p ~/ w;
    if (x > 0) seed(p - 1);
    if (x < w - 1) seed(p + 1);
    if (y > 0) seed(p - w);
    if (y < h - 1) seed(p + w);
  }
  for (int i = 0; i < n; i++) {
    if (mask[i] == 0 && reached[i] == 0) mask[i] = 1; // interior hole
  }
}

/// Separable box blur on an 8-bit alpha plane, [radius] px, two passes for a
/// smoother (near-Gaussian) falloff. Returns a new buffer.
Uint8List _featherBlur(Uint8List a, int w, int h, {required int radius}) {
  Uint8List src = a;
  for (int pass = 0; pass < 2; pass++) {
    final tmp = Uint8List(w * h);
    // Horizontal.
    for (int y = 0; y < h; y++) {
      int sum = 0;
      final row = y * w;
      for (int x = -radius; x <= radius; x++) {
        sum += src[row + x.clamp(0, w - 1)];
      }
      final div = radius * 2 + 1;
      for (int x = 0; x < w; x++) {
        tmp[row + x] = (sum / div).round();
        final add = (x + radius + 1).clamp(0, w - 1);
        final rem = (x - radius).clamp(0, w - 1);
        sum += src[row + add] - src[row + rem];
      }
    }
    // Vertical.
    final out = Uint8List(w * h);
    for (int x = 0; x < w; x++) {
      int sum = 0;
      for (int y = -radius; y <= radius; y++) {
        sum += tmp[y.clamp(0, h - 1) * w + x];
      }
      final div = radius * 2 + 1;
      for (int y = 0; y < h; y++) {
        out[y * w + x] = (sum / div).round();
        final add = (y + radius + 1).clamp(0, h - 1);
        final rem = (y - radius).clamp(0, h - 1);
        sum += tmp[add * w + x] - tmp[rem * w + x];
      }
    }
    src = out;
  }
  return src;
}

/// Bilinear upscale of an 8-bit alpha plane from src to dst dimensions.
Uint8List _upscaleMatte(Uint8List a, int sw, int sh, int dw, int dh) {
  if (sw == dw && sh == dh) return a;
  final out = Uint8List(dw * dh);
  final fx = (sw - 1) / math.max(1, dw - 1);
  final fy = (sh - 1) / math.max(1, dh - 1);
  for (int y = 0; y < dh; y++) {
    final syf = y * fy;
    final y0 = syf.floor().clamp(0, sh - 1);
    final y1 = math.min(y0 + 1, sh - 1);
    final wy = syf - y0;
    for (int x = 0; x < dw; x++) {
      final sxf = x * fx;
      final x0 = sxf.floor().clamp(0, sw - 1);
      final x1 = math.min(x0 + 1, sw - 1);
      final wx = sxf - x0;
      final top = a[y0 * sw + x0] * (1 - wx) + a[y0 * sw + x1] * wx;
      final bot = a[y1 * sw + x0] * (1 - wx) + a[y1 * sw + x1] * wx;
      out[y * dw + x] = (top * (1 - wy) + bot * wy).round();
    }
  }
  return out;
}
