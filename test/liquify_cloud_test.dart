import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelvault/utils/liquify_ops.dart';
import 'package:pixelvault/utils/cloud_ai_service.dart';

void main() {
  test('liquify push displaces a vertical edge', () {
    const w = 40, h = 40;
    final im = img.Image(width: w, height: h, numChannels: 3);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        im.setPixelRgb(x, y, x < w ~/ 2 ? 0 : 255, 0, 0);
      }
    }
    // Push rightward at the centre.
    final out = LiquifyOps.warp(im, const [
      WarpStroke(x: 0.5, y: 0.5, radius: 0.4, dx: 0.2, dy: 0, mode: WarpMode.push),
    ]);
    // The edge near the centre row should have moved right: a pixel just past
    // the original midline that was white may now read from the dark side.
    // Assert the output differs from the input somewhere on the centre row.
    bool changed = false;
    for (int x = 0; x < w; x++) {
      if (out.getPixel(x, h ~/ 2).r.toInt() != im.getPixel(x, h ~/ 2).r.toInt()) {
        changed = true;
        break;
      }
    }
    expect(changed, isTrue, reason: 'push warp should alter the centre row');
  });

  test('empty strokes return the source unchanged', () {
    final im = img.Image(width: 10, height: 10, numChannels: 3);
    final out = LiquifyOps.warp(im, const []);
    expect(identical(out, im), isTrue);
  });

  test('disabled cloud AI is not configured and throws on run', () async {
    const svc = DisabledCloudAiService();
    expect(svc.isConfigured, isFalse);
    expect(
      () => svc.run(const CloudAiRequest(feature: CloudAiFeature.enhanceUpscale)),
      throwsA(isA<CloudAiUnavailable>()),
    );
  });
}
