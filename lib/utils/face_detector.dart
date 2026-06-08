import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Phase 9.1 — face detection abstraction. Produces a [Face] (bounding box +
/// rough feature regions) used by the beauty tools.
///
/// Two implementations share this contract:
///   - [_classicalDetect] (shipped): model-free skin-region detection — finds
///     the dominant skin-coloured blob and estimates feature regions from face
///     geometry. Works offline today, no bundled model, no app-size cost.
///   - A TFLite landmark model (future): drop in at [_seamForTfliteModel] for
///     precise landmarks. Callers and beauty ops are unaffected because they
///     consume the same [Face] contract.

/// Normalized (0..1) face description. Feature rects are best-effort estimates
/// from face geometry when using the classical detector; a landmark model would
/// fill them precisely.
class Face {
  final double left, top, right, bottom; // bounding box, normalized
  final List<double>? skinAlpha; // optional skin mask (w*h, 0..255)
  final int maskW, maskH;

  const Face({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.skinAlpha,
    this.maskW = 0,
    this.maskH = 0,
  });

  bool get isValid => right > left && bottom > top;
  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
  double get w => right - left;
  double get h => bottom - top;

  /// Rough eye band: upper-third horizontal strip across the face.
  ({double l, double t, double r, double b}) get eyeBand => (
        l: left + w * 0.15,
        t: top + h * 0.30,
        r: right - w * 0.15,
        b: top + h * 0.48,
      );

  /// Rough mouth band: lower-third strip (for teeth whitening).
  ({double l, double t, double r, double b}) get mouthBand => (
        l: left + w * 0.28,
        t: top + h * 0.62,
        r: right - w * 0.28,
        b: top + h * 0.82,
      );
}

class FaceDetector {
  const FaceDetector();

  /// Detect the most prominent face in [imageBytes]. Returns null if none
  /// found. Runs on a background isolate.
  Future<Face?> detect(Uint8List imageBytes) =>
      compute(_detectEntry, imageBytes);

  // ── Seam for a future TFLite landmark model ─────────────────────────
  // Replace this with model inference to get precise landmarks; the Face
  // contract (and therefore the beauty ops) stays identical.
  static Face? _seamForTfliteModel(img.Image small) => _classicalDetect(small);
}

const int _work = 256;

Future<Face?> _detectEntry(Uint8List bytes) async {
  var im = img.decodeImage(bytes);
  if (im == null) return null;
  if (im.numChannels < 3 || im.hasPalette) im = im.convert(numChannels: 3);
  final scale = _work / math.max(im.width, im.height);
  final sw = math.max(1, (im.width * scale).round());
  final sh = math.max(1, (im.height * scale).round());
  final small = img.copyResize(im, width: sw, height: sh);
  return FaceDetector._seamForTfliteModel(small);
}

/// Model-free detection: classify skin-coloured pixels, find their bounding
/// blob, and return it as the face region plus a skin mask. This is a heuristic
/// (no landmarks), good enough to target beauty ops; a model upgrades accuracy.
Face? _classicalDetect(img.Image im) {
  final w = im.width, h = im.height;
  final n = w * h;
  final skin = Uint8List(n);
  int count = 0, minX = w, minY = h, maxX = 0, maxY = 0;
  double sumX = 0, sumY = 0;

  for (int y = 0, i = 0; y < h; y++) {
    for (int x = 0; x < w; x++, i++) {
      final p = im.getPixel(x, y);
      if (_isSkin(p.r.toInt(), p.g.toInt(), p.b.toInt())) {
        skin[i] = 255;
        count++;
        sumX += x;
        sumY += y;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  // Require a meaningful amount of skin to call it a face.
  if (count < n * 0.01 || maxX <= minX || maxY <= minY) return null;

  // Tighten the box around the skin centroid to reduce stray-pixel spread:
  // keep within ~1.4 std-dev of the centroid in each axis.
  final mx = sumX / count, my = sumY / count;
  double vx = 0, vy = 0;
  for (int y = 0, i = 0; y < h; y++) {
    for (int x = 0; x < w; x++, i++) {
      if (skin[i] == 255) {
        vx += (x - mx) * (x - mx);
        vy += (y - my) * (y - my);
      }
    }
  }
  final sx = math.sqrt(vx / count), sy = math.sqrt(vy / count);
  final l = math.max(minX, (mx - sx * 1.6)).clamp(0, w - 1).toDouble();
  final r = math.min(maxX, (mx + sx * 1.6)).clamp(0, w - 1).toDouble();
  final t = math.max(minY, (my - sy * 1.6)).clamp(0, h - 1).toDouble();
  final b = math.min(maxY, (my + sy * 1.6)).clamp(0, h - 1).toDouble();

  return Face(
    left: l / w,
    top: t / h,
    right: r / w,
    bottom: b / h,
    skinAlpha: skin.map((v) => v.toDouble()).toList(),
    maskW: w,
    maskH: h,
  );
}

/// Skin-tone test in RGB + a YCbCr chroma check (robust to lighting).
bool _isSkin(int r, int g, int b) {
  // Basic RGB rule (Kovac et al.) for uniform daylight.
  final rgbRule = r > 95 &&
      g > 40 &&
      b > 20 &&
      (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b))) > 15 &&
      (r - g).abs() > 15 &&
      r > g &&
      r > b;
  if (rgbRule) return true;
  // YCbCr chroma rule catches more skin under varied lighting.
  final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
  final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
  return cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173;
}
