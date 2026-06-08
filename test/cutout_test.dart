import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelvault/utils/ai_service.dart';

/// Build a synthetic photo: a solid red subject ellipse centred on a solid
/// blue background. Segmentation should mark the centre as subject (alpha high)
/// and the corners as background (alpha low).
Uint8List _syntheticSubjectOnBackground(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  final cx = w / 2, cy = h / 2;
  final rx = w * 0.28, ry = h * 0.36;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final dx = (x - cx) / rx, dy = (y - cy) / ry;
      final inside = dx * dx + dy * dy <= 1.0;
      if (inside) {
        im.setPixelRgb(x, y, 220, 40, 40); // red subject
      } else {
        im.setPixelRgb(x, y, 30, 60, 200); // blue background
      }
    }
  }
  return img.encodePng(im);
}

void main() {
  test('cutout matte marks centred subject and clears corners', () async {
    const w = 400, h = 500;
    final bytes = _syntheticSubjectOnBackground(w, h);

    final matte = await const AiService().removeBackground(bytes);

    expect(matte.width, w);
    expect(matte.height, h);
    expect(matte.alpha.length, w * h);

    int at(int x, int y) => matte.alpha[y * w + x];

    // Centre of the subject should be opaque.
    expect(at(w ~/ 2, h ~/ 2), greaterThan(200),
        reason: 'subject centre should be kept (alpha high)');

    // All four corners are background -> should be transparent.
    expect(at(2, 2), lessThan(40), reason: 'top-left corner is background');
    expect(at(w - 3, 2), lessThan(40), reason: 'top-right corner is background');
    expect(at(2, h - 3), lessThan(40), reason: 'bottom-left corner is background');
    expect(at(w - 3, h - 3), lessThan(40),
        reason: 'bottom-right corner is background');
  });

  test('on-device cutout reports no network requirement', () {
    expect(const AiService().needsNetwork(AiCapabilityKind.backgroundRemoval),
        isFalse);
  });
}
