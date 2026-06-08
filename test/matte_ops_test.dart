import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelvault/utils/matte_ops.dart';
import 'package:pixelvault/utils/ai_service.dart';

void main() {
  const w = 20, h = 20;

  test('paintDab add raises alpha to ~255 at centre', () {
    final a = Uint8List(w * h); // all 0
    final out = MatteOps.paintDab(
        a, w, h, const MatteDab(x: 0.5, y: 0.5, radius: 0.25, add: true, softness: 0.0));
    expect(out[(h ~/ 2) * w + (w ~/ 2)], 255);
    expect(out[0], 0); // corner untouched
  });

  test('paintDab erase lowers alpha to 0 at centre', () {
    final a = Uint8List(w * h)..fillRange(0, w * h, 255);
    final out = MatteOps.paintDab(
        a, w, h, const MatteDab(x: 0.5, y: 0.5, radius: 0.25, add: false, softness: 0.0));
    expect(out[(h ~/ 2) * w + (w ~/ 2)], 0);
    expect(out[0], 255); // corner untouched
  });

  test('feather softens a hard edge (produces mid values)', () {
    final a = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        a[y * w + x] = x < w ~/ 2 ? 0 : 255; // hard vertical edge
      }
    }
    final out = MatteOps.feather(a, w, h, radius: 2);
    // Near the edge there should now be a partial value.
    bool foundMid = false;
    for (int x = 0; x < w; x++) {
      final v = out[(h ~/ 2) * w + x];
      if (v > 20 && v < 235) foundMid = true;
    }
    expect(foundMid, isTrue, reason: 'feather should create soft edge pixels');
  });

  test('shiftEdge grow keeps subject, shrink reduces it', () {
    final a = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // central square subject
        final inside = x > 6 && x < 13 && y > 6 && y < 13;
        a[y * w + x] = inside ? 255 : 0;
      }
    }
    int count(Uint8List m) => m.where((v) => v > 127).length;
    final base = count(a);
    final grown = count(MatteOps.shiftEdge(a, w, h, 0.5));
    final shrunk = count(MatteOps.shiftEdge(a, w, h, -0.5));
    // grow >= base (threshold lowered), shrink <= base.
    expect(grown >= base, isTrue, reason: 'grown=$grown base=$base');
    expect(shrunk <= base, isTrue, reason: 'shrunk=$shrunk base=$base');
  });

  test('overSolid puts background colour where alpha=0, photo where alpha=255', () {
    final photo = img.Image(width: w, height: h, numChannels: 3);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        photo.setPixelRgb(x, y, 200, 50, 50);
      }
    }
    final a = Uint8List(w * h);
    a[(h ~/ 2) * w + (w ~/ 2)] = 255; // one subject pixel
    final out = MatteOps.overSolid(photo, a, w, h, 0, 0, 255);
    final bgPx = out.getPixel(0, 0);
    expect(bgPx.b.toInt(), 255); // background blue
    expect(bgPx.r.toInt(), 0);
    final subPx = out.getPixel(w ~/ 2, h ~/ 2);
    expect(subPx.r.toInt(), 200); // photo subject preserved
  });

  test('replaceBackground (solid) decodes and applies', () async {
    final photo = img.Image(width: w, height: h, numChannels: 3);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        photo.setPixelRgb(x, y, 10, 220, 10);
      }
    }
    final bytes = Uint8List.fromList(img.encodePng(photo));
    final alpha = Uint8List(w * h); // all background
    final out = await replaceBackground(BgReplaceRequest(
      photoBytes: bytes,
      matte: CutoutResult(alpha: alpha, width: w, height: h),
      kind: BgKind.solid,
      color: const [255, 0, 0],
      asPng: true,
    ));
    final decoded = img.decodePng(out)!;
    final p = decoded.getPixel(0, 0);
    expect(p.r.toInt(), 255); // fully background -> red
    expect(p.g.toInt(), 0);
  });
}
