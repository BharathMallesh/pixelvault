import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor_provider.dart';
import '../widgets/adjustment_slider.dart';
import '../theme/app_theme.dart';

class PerspectiveToolPanel extends ConsumerWidget {
  const PerspectiveToolPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final s = state.current;

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Visual grid icon hint
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PerspectivePreview(
                vertical: s.perspectiveVertical / 100,
                horizontal: s.perspectiveHorizontal / 100,
              ),
            ),
          ),

          AdjustmentSlider(
            label: 'Vertical',
            value: s.perspectiveVertical,
            onChanged: n.setPerspectiveVertical,
          ),
          AdjustmentSlider(
            label: 'Horizontal',
            value: s.perspectiveHorizontal,
            onChanged: n.setPerspectiveHorizontal,
          ),

          const SizedBox(height: 10),
          const Text(
            'Use Vertical to fix tilted buildings. Use Horizontal to fix wide-angle distortion.',
            style: TextStyle(fontSize: 11, color: Colors.white24),
            textAlign: TextAlign.center,
          ),

          if (s.perspectiveVertical != 0 || s.perspectiveHorizontal != 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: GestureDetector(
                onTap: () {
                  n.setPerspectiveVertical(0);
                  n.setPerspectiveHorizontal(0);
                },
                child: const Center(
                  child: Text('Reset perspective',
                      style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PerspectivePreview extends StatelessWidget {
  final double vertical;
  final double horizontal;
  const _PerspectivePreview({required this.vertical, required this.horizontal});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(80, 60),
      painter: _PerspPainter(v: vertical, h: horizontal),
    );
  }
}

class _PerspPainter extends CustomPainter {
  final double v; // -1 to 1
  final double h;
  _PerspPainter({required this.v, required this.h});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primaryLight.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final W = size.width;
    final H = size.height;
    final vShift = v * H * 0.3; // top compression
    final hShift = h * W * 0.3;

    // Draw a trapezoid representing the perspective correction
    final path = Path()
      ..moveTo(hShift.abs(), vShift.abs())
      ..lineTo(W - hShift.abs(), vShift.abs())
      ..lineTo(W - hShift.abs() + hShift * 0.5, H - vShift.abs())
      ..lineTo(hShift.abs() - hShift * 0.5, H - vShift.abs())
      ..close();

    canvas.drawPath(path, paint);

    // Grid lines inside
    final gridPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.5;
    for (int i = 1; i < 3; i++) {
      final t = i / 3;
      final topX1 = hShift.abs() + (W - 2 * hShift.abs()) * t;
      final botX1 = hShift.abs() - hShift * 0.5 +
          (W - 2 * (hShift.abs() - hShift * 0.5)) * t;
      canvas.drawLine(
          Offset(topX1, vShift.abs()), Offset(botX1, H - vShift.abs()), gridPaint);
    }
    for (int i = 1; i < 3; i++) {
      final t = i / 3;
      canvas.drawLine(
        Offset(
          hShift.abs() + (W * t - hShift.abs()) * 0.3,
          vShift.abs() + (H - 2 * vShift.abs()) * t,
        ),
        Offset(
          W - hShift.abs() - (W * (1 - t) - hShift.abs()) * 0.3,
          vShift.abs() + (H - 2 * vShift.abs()) * t,
        ),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PerspPainter old) => old.v != v || old.h != h;
}
