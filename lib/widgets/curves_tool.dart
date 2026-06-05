import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor_provider.dart';
import '../models/edit_settings.dart';
import '../theme/app_theme.dart';

/// Tone curve editor. Five control points along the input axis; drag any point
/// up/down to brighten/darken that tonal range. The curve maps input level (x)
/// to output level (y), both 0..1. Applied to the RGB master channel.
class CurvesToolPanel extends ConsumerStatefulWidget {
  const CurvesToolPanel({super.key});
  @override
  ConsumerState<CurvesToolPanel> createState() => _CurvesToolPanelState();
}

class _CurvesToolPanelState extends ConsumerState<CurvesToolPanel> {
  static const int _n = 5; // control points

  List<CurvePoint> get _identity =>
      List.generate(_n, (i) => CurvePoint(i / (_n - 1), i / (_n - 1)));

  List<CurvePoint> _current() {
    final c = ref.read(editorProvider).current.curve;
    if (c.length == _n) return [...c];
    return _identity;
  }

  int? _dragIndex;

  @override
  Widget build(BuildContext context) {
    final n = ref.read(editorProvider.notifier);
    final pts = _current();

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Tone curve · drag points up/down',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
              const Spacer(),
              GestureDetector(
                onTap: () => n.resetCurve(),
                child: const Text('Reset',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: LayoutBuilder(builder: (ctx, _) {
              const side = 220.0;
              return GestureDetector(
                onPanStart: (d) => _onStart(d.localPosition, side, pts),
                onPanUpdate: (d) => _onUpdate(d.localPosition, side, pts, n),
                onPanEnd: (_) {
                  _dragIndex = null;
                  n.commitHistory();
                },
                child: CustomPaint(
                  size: const Size(side, side),
                  painter: _CurvePainter(pts),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  void _onStart(Offset p, double side, List<CurvePoint> pts) {
    // Find nearest point by x.
    double best = 1e9;
    for (int i = 0; i < pts.length; i++) {
      final px = pts[i].x * side;
      final py = (1 - pts[i].y) * side;
      final d = (Offset(px, py) - p).distance;
      if (d < best) { best = d; _dragIndex = i; }
    }
    if (best > 44) _dragIndex = null;
  }

  void _onUpdate(Offset p, double side, List<CurvePoint> pts, EditorNotifier n) {
    final i = _dragIndex;
    if (i == null) return;
    // y is draggable; x stays fixed for endpoints, limited move for middle.
    final newY = (1 - (p.dy / side)).clamp(0.0, 1.0);
    final updated = [...pts];
    updated[i] = CurvePoint(pts[i].x, newY);
    n.setCurveLive(updated);
  }
}

class _CurvePainter extends CustomPainter {
  final List<CurvePoint> pts;
  _CurvePainter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white.withOpacity(0.04);
    canvas.drawRect(Offset.zero & size, bg);

    // Grid
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final d = size.width * i / 4;
      canvas.drawLine(Offset(d, 0), Offset(d, size.height), grid);
      canvas.drawLine(Offset(0, d), Offset(size.width, d), grid);
    }

    // Curve line
    final line = Paint()
      ..color = AppTheme.primaryLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final x = pts[i].x * size.width;
      final y = (1 - pts[i].y) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);

    // Control points
    for (final p in pts) {
      final c = Offset(p.x * size.width, (1 - p.y) * size.height);
      canvas.drawCircle(c, 6, Paint()..color = Colors.white);
      canvas.drawCircle(c, 6, Paint()
        ..color = AppTheme.primaryLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.pts != pts;
}
