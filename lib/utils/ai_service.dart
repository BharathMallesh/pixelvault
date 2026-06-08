import 'dart:typed_data';
import 'cutout_engine.dart';

/// Abstraction over "AI" capabilities. The hybrid design keeps the app
/// offline-by-default; every capability declares whether it touches the
/// network, so the UI can gate cloud features behind the user's opt-in toggle
/// and keep on-device features always available.
///
/// Phase 1 ships a single on-device capability (background removal / subject
/// cutout). Future cloud capabilities (upscale, generative fill) implement the
/// same interface with [needsNetwork] == true and live behind the opt-in flag.
enum AiCapabilityKind { backgroundRemoval }

/// Result of a cutout: a soft alpha matte (0..255), one byte per pixel, at
/// [width] x [height]. The editor composites this into a transparent PNG or
/// uses it as a focus mask for background blur.
class CutoutResult {
  final Uint8List alpha; // width*height, 0 = background, 255 = subject
  final int width;
  final int height;
  const CutoutResult({
    required this.alpha,
    required this.width,
    required this.height,
  });
}

/// Single entry point the UI talks to. Today it dispatches to the on-device
/// [CutoutEngine]. The seam is deliberately narrow so a TFLite-backed
/// implementation can be dropped in without touching callers.
class AiService {
  const AiService();

  /// Whether a given capability requires network access. On-device features
  /// return false and run even when AI cloud features are not opted in.
  bool needsNetwork(AiCapabilityKind kind) {
    switch (kind) {
      case AiCapabilityKind.backgroundRemoval:
        return false; // runs fully on-device
    }
  }

  /// Produce a subject/background alpha matte for [imageBytes], entirely on
  /// device. Runs the segmentation off the UI thread (see [CutoutEngine]).
  ///
  /// [hintRect] (normalized 0..1 left,top,right,bottom) optionally tells the
  /// engine roughly where the subject is, improving results. When null the
  /// engine assumes a centered subject.
  Future<CutoutResult> removeBackground(
    Uint8List imageBytes, {
    List<double>? hintRect,
  }) {
    return CutoutEngine.segment(imageBytes, hintRect: hintRect);
  }
}
