import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import '../models/layer.dart';

/// Phase 6.6 / 6.3 / 6.4 — CPU-based, isolate-safe layer compositor.
///
/// Composites a stack of pre-rasterized image layers over a base image,
/// honoring each layer's blend mode (6.3), opacity, visibility, and optional
/// per-layer alpha mask with invert (6.4). Bottom-to-top order matches
/// [LayerStack] (index 0 = bottom).
///
/// Why CPU/`image` and not dart:ui Canvas: this path runs on a background
/// isolate (no Flutter engine) and is fully headless-testable. The on-screen
/// editor still uses the GPU Canvas path (OverlayCompositor) for live overlays;
/// this is the deterministic save/export math for blended layers.
///
/// Each compositable layer must carry its already-rasterized RGBA pixels in
/// [RasterLayer]; turning a text/sticker/draw layer into pixels happens in the
/// migration step (6.5) via the existing Canvas renderer.
class RasterLayer {
  final img.Image rgba; // same dimensions as the canvas
  final bool visible;
  final double opacity; // 0..1
  final LayerBlend blend;
  final Uint8List? mask; // canvas-sized, 0..255, nullable
  final bool maskInverted;

  const RasterLayer({
    required this.rgba,
    this.visible = true,
    this.opacity = 1.0,
    this.blend = LayerBlend.normal,
    this.mask,
    this.maskInverted = false,
  });
}

class LayerCompositor {
  /// Composite [layers] (bottom-to-top) onto a canvas of [width]x[height].
  /// Layer 0 is treated as the base (drawn opaque first). Returns RGB pixels.
  static img.Image composite({
    required int width,
    required int height,
    required List<RasterLayer> layers,
  }) {
    // Start from transparent; the base layer fills it.
    final out = img.Image(width: width, height: height, numChannels: 4);
    for (final layer in layers) {
      if (!layer.visible || layer.opacity <= 0) continue;
      _blendOnto(out, layer, width, height);
    }
    return out;
  }

  /// Convenience: encode the composite to PNG (preserves transparency) or JPEG.
  static Future<Uint8List> compositeEncoded({
    required int width,
    required int height,
    required List<RasterLayer> layers,
    bool asPng = true,
    int jpegQuality = 95,
  }) {
    return compute(
      _encodeJob,
      _CompositeJob(
        width: width,
        height: height,
        layers: layers,
        asPng: asPng,
        jpegQuality: jpegQuality,
      ),
    );
  }

  static void _blendOnto(img.Image out, RasterLayer layer, int w, int h) {
    final src = layer.rgba;
    final mask = layer.mask;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final sp = src.getPixel(x, y);
        // Effective source alpha = pixel alpha * layer opacity * mask.
        double a = (sp.a / 255.0) * layer.opacity;
        if (mask != null) {
          var m = mask[y * w + x] / 255.0;
          if (layer.maskInverted) m = 1.0 - m;
          a *= m;
        }
        if (a <= 0) continue;

        final dp = out.getPixel(x, y);
        final da = dp.a / 255.0;

        // Blend the colour channels per the blend mode, then alpha-composite
        // (source-over) using the effective source alpha.
        final br = _blendChannel(layer.blend, sp.r / 255.0, dp.r / 255.0);
        final bg = _blendChannel(layer.blend, sp.g / 255.0, dp.g / 255.0);
        final bb = _blendChannel(layer.blend, sp.b / 255.0, dp.b / 255.0);

        // Where the destination is transparent, a blend mode has nothing to
        // blend with, so fall back toward the raw source colour.
        final mixR = br * da + (sp.r / 255.0) * (1 - da);
        final mixG = bg * da + (sp.g / 255.0) * (1 - da);
        final mixB = bb * da + (sp.b / 255.0) * (1 - da);

        final outA = a + da * (1 - a);
        if (outA <= 0) continue;
        final or = (mixR * a + (dp.r / 255.0) * da * (1 - a)) / outA;
        final og = (mixG * a + (dp.g / 255.0) * da * (1 - a)) / outA;
        final ob = (mixB * a + (dp.b / 255.0) * da * (1 - a)) / outA;

        out.setPixelRgba(
          x,
          y,
          (or * 255).round().clamp(0, 255),
          (og * 255).round().clamp(0, 255),
          (ob * 255).round().clamp(0, 255),
          (outA * 255).round().clamp(0, 255),
        );
      }
    }
  }

  /// Per-channel blend math (s = source, d = destination), all 0..1.
  static double _blendChannel(LayerBlend mode, double s, double d) {
    switch (mode) {
      case LayerBlend.normal:
        return s;
      case LayerBlend.multiply:
        return s * d;
      case LayerBlend.screen:
        return 1 - (1 - s) * (1 - d);
      case LayerBlend.overlay:
        return d < 0.5 ? 2 * s * d : 1 - 2 * (1 - s) * (1 - d);
      case LayerBlend.hardLight:
        return s < 0.5 ? 2 * s * d : 1 - 2 * (1 - s) * (1 - d);
      case LayerBlend.softLight:
        // Pegtop soft-light approximation.
        return (1 - 2 * s) * d * d + 2 * s * d;
      case LayerBlend.darken:
        return math.min(s, d);
      case LayerBlend.lighten:
        return math.max(s, d);
      case LayerBlend.add:
        return math.min(1.0, s + d);
      case LayerBlend.difference:
        return (s - d).abs();
    }
  }
}

class _CompositeJob {
  final int width, height, jpegQuality;
  final List<RasterLayer> layers;
  final bool asPng;
  const _CompositeJob({
    required this.width,
    required this.height,
    required this.layers,
    required this.asPng,
    required this.jpegQuality,
  });
}

Future<Uint8List> _encodeJob(_CompositeJob job) async {
  final composite = LayerCompositor.composite(
    width: job.width,
    height: job.height,
    layers: job.layers,
  );
  if (job.asPng) return img.encodePng(composite);
  // JPEG has no alpha: flatten onto black before encoding.
  final flat = img.Image(width: job.width, height: job.height, numChannels: 3);
  for (int y = 0; y < job.height; y++) {
    for (int x = 0; x < job.width; x++) {
      final p = composite.getPixel(x, y);
      final a = p.a / 255.0;
      flat.setPixelRgb(
        x,
        y,
        (p.r * a).round(),
        (p.g * a).round(),
        (p.b * a).round(),
      );
    }
  }
  return img.encodeJpg(flat, quality: job.jpegQuality);
}
