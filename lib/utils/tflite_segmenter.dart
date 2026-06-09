import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Real on-device ML subject segmentation via a bundled TFLite model.
///
/// This is the genuine-AI path for Cutout. It is intentionally optional: if no
/// model file is bundled at [_modelAsset], [segment] returns null and the
/// caller (cutout_engine) falls back to the classical algorithm. Drop a model
/// at `assets/models/cutout.tflite` to activate it (see that folder's README).
///
/// Assumed model I/O (tweak the constants if your export differs):
///   input  : 1 x [_size] x [_size] x 3, float32 normalized to [0,1]
///   output : 1 x [_size] x [_size] x 1 alpha matte, float32 in [0,1]
class TfliteSegmenter {
  static const String _modelAsset = 'assets/models/cutout.tflite';
  static const int _size = 320; // model input/output side

  static Interpreter? _interpreter;
  static bool _triedLoad = false;
  static bool get isAvailable => _interpreter != null;

  /// Lazily load the model. Returns false if no model is bundled (or it fails
  /// to load) — callers then use the classical fallback. Never throws.
  static Future<bool> ensureLoaded() async {
    if (_interpreter != null) return true;
    if (_triedLoad) return false; // already failed once; don't retry every call
    _triedLoad = true;
    try {
      // Will throw if the asset isn't present; that's our "no model" signal.
      await rootBundle.load(_modelAsset);
      _interpreter = await Interpreter.fromAsset(_modelAsset);
      return true;
    } catch (_) {
      _interpreter = null;
      return false;
    }
  }

  /// Run segmentation on [image], returning a full-resolution alpha matte
  /// (Uint8List, 0..255, length = image.width*image.height). Returns null if
  /// the model isn't available — caller falls back to classical.
  static Future<Uint8List?> segment(img.Image image) async {
    if (!await ensureLoaded()) return null;
    final interp = _interpreter;
    if (interp == null) return null;

    try {
      final w = image.width, h = image.height;
      // 1. Resize to the model's square input.
      final resized = img.copyResize(image, width: _size, height: _size);

      // 2. Build the normalized input tensor [1, _size, _size, 3].
      final input = List.generate(
        1,
        (_) => List.generate(
          _size,
          (y) => List.generate(_size, (x) {
            final p = resized.getPixel(x, y);
            return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
          }),
        ),
      );

      // 3. Output buffer [1, _size, _size, 1].
      final output = List.generate(
        1,
        (_) => List.generate(
          _size,
          (_) => List.generate(_size, (_) => List.filled(1, 0.0)),
        ),
      );

      interp.run(input, output);

      // 4. Read the matte and upscale to full resolution (bilinear).
      final small = Uint8List(_size * _size);
      for (int y = 0; y < _size; y++) {
        for (int x = 0; x < _size; x++) {
          final v = output[0][y][x][0].clamp(0.0, 1.0);
          small[y * _size + x] = (v * 255).round();
        }
      }
      return _upscale(small, _size, _size, w, h);
    } catch (_) {
      // Any inference error -> let the caller fall back to classical.
      return null;
    }
  }

  static Uint8List _upscale(Uint8List a, int sw, int sh, int dw, int dh) {
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
}
