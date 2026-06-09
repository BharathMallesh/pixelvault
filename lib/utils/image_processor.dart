import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/edit_settings.dart';
import '../models/brush_mask.dart';

/// Arguments for the background-isolate processing entrypoint.
class _ProcessJob {
  final Uint8List bytes;
  final EditSettings settings;
  final int jpegQuality;
  final bool asPng;
  const _ProcessJob({
    required this.bytes,
    required this.settings,
    required this.jpegQuality,
    required this.asPng,
  });
}

/// Top-level entry run inside the isolate spawned by `compute`.
Future<Uint8List> _processJobEntry(_ProcessJob job) => ImageProcessor.processBytes(
      inputBytes: job.bytes,
      settings: job.settings,
      jpegQuality: job.jpegQuality,
      asPng: job.asPng,
    );

/// One collage cell: a normalized rect (0..1) plus the source image bytes
/// (null = empty slot, painted as a dark placeholder).
class CollageCell {
  final double left, top, right, bottom;
  final Uint8List? bytes;
  // Per-cell pan/zoom so the user can choose what shows inside the cell.
  // [zoom] >= 1 adds zoom on top of the base "cover" fit. [panX]/[panY] are
  // -1..1 and pan within the cropped slack (0 = centered, ±1 = edge).
  final double zoom, panX, panY;
  const CollageCell({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.bytes,
    this.zoom = 1.0,
    this.panX = 0.0,
    this.panY = 0.0,
  });
}

class ImageProcessor {
  /// Composite [cells] onto a square [canvasSize]px canvas, filling each cell
  /// with a center-cropped ("cover") version of its image and drawing borders
  /// of [borderWidth]px in [borderColor]. Returns encoded JPEG/PNG bytes.
  static Uint8List composeCollage({
    required List<CollageCell> cells,
    required int canvasSize,
    required double borderWidth,
    required int borderR,
    required int borderG,
    required int borderB,
    bool transparentBorder = false,
    bool asPng = false,
    int jpegQuality = 95,
  }) {
    final canvas = img.Image(
        width: canvasSize, height: canvasSize, numChannels: 4);
    // Background = border color (cells are inset by half the border, so the
    // gaps between them show this color). Transparent only works for PNG.
    if (transparentBorder && asPng) {
      img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
    } else {
      img.fill(canvas, color: img.ColorRgb8(borderR, borderG, borderB));
    }

    final half = (borderWidth / 2).round();
    for (final cell in cells) {
      if (cell.bytes == null) continue;
      var src = img.decodeImage(cell.bytes!);
      if (src == null) continue;
      if (src.numChannels < 3 || src.hasPalette) {
        src = src.convert(numChannels: 3);
      }

      final x = (cell.left * canvasSize).round() + half;
      final y = (cell.top * canvasSize).round() + half;
      final w = ((cell.right - cell.left) * canvasSize).round() - 2 * half;
      final h = ((cell.bottom - cell.top) * canvasSize).round() - 2 * half;
      if (w <= 0 || h <= 0) continue;

      // Base = CONTAIN (whole photo fits the cell), then apply the user's zoom
      // and pan. This matches the on-screen preview exactly. At zoom 1 the
      // whole photo shows, centered, with the border color filling any gap.
      final zoom = cell.zoom < 1.0 ? 1.0 : cell.zoom;
      final containScale = math.min(w / src.width, h / src.height);
      final scale = containScale * zoom;
      final rw = (src.width * scale).round().clamp(1, 1 << 16);
      final rh = (src.height * scale).round().clamp(1, 1 << 16);
      final resized = img.copyResize(src, width: rw, height: rh);

      // Make a cell-sized tile filled with the border color.
      final tile = img.Image(width: w, height: h, numChannels: 4);
      if (transparentBorder && asPng) {
        img.fill(tile, color: img.ColorRgba8(0, 0, 0, 0));
      } else {
        img.fill(tile, color: img.ColorRgba8(borderR, borderG, borderB, 255));
      }

      // Place the resized photo into the tile. dstX/dstY are where the photo's
      // top-left goes; can be negative (photo overflows, zoomed in) or positive
      // (photo smaller, letterboxed). Pan shifts within the overflow.
      final slackX = rw - w;
      final slackY = rh - h;
      final dstX = ((w - rw) / 2).round() +
          (-cell.panX.clamp(-1.0, 1.0) * (slackX > 0 ? slackX : 0) / 2).round();
      final dstY = ((h - rh) / 2).round() +
          (-cell.panY.clamp(-1.0, 1.0) * (slackY > 0 ? slackY : 0) / 2).round();

      // compositeImage clips negative offsets, so copy pixel-by-pixel over the
      // visible window instead (robust for overflow + letterbox alike).
      for (int ty = 0; ty < h; ty++) {
        final sy = ty - dstY;
        if (sy < 0 || sy >= rh) continue;
        for (int tx = 0; tx < w; tx++) {
          final sx = tx - dstX;
          if (sx < 0 || sx >= rw) continue;
          final sp = resized.getPixel(sx, sy);
          tile.setPixelRgba(tx, ty, sp.r, sp.g, sp.b, 255);
        }
      }

      img.compositeImage(canvas, tile, dstX: x, dstY: y);
    }

    return asPng
        ? Uint8List.fromList(img.encodePng(canvas))
        : Uint8List.fromList(img.encodeJpg(canvas, quality: jpegQuality));
  }

  /// Run [processBytes] on a background isolate so heavy full-resolution
  /// decoding/encoding never blocks the UI thread. Use this for saving; the
  /// live preview can call [processBytes] directly on small thumbnails.
  static Future<Uint8List> processBytesIsolated({
    required Uint8List inputBytes,
    required EditSettings settings,
    int jpegQuality = 95,
    bool asPng = false,
  }) {
    return compute(_processJobEntry, _ProcessJob(
      bytes: inputBytes,
      settings: settings,
      jpegQuality: jpegQuality,
      asPng: asPng,
    ));
  }

  /// Decode [inputBytes], apply [settings], and return the encoded result.
  /// Source bytes come from photo_manager (the gallery asset), so this works
  /// directly on bytes rather than assuming a file path on disk.
  static Future<Uint8List> processBytes({
    required Uint8List inputBytes,
    required EditSettings settings,
    int jpegQuality = 95,
    bool asPng = false,
  }) async {
    img.Image? image = img.decodeImage(inputBytes);
    if (image == null) throw Exception('Could not decode image');

    // Normalize to 3-channel RGB. Grayscale (1-ch) and palette images decode
    // with the value only in the red channel, which would render as a red
    // flood once written back to a 3-channel JPEG. Expanding here makes the
    // gray value populate R, G and B equally.
    if (image.numChannels < 3 || image.hasPalette) {
      image = image.convert(numChannels: 3);
    }

    image = _applyAll(image, settings);

    return asPng
        ? Uint8List.fromList(img.encodePng(image))
        : Uint8List.fromList(img.encodeJpg(image, quality: jpegQuality));
  }

  /// Convenience wrapper that reads from a file path and writes the result to
  /// the app documents directory. Kept for batch/file-based callers.
  static Future<String> processAndSave({
    required String inputPath,
    required EditSettings settings,
    int jpegQuality = 95,
    bool asPng = false,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    final encoded = await processBytes(
      inputBytes: bytes,
      settings: settings,
      jpegQuality: jpegQuality,
      asPng: asPng,
    );

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = asPng ? 'png' : 'jpg';
    final outPath = p.join(dir.path, 'pixelvault_$ts.$ext');
    await File(outPath).writeAsBytes(encoded);
    return outPath;
  }

  static img.Image _applyAll(img.Image image, EditSettings s) {
    // 1. Crop
    if (s.cropRect != null) {
      final cr = s.cropRect!;
      final x = (cr.left * image.width).round();
      final y = (cr.top * image.height).round();
      final w = ((cr.right - cr.left) * image.width).round();
      final h = ((cr.bottom - cr.top) * image.height).round();
      image = img.copyCrop(image, x: x, y: y, width: w, height: h);
    }

    // 2. Rotation & flip
    if (s.rotation != 0) image = img.copyRotate(image, angle: s.rotation);
    if (s.flipHorizontal) image = img.flipHorizontal(image);
    if (s.flipVertical)   image = img.flipVertical(image);

    // 3. Perspective correction (keystone)
    if (s.perspectiveVertical != 0 || s.perspectiveHorizontal != 0) {
      image = _applyPerspective(
          image, s.perspectiveVertical / 100, s.perspectiveHorizontal / 100);
    }

    // 4. Healing brush (clone clean nearby patches over marked spots).
    //    Done before color grading so healed pixels are graded consistently.
    if (s.healMask.isNotEmpty) {
      image = _applyHeal(image, s.healMask);
    }

    // 5. Basic adjustments
    if (s.brightness != 0) {
      // adjustColor.brightness is a multiplier (1.0 = no change), not an
      // additive offset, so map the -100..100 slider around 1.0:
      // +100 -> ~2.0 (brighter), -100 -> 0.0 (black).
      image = img.adjustColor(image, brightness: 1.0 + s.brightness / 100);
    }
    if (s.contrast != 0) {
      image = img.adjustColor(image, contrast: 1.0 + s.contrast / 100);
    }
    if (s.saturation != 0) {
      image = img.adjustColor(image, saturation: 1.0 + s.saturation / 100);
    }
    // Tone curve (master RGB).
    if (!_curveIsIdentity(s.curve)) {
      image = _applyCurve(image, s.curve);
    }
    if (s.warmth != 0) {
      // Warmth = shift red up and blue down (or vice versa).
      image = _applyWarmth(image, s.warmth.round());
    }
    if (s.tint != 0) {
      // Tint = green/magenta axis: shift green vs red+blue.
      image = _applyTint(image, s.tint.round());
    }
    if (s.vibrance != 0) {
      // Vibrance = saturation that spares already-saturated pixels.
      image = _applyVibrance(image, s.vibrance / 100);
    }
    if (s.clarity != 0) {
      // Clarity = local-contrast / midtone punch via unsharp mask.
      image = _applyClarity(image, s.clarity / 100);
    }

    // 6. Highlights & Shadows (tone mapping approximation)
    if (s.highlights != 0 || s.shadows != 0) {
      image = _applyTone(image, s.highlights, s.shadows);
    }

    // 7. HSL per-channel color grading
    if (_hasHslEdits(s)) {
      image = _applyHsl(image, s);
    }

    // 8. Selective (masked) local adjustments
    if (s.selectiveMask.isNotEmpty &&
        (s.selBrightness != 0 || s.selContrast != 0 ||
         s.selSaturation != 0 || s.selWarmth != 0)) {
      image = _applySelective(image, s);
    }

    // 9. Dehaze (lift contrast + saturation to cut atmospheric haze)
    if (s.dehaze > 0) {
      image = _applyDehaze(image, s.dehaze / 100);
    }

    // 10. Sharpness
    if (s.sharpness > 0) {
      image = img.convolution(image, filter: [
        0, -s.sharpness / 200,  0,
       -s.sharpness / 200, 1 + s.sharpness / 50, -s.sharpness / 200,
        0, -s.sharpness / 200,  0,
      ], div: 1);
    }

    // 11. Noise reduction (light gaussian smoothing)
    if (s.noiseReduction > 0) {
      final r = (s.noiseReduction / 50).round().clamp(1, 3);
      image = img.gaussianBlur(image, radius: r);
    }

    // 12. Background blur. If the user painted a focus mask, keep that region
    //     sharp and blur everything else; otherwise fall back to a
    //     center-weighted radial blur.
    if (s.blurStrength > 0) {
      image = _applyBackgroundBlur(
          image, s.blurStrength / 100, s.focusMask);
    }

    // 13. Vignette
    if (s.vignette > 0) {
      image = _applyVignette(image, s.vignette / 100);
    }

    // 14. Light overlay effect (Phase 8.3) — screen/add-blended gradients.
    if (s.overlayEffect != 'none' && s.overlayStrength > 0) {
      image = _applyOverlayEffect(image, s.overlayEffect, s.overlayStrength / 100);
    }

    // 15. Frame / border (Phase 8.2) — drawn last so it sits over everything.
    if (s.frameStyle != 'none' && s.frameWidth > 0) {
      image = _applyFrame(image, s.frameStyle, s.frameWidth / 100);
    }

    return image;
  }

  // ── Light overlay effects (Phase 8.3) ──────────────────────────────
  // All procedurally generated (no bundled artwork). [strength] 0..1.
  static img.Image _applyOverlayEffect(
      img.Image src, String effect, double strength) {
    final w = src.width, h = src.height;
    final dst = img.Image.from(src);
    final maxD = math.sqrt(w * w + h * h) / 2;

    // Per-effect colour + placement of the light source.
    // Returns added light (0..255-ish) per channel for pixel (x,y).
    List<double> light(int x, int y) {
      switch (effect) {
        case 'leak_warm': {
          // Warm leak from the top-right corner.
          final d = math.sqrt(math.pow(x - w * 0.85, 2) + math.pow(y - h * 0.15, 2));
          final f = (1 - (d / (maxD * 1.2))).clamp(0.0, 1.0);
          return [255 * f, 150 * f, 60 * f];
        }
        case 'leak_cool': {
          // Cool leak from the bottom-left corner.
          final d = math.sqrt(math.pow(x - w * 0.15, 2) + math.pow(y - h * 0.85, 2));
          final f = (1 - (d / (maxD * 1.2))).clamp(0.0, 1.0);
          return [70 * f, 130 * f, 255 * f];
        }
        case 'sunflare': {
          // Bright warm flare from center-top.
          final d = math.sqrt(math.pow(x - w * 0.5, 2) + math.pow(y - h * 0.25, 2));
          final f = (1 - (d / (maxD * 0.9))).clamp(0.0, 1.0);
          final f2 = f * f;
          return [255 * f2, 230 * f2, 170 * f2];
        }
        case 'bokeh': {
          // Soft circular highlights on a deterministic grid.
          double acc = 0;
          for (int i = 0; i < 9; i++) {
            final bx = w * ((i * 0.37 + 0.1) % 1.0);
            final by = h * ((i * 0.61 + 0.2) % 1.0);
            final br = maxD * (0.06 + (i % 3) * 0.03);
            final d = math.sqrt((x - bx) * (x - bx) + (y - by) * (y - by));
            acc += (1 - (d / br)).clamp(0.0, 1.0);
          }
          final f = acc.clamp(0.0, 1.0);
          return [220 * f, 220 * f, 255 * f];
        }
        case 'grain': {
          // Deterministic film grain (value noise from coordinates).
          final n = ((math.sin(x * 12.9898 + y * 78.233) * 43758.5453) % 1.0);
          final v = (n - 0.5) * 90;
          return [v, v, v];
        }
        default:
          return const [0, 0, 0];
      }
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = dst.getPixel(x, y);
        final l = light(x, y);
        // Both light leaks (additive) and grain (signed) add to the channels.
        p.r = (p.r + l[0] * strength).clamp(0, 255);
        p.g = (p.g + l[1] * strength).clamp(0, 255);
        p.b = (p.b + l[2] * strength).clamp(0, 255);
      }
    }
    return dst;
  }

  // ── Frames / borders (Phase 8.2) ───────────────────────────────────
  static img.Image _applyFrame(img.Image src, String style, double widthFrac) {
    final w = src.width, h = src.height;
    final border = (math.min(w, h) * widthFrac / 4).round().clamp(1, math.min(w, h) ~/ 2);

    img.ColorRgb8 col;
    int top = border, bottom = border, left = border, right = border;
    switch (style) {
      case 'black':
        col = img.ColorRgb8(0, 0, 0);
        break;
      case 'film':
        // Black border with a thicker top/bottom (cinematic).
        col = img.ColorRgb8(0, 0, 0);
        top = bottom = (border * 1.8).round();
        break;
      case 'polaroid':
        // White with a much thicker bottom.
        col = img.ColorRgb8(245, 245, 240);
        bottom = (border * 4).round();
        break;
      case 'white':
      case 'rounded':
      default:
        col = img.ColorRgb8(255, 255, 255);
        break;
    }

    final dst = img.Image.from(src);
    img.fillRect(dst, x1: 0, y1: 0, x2: w - 1, y2: top - 1, color: col);
    img.fillRect(dst, x1: 0, y1: h - bottom, x2: w - 1, y2: h - 1, color: col);
    img.fillRect(dst, x1: 0, y1: 0, x2: left - 1, y2: h - 1, color: col);
    img.fillRect(dst, x1: w - right, y1: 0, x2: w - 1, y2: h - 1, color: col);

    if (style == 'rounded') {
      // Round the inner photo corners by painting white quarter-circles.
      final rad = border * 3;
      _roundCorner(dst, left, top, rad, true, true, col);
      _roundCorner(dst, w - right - 1, top, rad, false, true, col);
      _roundCorner(dst, left, h - bottom - 1, rad, true, false, col);
      _roundCorner(dst, w - right - 1, h - bottom - 1, rad, false, false, col);
    }
    return dst;
  }

  static void _roundCorner(img.Image im, int cornerX, int cornerY, int rad,
      bool left, bool top, img.Color col) {
    final ccx = cornerX + (left ? rad : -rad);
    final ccy = cornerY + (top ? rad : -rad);
    for (int dy = 0; dy < rad; dy++) {
      for (int dx = 0; dx < rad; dx++) {
        final x = left ? cornerX + dx : cornerX - dx;
        final y = top ? cornerY + dy : cornerY - dy;
        if (x < 0 || y < 0 || x >= im.width || y >= im.height) continue;
        final d = math.sqrt((x - ccx) * (x - ccx) + (y - ccy) * (y - ccy));
        if (d > rad) im.setPixel(x, y, col);
      }
    }
  }

  // ── Warmth (color temperature) ─────────────────────────────────────
  static img.Image _applyWarmth(img.Image src, int amount) {
    final dst = img.Image.from(src);
    for (final pixel in dst) {
      pixel.r = (pixel.r + amount).clamp(0, 255);
      pixel.b = (pixel.b - amount).clamp(0, 255);
    }
    return dst;
  }

  // ── Tone curve ─────────────────────────────────────────────────────
  static bool _curveIsIdentity(List<CurvePoint> pts) {
    if (pts.isEmpty) return true;
    for (final p in pts) {
      if ((p.x - p.y).abs() > 0.001) return false;
    }
    return true;
  }

  /// Build a 256-entry lookup table from the curve's control points (sorted by
  /// x, piecewise-linear) and remap every channel through it.
  static img.Image _applyCurve(img.Image src, List<CurvePoint> pts) {
    final sorted = [...pts]..sort((a, b) => a.x.compareTo(b.x));
    final lut = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      final x = i / 255.0;
      double y;
      if (x <= sorted.first.x) {
        y = sorted.first.y;
      } else if (x >= sorted.last.x) {
        y = sorted.last.y;
      } else {
        y = sorted.last.y;
        for (int k = 0; k < sorted.length - 1; k++) {
          final a = sorted[k], b = sorted[k + 1];
          if (x >= a.x && x <= b.x) {
            final t = (b.x - a.x) == 0 ? 0.0 : (x - a.x) / (b.x - a.x);
            y = a.y + (b.y - a.y) * t;
            break;
          }
        }
      }
      lut[i] = (y * 255).clamp(0, 255).round();
    }
    final dst = img.Image.from(src);
    for (final p in dst) {
      p.r = lut[p.r.clamp(0, 255).toInt()];
      p.g = lut[p.g.clamp(0, 255).toInt()];
      p.b = lut[p.b.clamp(0, 255).toInt()];
    }
    return dst;
  }

  // ── Dehaze ─────────────────────────────────────────────────────────
  // Haze flattens contrast and washes out color. Counter it by stretching
  // contrast around mid-gray and lifting saturation, scaled by [amount].
  static img.Image _applyDehaze(img.Image src, double amount) {
    final contrast = 1.0 + amount * 0.5;       // up to +50% contrast
    final satScale = 1.0 + amount * 0.4;       // up to +40% saturation
    final dst = img.Image.from(src);
    for (final pixel in dst) {
      double r = pixel.r.toDouble(), g = pixel.g.toDouble(), b = pixel.b.toDouble();
      // Contrast around 128
      r = (r - 128) * contrast + 128;
      g = (g - 128) * contrast + 128;
      b = (b - 128) * contrast + 128;
      // Saturation around luminance
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      r = lum + (r - lum) * satScale;
      g = lum + (g - lum) * satScale;
      b = lum + (b - lum) * satScale;
      pixel.r = r.clamp(0, 255).round();
      pixel.g = g.clamp(0, 255).round();
      pixel.b = b.clamp(0, 255).round();
    }
    return dst;
  }

  // ── Tint (green / magenta) ─────────────────────────────────────────
  static img.Image _applyTint(img.Image src, int amount) {
    final dst = img.Image.from(src);
    final half = (amount / 2).round();
    for (final pixel in dst) {
      // Positive = greener; negative = magenta (more red+blue).
      pixel.g = (pixel.g + amount).clamp(0, 255);
      pixel.r = (pixel.r - half).clamp(0, 255);
      pixel.b = (pixel.b - half).clamp(0, 255);
    }
    return dst;
  }

  // ── Vibrance ───────────────────────────────────────────────────────
  // Like saturation, but scaled down for pixels that are already saturated,
  // so it boosts muted colors without over-cooking vivid ones.
  static img.Image _applyVibrance(img.Image src, double amount) {
    final dst = img.Image.from(src);
    for (final pixel in dst) {
      final r = pixel.r.toDouble(), g = pixel.g.toDouble(), b = pixel.b.toDouble();
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      final curSat = mx == 0 ? 0.0 : (mx - mn) / mx; // 0..1
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      // Less-saturated pixels get the full push; saturated ones get little.
      final scale = amount * (1.0 - curSat);
      pixel.r = (lum + (r - lum) * (1 + scale)).clamp(0, 255).round();
      pixel.g = (lum + (g - lum) * (1 + scale)).clamp(0, 255).round();
      pixel.b = (lum + (b - lum) * (1 + scale)).clamp(0, 255).round();
    }
    return dst;
  }

  // ── Clarity (local-contrast / midtone punch) ───────────────────────
  // Unsharp mask: blend the image away from a blurred copy to boost local
  // contrast. Positive adds punch; negative softens.
  static img.Image _applyClarity(img.Image src, double amount) {
    final blurred = img.gaussianBlur(img.Image.from(src), radius: 8);
    final dst = img.Image.from(src);
    for (final pixel in dst) {
      final bp = blurred.getPixel(pixel.x, pixel.y);
      pixel.r = (pixel.r + (pixel.r - bp.r) * amount).clamp(0, 255).round();
      pixel.g = (pixel.g + (pixel.g - bp.g) * amount).clamp(0, 255).round();
      pixel.b = (pixel.b + (pixel.b - bp.b) * amount).clamp(0, 255).round();
    }
    return dst;
  }

  // ── Tone (highlights / shadows) ────────────────────────────────────
  static img.Image _applyTone(img.Image src, double highlights, double shadows) {
    final dst = img.Image.from(src);
    for (final pixel in dst) {
      final lum = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255;
      double factor = 1.0;
      if (lum > 0.5 && highlights != 0) {
        factor += (highlights / 100) * ((lum - 0.5) * 2);
      } else if (lum < 0.5 && shadows != 0) {
        factor += (shadows / 100) * ((0.5 - lum) * 2);
      }
      pixel.r = (pixel.r * factor).clamp(0, 255).round();
      pixel.g = (pixel.g * factor).clamp(0, 255).round();
      pixel.b = (pixel.b * factor).clamp(0, 255).round();
    }
    return dst;
  }

  // ── HSL per-channel ────────────────────────────────────────────────
  // Six color bands centred on these hues (degrees). Each pixel's hue is
  // assigned a smooth membership weight to nearby bands, and that band's
  // hue/sat/lum deltas are applied weighted by membership.
  static const List<_HslBand> _bands = [
    _HslBand('red', 0),
    _HslBand('orange', 30),
    _HslBand('yellow', 60),
    _HslBand('green', 120),
    _HslBand('blue', 220),
    _HslBand('purple', 285),
  ];

  static bool _hasHslEdits(EditSettings s) =>
      s.hslRedHue != 0 || s.hslRedSat != 0 || s.hslRedLum != 0 ||
      s.hslOrangeHue != 0 || s.hslOrangeSat != 0 || s.hslOrangeLum != 0 ||
      s.hslYellowHue != 0 || s.hslYellowSat != 0 || s.hslYellowLum != 0 ||
      s.hslGreenHue != 0 || s.hslGreenSat != 0 || s.hslGreenLum != 0 ||
      s.hslBlueHue != 0 || s.hslBlueSat != 0 || s.hslBlueLum != 0 ||
      s.hslPurpleHue != 0 || s.hslPurpleSat != 0 || s.hslPurpleLum != 0;

  static ({double hue, double sat, double lum}) _hslDeltas(
      EditSettings s, String band) {
    switch (band) {
      case 'red':    return (hue: s.hslRedHue, sat: s.hslRedSat, lum: s.hslRedLum);
      case 'orange': return (hue: s.hslOrangeHue, sat: s.hslOrangeSat, lum: s.hslOrangeLum);
      case 'yellow': return (hue: s.hslYellowHue, sat: s.hslYellowSat, lum: s.hslYellowLum);
      case 'green':  return (hue: s.hslGreenHue, sat: s.hslGreenSat, lum: s.hslGreenLum);
      case 'blue':   return (hue: s.hslBlueHue, sat: s.hslBlueSat, lum: s.hslBlueLum);
      case 'purple': return (hue: s.hslPurpleHue, sat: s.hslPurpleSat, lum: s.hslPurpleLum);
      default:       return (hue: 0, sat: 0, lum: 0);
    }
  }

  static img.Image _applyHsl(img.Image src, EditSettings s) {
    final dst = img.Image.from(src);
    // Precompute per-band deltas once.
    final deltas = {for (final b in _bands) b.name: _hslDeltas(s, b.name)};

    for (final pixel in dst) {
      final hsl = _rgbToHsl(pixel.r / 255, pixel.g / 255, pixel.b / 255);
      double h = hsl.h; // 0..360
      double sat = hsl.s; // 0..1
      double lum = hsl.l; // 0..1

      double hueShift = 0, satScale = 0, lumScale = 0;
      for (final band in _bands) {
        final w = _bandWeight(h, band.center);
        if (w <= 0) continue;
        final d = deltas[band.name]!;
        // Hue: ±0.3 of a 30° step per slider unit feels natural.
        hueShift += w * (d.hue / 100) * 30;
        satScale += w * (d.sat / 100);
        lumScale += w * (d.lum / 100);
      }

      h = (h + hueShift) % 360;
      if (h < 0) h += 360;
      sat = (sat * (1 + satScale)).clamp(0.0, 1.0);
      lum = (lum * (1 + lumScale)).clamp(0.0, 1.0);

      final rgb = _hslToRgb(h, sat, lum);
      pixel.r = (rgb.r * 255).clamp(0, 255).round();
      pixel.g = (rgb.g * 255).clamp(0, 255).round();
      pixel.b = (rgb.b * 255).clamp(0, 255).round();
    }
    return dst;
  }

  /// Triangular membership: full weight at the band center, fading to 0 at
  /// ±60° (the neighbouring bands), accounting for hue wrap-around.
  static double _bandWeight(double hue, double center) {
    double diff = (hue - center).abs();
    if (diff > 180) diff = 360 - diff;
    const falloff = 60.0;
    if (diff >= falloff) return 0;
    return 1.0 - diff / falloff;
  }

  // ── Perspective (keystone) correction ──────────────────────────────
  // Positive vertical pulls the top inward (corrects "leaning back"); positive
  // horizontal pulls the right inward. Implemented as an inverse bilinear warp
  // mapping each destination pixel back to a source sample.
  static img.Image _applyPerspective(
      img.Image src, double vert, double horiz) {
    final w = src.width;
    final h = src.height;
    final dst = img.Image(width: w, height: h, numChannels: src.numChannels);

    // Corner insets as fractions of width/height.
    final topInset = vert > 0 ? vert : 0.0;       // shrink top edge
    final botInset = vert < 0 ? -vert : 0.0;      // shrink bottom edge
    final leftInset = horiz < 0 ? -horiz : 0.0;   // shrink left edge
    final rightInset = horiz > 0 ? horiz : 0.0;   // shrink right edge

    for (int y = 0; y < h; y++) {
      final fy = y / (h - 1);
      // Horizontal extent of the trapezoid at this row.
      final rowLeft = (topInset * (1 - fy) + botInset * fy) * 0.5;
      final rowRight = 1.0 - rowLeft;
      for (int x = 0; x < w; x++) {
        final fx = x / (w - 1);
        // Map destination fx into the source row span -> source u.
        final u = rowLeft + fx * (rowRight - rowLeft);
        // Vertical extent at this column (for horizontal keystone).
        final colTop = (leftInset * (1 - fx) + rightInset * fx) * 0.5;
        final colBot = 1.0 - colTop;
        final v = colTop + fy * (colBot - colTop);

        final sx = u * (w - 1);
        final sy = v * (h - 1);
        final sample = _bilinearSample(src, sx, sy);
        dst.setPixel(x, y, sample);
      }
    }
    return dst;
  }

  static img.Color _bilinearSample(img.Image src, double sx, double sy) {
    final x0 = sx.floor().clamp(0, src.width - 1);
    final y0 = sy.floor().clamp(0, src.height - 1);
    final x1 = (x0 + 1).clamp(0, src.width - 1);
    final y1 = (y0 + 1).clamp(0, src.height - 1);
    final dx = sx - x0;
    final dy = sy - y0;

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    double lerp(num a, num b, double t) => a + (b - a) * t;
    double chan(num a, num b, num c, num d) =>
        lerp(lerp(a, b, dx), lerp(c, d, dx), dy);

    return img.ColorRgb8(
      chan(p00.r, p10.r, p01.r, p11.r).round().clamp(0, 255),
      chan(p00.g, p10.g, p01.g, p11.g).round().clamp(0, 255),
      chan(p00.b, p10.b, p01.b, p11.b).round().clamp(0, 255),
    );
  }

  // ── Background blur (bokeh) ────────────────────────────────────────
  // Blurs the whole image, then blends the sharp original back into the
  // in-focus region. If the user painted a [focusMask], that region stays
  // sharp; otherwise we fall back to a center-weighted radial focus. Either
  // way the focus boundary is feathered for a natural transition.
  static img.Image _applyBackgroundBlur(
      img.Image src, double strength, BrushMask focusMask) {
    final radius = (strength * 12).round().clamp(1, 14);
    final blurred = img.gaussianBlur(img.Image.from(src), radius: radius);
    final dst = img.Image.from(src);

    if (focusMask.isNotEmpty) {
      // sharpness[i] in 0..1 — 1 = keep sharp (subject), 0 = fully blurred.
      final sharp = _rasterizeMask(focusMask, src.width, src.height,
          feather: 0.04);
      for (final pixel in dst) {
        final keep = sharp[pixel.y * src.width + pixel.x];
        final t = 1.0 - keep; // blend amount toward blurred
        if (t <= 0) continue;
        final bp = blurred.getPixel(pixel.x, pixel.y);
        pixel.r = (pixel.r * (1 - t) + bp.r * t).round();
        pixel.g = (pixel.g * (1 - t) + bp.g * t).round();
        pixel.b = (pixel.b * (1 - t) + bp.b * t).round();
      }
      return dst;
    }

    // Fallback: center-weighted radial focus.
    final cx = src.width / 2.0;
    final cy = src.height / 2.0;
    final maxDist = math.sqrt(cx * cx + cy * cy);
    final focus = (1.0 - strength) * 0.45 + 0.15; // 0.15..0.60 of maxDist
    const feather = 0.25;
    for (final pixel in dst) {
      final dx = pixel.x - cx;
      final dy = pixel.y - cy;
      final dist = math.sqrt(dx * dx + dy * dy) / maxDist;
      double t = ((dist - focus) / feather).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final bp = blurred.getPixel(pixel.x, pixel.y);
      pixel.r = (pixel.r * (1 - t) + bp.r * t).round();
      pixel.g = (pixel.g * (1 - t) + bp.g * t).round();
      pixel.b = (pixel.b * (1 - t) + bp.b * t).round();
    }
    return dst;
  }

  // ── Healing brush (patch-clone fill) ───────────────────────────────
  // For each marked dab, copy a clean patch from a nearby offset region over
  // the spot, blended with a feathered (radial falloff) edge so the repair is
  // seamless. The source patch is offset perpendicular-ish to keep texture.
  static img.Image _applyHeal(img.Image src, BrushMask mask) {
    final dst = img.Image.from(src);
    final w = src.width, h = src.height;

    for (final dab in mask.dabs) {
      final cx = (dab.x * w).round();
      final cy = (dab.y * h).round();
      final r = (dab.radius * w).round().clamp(2, w);

      // Pick a clean source center offset by ~2 radii. Try right, then left,
      // then down, then up — whichever stays in bounds.
      final candidates = <List<int>>[
        [cx + 2 * r, cy], [cx - 2 * r, cy],
        [cx, cy + 2 * r], [cx, cy - 2 * r],
      ];
      int sxc = cx, syc = cy;
      for (final c in candidates) {
        if (c[0] - r >= 0 && c[0] + r < w && c[1] - r >= 0 && c[1] + r < h) {
          sxc = c[0];
          syc = c[1];
          break;
        }
      }
      if (sxc == cx && syc == cy) continue; // no clean source found

      for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
          final dist = math.sqrt(dx * dx + dy * dy) / r;
          if (dist > 1.0) continue;
          final tx = cx + dx, ty = cy + dy;
          if (tx < 0 || tx >= w || ty < 0 || ty >= h) continue;
          final sx = sxc + dx, sy = syc + dy;
          if (sx < 0 || sx >= w || sy < 0 || sy >= h) continue;

          // Feather: full clone at center, fading to original near the edge.
          final blend = (1.0 - dist * dist).clamp(0.0, 1.0);
          final tp = dst.getPixel(tx, ty);
          final sp = src.getPixel(sx, sy);
          tp.r = (tp.r * (1 - blend) + sp.r * blend).round();
          tp.g = (tp.g * (1 - blend) + sp.g * blend).round();
          tp.b = (tp.b * (1 - blend) + sp.b * blend).round();
        }
      }
    }
    return dst;
  }

  // ── Selective (masked) adjustments ─────────────────────────────────
  // Apply brightness/contrast/saturation/warmth only inside the painted
  // region, weighted by a feathered mask so edits blend with their surrounds.
  static img.Image _applySelective(img.Image src, EditSettings s) {
    final dst = img.Image.from(src);
    final mask = _rasterizeMask(s.selectiveMask, src.width, src.height,
        feather: 0.05);
    final w = src.width;

    final bright = s.selBrightness / 100 * 255; // additive
    final contrast = 1.0 + s.selContrast / 100;
    final satScale = 1.0 + s.selSaturation / 100;
    final warmth = s.selWarmth.round();

    for (final pixel in dst) {
      final m = mask[pixel.y * w + pixel.x];
      if (m <= 0) continue;

      double r = pixel.r.toDouble();
      double g = pixel.g.toDouble();
      double b = pixel.b.toDouble();

      // Brightness (additive)
      r += bright; g += bright; b += bright;
      // Contrast around mid-gray
      r = (r - 128) * contrast + 128;
      g = (g - 128) * contrast + 128;
      b = (b - 128) * contrast + 128;
      // Saturation around luminance
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      r = lum + (r - lum) * satScale;
      g = lum + (g - lum) * satScale;
      b = lum + (b - lum) * satScale;
      // Warmth
      r += warmth; b -= warmth;

      // Blend edited result with original by mask coverage.
      pixel.r = (pixel.r * (1 - m) + r.clamp(0, 255) * m).round();
      pixel.g = (pixel.g * (1 - m) + g.clamp(0, 255) * m).round();
      pixel.b = (pixel.b * (1 - m) + b.clamp(0, 255) * m).round();
    }
    return dst;
  }

  // Rasterize a brush mask into a [w*h] coverage buffer in 0..1. Each dab
  // stamps a radial falloff; [feather] (fraction of width) softens the outer
  // edge. Values are accumulated and clamped so overlapping dabs stay solid.
  static List<double> _rasterizeMask(BrushMask mask, int w, int h,
      {double feather = 0.04}) {
    final buf = List<double>.filled(w * h, 0.0);
    final featherPx = (feather * w).clamp(1.0, w.toDouble());

    for (final dab in mask.dabs) {
      final cx = dab.x * w;
      final cy = dab.y * h;
      final r = dab.radius * w;
      final outer = r + featherPx;
      final x0 = (cx - outer).floor().clamp(0, w - 1);
      final x1 = (cx + outer).ceil().clamp(0, w - 1);
      final y0 = (cy - outer).floor().clamp(0, h - 1);
      final y1 = (cy + outer).ceil().clamp(0, h - 1);

      for (int y = y0; y <= y1; y++) {
        for (int x = x0; x <= x1; x++) {
          final dx = x - cx, dy = y - cy;
          final d = math.sqrt(dx * dx + dy * dy);
          double cov;
          if (d <= r) {
            cov = 1.0;
          } else if (d <= outer) {
            cov = 1.0 - (d - r) / featherPx; // linear feather
          } else {
            cov = 0.0;
          }
          if (cov <= 0) continue;
          final i = y * w + x;
          if (cov > buf[i]) buf[i] = cov; // union, keep strongest coverage
        }
      }
    }
    return buf;
  }

  // ── Vignette ───────────────────────────────────────────────────────
  static img.Image _applyVignette(img.Image src, double strength) {
    final dst = img.Image.from(src);
    final cx = src.width / 2.0;
    final cy = src.height / 2.0;
    final maxDist = math.sqrt(cx * cx + cy * cy);

    for (final pixel in dst) {
      final dx = pixel.x - cx;
      final dy = pixel.y - cy;
      final dist = math.sqrt(dx * dx + dy * dy) / maxDist;
      final darken = 1.0 - (dist * dist * strength);
      pixel.r = (pixel.r * darken).clamp(0, 255).round();
      pixel.g = (pixel.g * darken).clamp(0, 255).round();
      pixel.b = (pixel.b * darken).clamp(0, 255).round();
    }
    return dst;
  }

  // ── Thumbnails ─────────────────────────────────────────────────────
  static Future<Uint8List?> getThumbnailBytes(
      String inputPath, int maxDimension) async {
    try {
      final bytes = await File(inputPath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;
      if (image.width > maxDimension || image.height > maxDimension) {
        image = img.copyResize(image, width: maxDimension);
      }
      return Uint8List.fromList(img.encodeJpg(image, quality: 80));
    } catch (_) {
      return null;
    }
  }

  // ── Color space helpers ────────────────────────────────────────────
  static ({double h, double s, double l}) _rgbToHsl(
      double r, double g, double b) {
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    final l = (maxC + minC) / 2;
    double h = 0, s = 0;
    final d = maxC - minC;
    if (d != 0) {
      s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC);
      if (maxC == r) {
        h = (g - b) / d + (g < b ? 6 : 0);
      } else if (maxC == g) {
        h = (b - r) / d + 2;
      } else {
        h = (r - g) / d + 4;
      }
      h *= 60;
    }
    return (h: h, s: s, l: l);
  }

  static ({double r, double g, double b}) _hslToRgb(
      double h, double s, double l) {
    if (s == 0) return (r: l, g: l, b: l);
    double hue2rgb(double p, double q, double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }

    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    final hk = h / 360;
    return (
      r: hue2rgb(p, q, hk + 1 / 3),
      g: hue2rgb(p, q, hk),
      b: hue2rgb(p, q, hk - 1 / 3),
    );
  }
}

class _HslBand {
  final String name;
  final double center; // hue in degrees
  const _HslBand(this.name, this.center);
}
