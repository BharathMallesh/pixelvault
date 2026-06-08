import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelvault/models/edit_settings.dart';
import 'package:pixelvault/utils/image_processor.dart';

Uint8List _gray(int w, int h, int v) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  test('white frame fills the border, leaves centre untouched', () async {
    final bytes = _gray(200, 200, 60);
    final out = await ImageProcessor.processBytes(
      inputBytes: bytes,
      settings: const EditSettings(frameStyle: 'white', frameWidth: 40),
      asPng: true,
    );
    final im = img.decodePng(out)!;
    final corner = im.getPixel(1, 1);
    expect(corner.r.toInt(), greaterThan(240), reason: 'border should be white');
    final centre = im.getPixel(100, 100);
    expect(centre.r.toInt(), 60, reason: 'centre photo untouched');
  });

  test('black frame fills the border black', () async {
    final bytes = _gray(160, 160, 200);
    final out = await ImageProcessor.processBytes(
      inputBytes: bytes,
      settings: const EditSettings(frameStyle: 'black', frameWidth: 50),
      asPng: true,
    );
    final im = img.decodePng(out)!;
    expect(im.getPixel(1, 1).r.toInt(), lessThan(15));
  });

  test('warm light leak brightens toward the top-right corner', () async {
    final bytes = _gray(200, 200, 80);
    final out = await ImageProcessor.processBytes(
      inputBytes: bytes,
      settings: const EditSettings(overlayEffect: 'leak_warm', overlayStrength: 100),
      asPng: true,
    );
    final im = img.decodePng(out)!;
    // Top-right should be brighter/warmer than bottom-left.
    final tr = im.getPixel(190, 10);
    final bl = im.getPixel(10, 190);
    expect(tr.r.toInt(), greaterThan(bl.r.toInt()),
        reason: 'warm leak originates top-right');
    expect(tr.r.toInt(), greaterThan(80), reason: 'leak should brighten');
  });

  test('no frame / no overlay leaves the image unchanged', () async {
    final bytes = _gray(64, 64, 123);
    final out = await ImageProcessor.processBytes(
      inputBytes: bytes,
      settings: const EditSettings(),
      asPng: true,
    );
    final im = img.decodePng(out)!;
    expect(im.getPixel(1, 1).r.toInt(), 123);
    expect(im.getPixel(32, 32).r.toInt(), 123);
  });
}
