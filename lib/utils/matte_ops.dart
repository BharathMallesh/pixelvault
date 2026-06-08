import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'ai_service.dart';

/// Phase 7 — operations on a cutout matte (the 8-bit alpha plane from
/// [CutoutResult]): manual refine (add/erase brush), edge feather/shift, and
/// background replacement (solid / gradient / photo).
///
/// All functions are pure and operate on plain buffers, so they're fully
/// headless-testable. Heavy variants (encode) run on a background isolate.

/// A normalized brush dab on the matte: centre (0..1) + radius (0..1 of the
/// longest side), and whether it adds the subject (alpha→255) or erases it
/// (alpha→0). [softness] 0..1 feathers the dab edge.
class MatteDab {
  final double x, y, radius;
  final bool add; // true = paint subject, false = erase to background
  final double softness;
  const MatteDab({
    required this.x,
    required this.y,
    required this.radius,
    required this.add,
    this.softness = 0.5,
  });
}

class MatteOps {
  /// Apply [dab] to [alpha] (width*height, 0..255) in place-style, returning a
  /// new buffer. Inside the radius the alpha moves toward 255 (add) or 0
  /// (erase); a soft ring blends proportionally.
  static Uint8List paintDab(
    Uint8List alpha,
    int w,
    int h,
    MatteDab dab,
  ) {
    final out = Uint8List.fromList(alpha);
    final cx = dab.x * w;
    final cy = dab.y * h;
    final r = dab.radius * math.max(w, h);
    if (r <= 0) return out;
    final soft = (dab.softness.clamp(0.0, 1.0)) * r;
    final inner = math.max(0.0, r - soft);
    final target = dab.add ? 255 : 0;

    final minX = math.max(0, (cx - r).floor());
    final maxX = math.min(w - 1, (cx + r).ceil());
    final minY = math.max(0, (cy - r).floor());
    final maxY = math.min(h - 1, (cy + r).ceil());

    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
        if (d > r) continue;
        double t; // 1 = full effect, 0 = none
        if (d <= inner || soft <= 0) {
          t = 1.0;
        } else {
          t = (1.0 - (d - inner) / soft).clamp(0.0, 1.0);
        }
        final i = y * w + x;
        out[i] = (out[i] + (target - out[i]) * t).round().clamp(0, 255);
      }
    }
    return out;
  }

  /// Separable box-blur feather of the matte edge, [radius] px, two passes.
  static Uint8List feather(Uint8List alpha, int w, int h, {int radius = 2}) {
    if (radius < 1) return Uint8List.fromList(alpha);
    Uint8List src = alpha;
    for (int pass = 0; pass < 2; pass++) {
      final tmp = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        final row = y * w;
        int sum = 0;
        for (int x = -radius; x <= radius; x++) {
          sum += src[row + x.clamp(0, w - 1)];
        }
        final div = radius * 2 + 1;
        for (int x = 0; x < w; x++) {
          tmp[row + x] = (sum / div).round();
          sum += src[row + (x + radius + 1).clamp(0, w - 1)] -
              src[row + (x - radius).clamp(0, w - 1)];
        }
      }
      final out = Uint8List(w * h);
      for (int x = 0; x < w; x++) {
        int sum = 0;
        for (int y = -radius; y <= radius; y++) {
          sum += tmp[y.clamp(0, h - 1) * w + x];
        }
        final div = radius * 2 + 1;
        for (int y = 0; y < h; y++) {
          out[y * w + x] = (sum / div).round();
          sum += tmp[(y + radius + 1).clamp(0, h - 1) * w + x] -
              tmp[(y - radius).clamp(0, h - 1) * w + x];
        }
      }
      src = out;
    }
    return src;
  }

  /// Shift the matte edge: positive [amount] (0..1) grows the subject (dilate),
  /// negative shrinks it (erode). Implemented as a threshold on a feathered
  /// copy — cheap and good enough for edge tuning.
  static Uint8List shiftEdge(Uint8List alpha, int w, int h, double amount) {
    if (amount == 0) return Uint8List.fromList(alpha);
    final out = Uint8List(w * h);
    // Bias the 50% threshold: growing lowers it, shrinking raises it.
    final threshold = (128 - amount * 127).round().clamp(1, 254);
    for (int i = 0; i < alpha.length; i++) {
      out[i] = alpha[i] >= threshold ? 255 : (alpha[i] * 0);
    }
    // Keep soft edges: blend original where it was already partial.
    for (int i = 0; i < alpha.length; i++) {
      if (alpha[i] > 0 && alpha[i] < 255) {
        out[i] = math.max(out[i], alpha[i]);
      }
    }
    return out;
  }

  /// Composite the subject (from [photo]) over a solid [r,g,b] background using
  /// [alpha]. All buffers share width*height. Returns an RGB image.
  static img.Image overSolid(
    img.Image photo,
    Uint8List alpha,
    int w,
    int h,
    int r,
    int g,
    int b,
  ) {
    final out = img.Image(width: w, height: h, numChannels: 3);
    for (int y = 0, i = 0; y < h; y++) {
      for (int x = 0; x < w; x++, i++) {
        final a = alpha[i] / 255.0;
        final p = photo.getPixel(x, y);
        out.setPixelRgb(
          x,
          y,
          (p.r * a + r * (1 - a)).round(),
          (p.g * a + g * (1 - a)).round(),
          (p.b * a + b * (1 - a)).round(),
        );
      }
    }
    return out;
  }

  /// Composite the subject over a vertical linear gradient from (r1,g1,b1) at
  /// the top to (r2,g2,b2) at the bottom.
  static img.Image overGradient(
    img.Image photo,
    Uint8List alpha,
    int w,
    int h,
    List<int> top,
    List<int> bottom,
  ) {
    final out = img.Image(width: w, height: h, numChannels: 3);
    for (int y = 0; y < h; y++) {
      final ty = h > 1 ? y / (h - 1) : 0.0;
      final br = (top[0] + (bottom[0] - top[0]) * ty);
      final bg = (top[1] + (bottom[1] - top[1]) * ty);
      final bb = (top[2] + (bottom[2] - top[2]) * ty);
      for (int x = 0; x < w; x++) {
        final i = y * w + x;
        final a = alpha[i] / 255.0;
        final p = photo.getPixel(x, y);
        out.setPixelRgb(
          x,
          y,
          (p.r * a + br * (1 - a)).round(),
          (p.g * a + bg * (1 - a)).round(),
          (p.b * a + bb * (1 - a)).round(),
        );
      }
    }
    return out;
  }

  /// Composite the subject over a background [bg] image ("cover"-fit to fill).
  static img.Image overPhoto(
    img.Image photo,
    Uint8List alpha,
    int w,
    int h,
    img.Image bg,
  ) {
    final fitted = _coverFit(bg, w, h);
    final out = img.Image(width: w, height: h, numChannels: 3);
    for (int y = 0, i = 0; y < h; y++) {
      for (int x = 0; x < w; x++, i++) {
        final a = alpha[i] / 255.0;
        final p = photo.getPixel(x, y);
        final q = fitted.getPixel(x, y);
        out.setPixelRgb(
          x,
          y,
          (p.r * a + q.r * (1 - a)).round(),
          (p.g * a + q.g * (1 - a)).round(),
          (p.b * a + q.b * (1 - a)).round(),
        );
      }
    }
    return out;
  }

  /// Center-crop + scale [src] to exactly [w]x[h] (cover).
  static img.Image _coverFit(img.Image src, int w, int h) {
    final scale = math.max(w / src.width, h / src.height);
    final rw = (src.width * scale).round();
    final rh = (src.height * scale).round();
    final resized = img.copyResize(src, width: rw, height: rh);
    final dx = ((rw - w) / 2).round();
    final dy = ((rh - h) / 2).round();
    return img.copyCrop(resized, x: dx, y: dy, width: w, height: h);
  }
}

// ── Isolate-backed background replace (decode + composite + encode) ──────────

enum BgKind { solid, gradient, photo }

class BgReplaceRequest {
  final Uint8List photoBytes;
  final CutoutResult matte;
  final BgKind kind;
  final List<int> color; // solid: rgb; gradient: [r1,g1,b1,r2,g2,b2]
  final Uint8List? bgBytes; // photo background
  final bool asPng;
  final int jpegQuality;
  const BgReplaceRequest({
    required this.photoBytes,
    required this.matte,
    required this.kind,
    this.color = const [255, 255, 255],
    this.bgBytes,
    this.asPng = false,
    this.jpegQuality = 95,
  });
}

/// Replace the background of [photoBytes] using [matte], off the UI thread.
Future<Uint8List> replaceBackground(BgReplaceRequest req) =>
    compute(_replaceEntry, req);

Future<Uint8List> _replaceEntry(BgReplaceRequest req) async {
  var photo = img.decodeImage(req.photoBytes);
  if (photo == null) throw Exception('Could not decode photo for bg replace');
  if (photo.numChannels < 3 || photo.hasPalette) {
    photo = photo.convert(numChannels: 3);
  }
  final m = req.matte;
  if (m.width != photo.width || m.height != photo.height) {
    photo = img.copyResize(photo, width: m.width, height: m.height);
  }
  final w = m.width, h = m.height;

  img.Image out;
  switch (req.kind) {
    case BgKind.solid:
      out = MatteOps.overSolid(
          photo, m.alpha, w, h, req.color[0], req.color[1], req.color[2]);
      break;
    case BgKind.gradient:
      out = MatteOps.overGradient(photo, m.alpha, w, h,
          req.color.sublist(0, 3), req.color.sublist(3, 6));
      break;
    case BgKind.photo:
      final bg = img.decodeImage(req.bgBytes!);
      if (bg == null) throw Exception('Could not decode background image');
      out = MatteOps.overPhoto(photo, m.alpha, w, h, bg);
      break;
  }
  return req.asPng ? img.encodePng(out) : img.encodeJpg(out, quality: req.jpegQuality);
}
