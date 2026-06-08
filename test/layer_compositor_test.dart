import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelvault/models/layer.dart';
import 'package:pixelvault/utils/layer_compositor.dart';

img.Image _solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      im.setPixelRgba(x, y, r, g, b, a);
    }
  }
  return im;
}

void main() {
  const w = 8, h = 8;
  RasterLayer base(int r, int g, int b) =>
      RasterLayer(rgba: _solid(w, h, r, g, b));

  ({int r, int g, int b, int a}) px(img.Image im) {
    final p = im.getPixel(w ~/ 2, h ~/ 2);
    return (r: p.r.toInt(), g: p.g.toInt(), b: p.b.toInt(), a: p.a.toInt());
  }

  test('normal opaque top fully covers base', () {
    final out = LayerCompositor.composite(width: w, height: h, layers: [
      base(0, 0, 0),
      RasterLayer(rgba: _solid(w, h, 200, 100, 50)),
    ]);
    final c = px(out);
    expect(c.r, 200);
    expect(c.g, 100);
    expect(c.b, 50);
    expect(c.a, 255);
  });

  test('normal at 50% opacity blends halfway', () {
    final out = LayerCompositor.composite(width: w, height: h, layers: [
      base(0, 0, 0),
      RasterLayer(rgba: _solid(w, h, 200, 200, 200), opacity: 0.5),
    ]);
    final c = px(out);
    // (200*0.5 + 0*0.5) = 100, allow rounding.
    expect((c.r - 100).abs() <= 2, isTrue, reason: 'got ${c.r}');
  });

  test('multiply darkens', () {
    // 0.5 * 0.5 = 0.25 -> ~64
    final out = LayerCompositor.composite(width: w, height: h, layers: [
      base(128, 128, 128),
      RasterLayer(rgba: _solid(w, h, 128, 128, 128), blend: LayerBlend.multiply),
    ]);
    final c = px(out);
    expect(c.r < 128, isTrue, reason: 'multiply should darken, got ${c.r}');
    expect((c.r - 64).abs() <= 4, isTrue, reason: 'got ${c.r}');
  });

  test('screen lightens', () {
    // 1-(1-.5)(1-.5)=0.75 -> ~191
    final out = LayerCompositor.composite(width: w, height: h, layers: [
      base(128, 128, 128),
      RasterLayer(rgba: _solid(w, h, 128, 128, 128), blend: LayerBlend.screen),
    ]);
    final c = px(out);
    expect(c.r > 128, isTrue, reason: 'screen should lighten, got ${c.r}');
    expect((c.r - 191).abs() <= 4, isTrue, reason: 'got ${c.r}');
  });

  test('mask hides where 0, reveals where 255', () {
    final mask = Uint8List(w * h); // all 0 = fully hidden
    final out = LayerCompositor.composite(width: w, height: h, layers: [
      base(10, 20, 30),
      RasterLayer(rgba: _solid(w, h, 250, 250, 250), mask: mask),
    ]);
    final c = px(out);
    // Top layer fully masked out -> base shows through.
    expect(c.r, 10);
    expect(c.g, 20);
    expect(c.b, 30);
  });

  test('inverted mask flips hide/reveal', () {
    final mask = Uint8List(w * h); // all 0; inverted -> all reveal
    final out = LayerCompositor.composite(width: w, height: h, layers: [
      base(10, 20, 30),
      RasterLayer(
          rgba: _solid(w, h, 250, 250, 250), mask: mask, maskInverted: true),
    ]);
    final c = px(out);
    expect(c.r, 250); // now revealed
  });

  test('hidden layer is skipped', () {
    final out = LayerCompositor.composite(width: w, height: h, layers: [
      base(5, 5, 5),
      RasterLayer(rgba: _solid(w, h, 255, 0, 0), visible: false),
    ]);
    final c = px(out);
    expect(c.r, 5);
  });
}
