import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelvault/utils/face_detector.dart';
import 'package:pixelvault/utils/beauty_ops.dart';

/// Skin-coloured ellipse (a stand-in face) on a green background, with some
/// per-pixel noise inside the face so smoothing has something to reduce.
img.Image _syntheticFace(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  final cx = w / 2, cy = h / 2, rx = w * 0.30, ry = h * 0.38;
  final rng = math.Random(7);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final dx = (x - cx) / rx, dy = (y - cy) / ry;
      if (dx * dx + dy * dy <= 1.0) {
        // skin tone ~ (230,180,150) + noise
        final n = rng.nextInt(40) - 20;
        im.setPixelRgb(x, y, (230 + n).clamp(0, 255), (180 + n).clamp(0, 255),
            (150 + n).clamp(0, 255));
      } else {
        im.setPixelRgb(x, y, 30, 160, 40); // green bg (not skin)
      }
    }
  }
  return im;
}

double _localVariance(img.Image im, int cx, int cy, int r) {
  double sum = 0, sum2 = 0;
  int c = 0;
  for (int y = cy - r; y <= cy + r; y++) {
    for (int x = cx - r; x <= cx + r; x++) {
      final p = im.getPixel(x, y);
      final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      sum += l;
      sum2 += l * l;
      c++;
    }
  }
  final mean = sum / c;
  return sum2 / c - mean * mean;
}

void main() {
  const w = 200, h = 240;

  test('detector finds the skin-coloured face region', () async {
    final bytes = Uint8List.fromList(img.encodePng(_syntheticFace(w, h)));
    final face = await const FaceDetector().detect(bytes);
    expect(face, isNotNull);
    expect(face!.isValid, isTrue);
    // Face centre should be near image centre.
    expect((face.cx - 0.5).abs() < 0.15, isTrue, reason: 'cx=${face.cx}');
    expect((face.cy - 0.5).abs() < 0.15, isTrue, reason: 'cy=${face.cy}');
  });

  test('detector returns null when there is no skin', () async {
    final im = img.Image(width: 60, height: 60, numChannels: 3);
    for (int y = 0; y < 60; y++) {
      for (int x = 0; x < 60; x++) {
        im.setPixelRgb(x, y, 20, 120, 220); // all blue
      }
    }
    final bytes = Uint8List.fromList(img.encodePng(im));
    final face = await const FaceDetector().detect(bytes);
    expect(face, isNull);
  });

  test('skin smooth reduces local variance inside the face', () async {
    final src = _syntheticFace(w, h);
    final bytes = Uint8List.fromList(img.encodePng(src));
    final face = await const FaceDetector().detect(bytes);
    expect(face, isNotNull);
    final before = _localVariance(src, w ~/ 2, h ~/ 2, 6);
    final smoothed = BeautyOps.skinSmooth(src, face!, 0.9, radius: 3);
    final after = _localVariance(smoothed, w ~/ 2, h ~/ 2, 6);
    expect(after < before, isTrue, reason: 'before=$before after=$after');
  });

  test('eye brighten increases luminance in the eye band', () async {
    final src = _syntheticFace(w, h);
    final bytes = Uint8List.fromList(img.encodePng(src));
    final face = await const FaceDetector().detect(bytes);
    final e = face!.eyeBand;
    final ex = ((e.l + e.r) / 2 * w).round();
    final ey = ((e.t + e.b) / 2 * h).round();
    double lum(img.Image im) {
      final p = im.getPixel(ex, ey);
      return 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    }
    final before = lum(src);
    final out = BeautyOps.eyeBrighten(src, face, 1.0);
    expect(lum(out) >= before, isTrue);
  });

  test('zero amounts leave the image unchanged', () async {
    final src = _syntheticFace(40, 40);
    final bytes = Uint8List.fromList(img.encodePng(src));
    final face = await const FaceDetector().detect(bytes);
    final out = BeautyOps.applyAll(src, face!, smooth: 0, teeth: 0, eyes: 0);
    // Same object back (applyAll returns src when nothing enabled).
    expect(identical(out, src), isTrue);
  });
}
