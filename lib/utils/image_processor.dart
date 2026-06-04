import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/edit_settings.dart';

class ImageProcessor {
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

    // 4. Basic adjustments
    if (s.brightness != 0) {
      image = img.adjustColor(image, brightness: s.brightness / 100);
    }
    if (s.contrast != 0) {
      image = img.adjustColor(image, contrast: 1.0 + s.contrast / 100);
    }
    if (s.saturation != 0) {
      image = img.adjustColor(image, saturation: 1.0 + s.saturation / 100);
    }
    if (s.warmth != 0) {
      // Warmth = shift red up and blue down (or vice versa).
      image = _applyWarmth(image, s.warmth.round());
    }

    // 5. Highlights & Shadows (tone mapping approximation)
    if (s.highlights != 0 || s.shadows != 0) {
      image = _applyTone(image, s.highlights, s.shadows);
    }

    // 6. HSL per-channel color grading
    if (_hasHslEdits(s)) {
      image = _applyHsl(image, s);
    }

    // 7. Sharpness
    if (s.sharpness > 0) {
      image = img.convolution(image, filter: [
        0, -s.sharpness / 200,  0,
       -s.sharpness / 200, 1 + s.sharpness / 50, -s.sharpness / 200,
        0, -s.sharpness / 200,  0,
      ], div: 1);
    }

    // 8. Background blur (radial / center-weighted bokeh)
    if (s.blurStrength > 0) {
      image = _applyRadialBlur(image, s.blurStrength / 100);
    }

    // 9. Vignette
    if (s.vignette > 0) {
      image = _applyVignette(image, s.vignette / 100);
    }

    return image;
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

  // ── Radial background blur (bokeh approximation) ───────────────────
  // Blurs the whole image, then blends the sharp original back into the
  // centre using a radial mask, so the subject area (centre) stays in focus
  // while the surroundings soften. This is a center-weighted approximation,
  // not ML subject segmentation — see README TODO.
  static img.Image _applyRadialBlur(img.Image src, double strength) {
    final radius = (strength * 12).round().clamp(1, 14);
    final blurred = img.gaussianBlur(img.Image.from(src), radius: radius);

    final dst = img.Image.from(src);
    final cx = src.width / 2.0;
    final cy = src.height / 2.0;
    final maxDist = math.sqrt(cx * cx + cy * cy);
    // Sharp focus radius shrinks as strength grows.
    final focus = (1.0 - strength) * 0.45 + 0.15; // 0.15..0.60 of maxDist
    const feather = 0.25;

    for (final pixel in dst) {
      final dx = pixel.x - cx;
      final dy = pixel.y - cy;
      final dist = math.sqrt(dx * dx + dy * dy) / maxDist;
      // 0 = fully sharp, 1 = fully blurred.
      double t = (dist - focus) / feather;
      t = t.clamp(0.0, 1.0);
      if (t <= 0) continue;
      final bp = blurred.getPixel(pixel.x, pixel.y);
      pixel.r = (pixel.r * (1 - t) + bp.r * t).round();
      pixel.g = (pixel.g * (1 - t) + bp.g * t).round();
      pixel.b = (pixel.b * (1 - t) + bp.b * t).round();
    }
    return dst;
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
