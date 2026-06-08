import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/matte_provider.dart';
import '../utils/matte_ops.dart';
import '../theme/app_theme.dart';
import 'crop_overlay.dart' show editorImageAspectProvider;

/// Phase 7.1 — brush overlay for refining the cutout matte. Painting adds
/// (subject) or erases (background) dabs into [matteEditProvider]. Only shown
/// when the Cutout tool is active and a matte has been detected.
///
/// Coordinates are mapped to the photo's BoxFit.contain rect so dabs land on
/// the right part of the image regardless of letterboxing.
class CutoutRefineOverlay extends ConsumerWidget {
  final Size canvasSize;
  const CutoutRefineOverlay({super.key, required this.canvasSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(matteEditProvider);
    if (!m.hasMatte) return const SizedBox.shrink();
    final mn = ref.read(matteEditProvider.notifier);
    final aspect = ref.watch(editorImageAspectProvider);
    final rect = _photoRect(canvasSize, aspect);

    void paintAt(Offset pos) {
      if (!rect.contains(pos)) return;
      final nx = ((pos.dx - rect.left) / rect.width).clamp(0.0, 1.0);
      final ny = ((pos.dy - rect.top) / rect.height).clamp(0.0, 1.0);
      mn.addDab(MatteDab(
        x: nx,
        y: ny,
        radius: m.brushRadius,
        add: m.brushAdd,
        softness: 0.5,
      ));
    }

    return GestureDetector(
      onPanUpdate: (d) => paintAt(d.localPosition),
      onPanDown: (d) => paintAt(d.localPosition),
      child: CustomPaint(
        size: Size.infinite,
        painter: _RefinePainter(rect: rect, dabs: m.dabs),
      ),
    );
  }

  /// The on-screen rect the photo occupies under BoxFit.contain.
  Rect _photoRect(Size canvas, double? aspect) {
    if (aspect == null || aspect <= 0) return Offset.zero & canvas;
    final canvasAspect = canvas.width / canvas.height;
    double w, h;
    if (aspect > canvasAspect) {
      w = canvas.width;
      h = w / aspect;
    } else {
      h = canvas.height;
      w = h * aspect;
    }
    final left = (canvas.width - w) / 2;
    final top = (canvas.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }
}

class _RefinePainter extends CustomPainter {
  final Rect rect;
  final List<MatteDab> dabs;
  _RefinePainter({required this.rect, required this.dabs});

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in dabs) {
      final c = Offset(rect.left + d.x * rect.width, rect.top + d.y * rect.height);
      final r = d.radius * (rect.width > rect.height ? rect.width : rect.height);
      final fill = Paint()
        ..color = (d.add ? AppTheme.primary : Colors.redAccent)
            .withValues(alpha: 0.30);
      canvas.drawCircle(c, r, fill);
    }
  }

  @override
  bool shouldRepaint(_RefinePainter old) => old.dabs.length != dabs.length;
}
