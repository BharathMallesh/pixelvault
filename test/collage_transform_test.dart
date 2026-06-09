import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelvault/utils/image_processor.dart';

// Left half red, right half blue.
Uint8List _leftRedRightBlue(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      im.setPixelRgb(x, y, x < w ~/ 2 ? 255 : 0, 0, x < w ~/ 2 ? 0 : 255);
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  test('zoom 1 contains the whole photo (both halves visible)', () {
    final bytes = _leftRedRightBlue(200, 200);
    final out = ImageProcessor.composeCollage(
      cells: [CollageCell(left: 0, top: 0, right: 1, bottom: 1, bytes: bytes)],
      canvasSize: 200, borderWidth: 0, borderR: 0, borderG: 0, borderB: 0,
      asPng: true,
    );
    final im = img.decodePng(out)!;
    expect(im.getPixel(50, 100).r.toInt() > im.getPixel(50, 100).b.toInt(), isTrue);
    expect(im.getPixel(150, 100).b.toInt() > im.getPixel(150, 100).r.toInt(), isTrue);
  });

  test('panX=-1 reveals left (red), panX=+1 reveals right (blue) when zoomed', () {
    final bytes = _leftRedRightBlue(200, 200);
    Uint8List render(double panX) => ImageProcessor.composeCollage(
          cells: [
            CollageCell(
                left: 0, top: 0, right: 1, bottom: 1,
                bytes: bytes, zoom: 2.0, panX: panX, panY: 0),
          ],
          canvasSize: 200, borderWidth: 0, borderR: 0, borderG: 0, borderB: 0,
          asPng: true,
        );
    final left = img.decodePng(render(-1.0))!;
    final right = img.decodePng(render(1.0))!;
    expect(left.getPixel(100, 100).r.toInt() > left.getPixel(100, 100).b.toInt(),
        isTrue, reason: 'pan left -> red');
    expect(right.getPixel(100, 100).b.toInt() > right.getPixel(100, 100).r.toInt(),
        isTrue, reason: 'pan right -> blue');
  });

  test('wide photo in square cell at zoom 1 is letterboxed with border', () {
    final bytes = _leftRedRightBlue(400, 200);
    final out = ImageProcessor.composeCollage(
      cells: [CollageCell(left: 0, top: 0, right: 1, bottom: 1, bytes: bytes)],
      canvasSize: 200, borderWidth: 0, borderR: 10, borderG: 20, borderB: 30,
      asPng: true,
    );
    final im = img.decodePng(out)!;
    final top = im.getPixel(100, 2);
    expect(top.r.toInt() == 10 && top.g.toInt() == 20 && top.b.toInt() == 30,
        isTrue, reason: 'letterbox border at top');
  });
}
