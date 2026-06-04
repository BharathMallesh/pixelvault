import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/edit_settings.dart';

class ImageProcessor {
  static Future<String> processAndSave({
    required String inputPath,
    required EditSettings settings,
    int jpegQuality = 90,
    bool asPng = false,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Could not decode image');

    image = _applyAll(image, settings);

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = asPng ? 'png' : 'jpg';
    final outPath = p.join(dir.path, 'pixelvault_$ts.$ext');

    final Uint8List encoded = asPng
        ? Uint8List.fromList(img.encodePng(image))
        : Uint8List.fromList(img.encodeJpg(image, quality: jpegQuality));

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

    // 3. Basic adjustments
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
      // Warmth = shift red/blue channels
      final warmAmt = s.warmth.round();
      image = img.adjustColor(image,
        redOffset: warmAmt,
        blueOffset: -warmAmt,
      );
    }

    // 4. Highlights & Shadows (tone mapping approximation)
    if (s.highlights != 0 || s.shadows != 0) {
      image = _applyTone(image, s.highlights, s.shadows);
    }

    // 5. Sharpness
    if (s.sharpness > 0) {
      image = img.convolution(image, filter: [
        0, -s.sharpness / 200,  0,
       -s.sharpness / 200, 1 + s.sharpness / 50, -s.sharpness / 200,
        0, -s.sharpness / 200,  0,
      ], div: 1);
    }

    // 6. Blur
    if (s.blurStrength > 0) {
      final radius = (s.blurStrength / 20).round().clamp(1, 10);
      image = img.gaussianBlur(image, radius: radius);
    }

    // 7. Vignette
    if (s.vignette > 0) {
      image = _applyVignette(image, s.vignette / 100);
    }

    return image;
  }

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
}
