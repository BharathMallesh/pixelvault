import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/draw_stroke.dart';
import '../theme/app_theme.dart';

final drawStrokesProvider = StateProvider<List<DrawStroke>>((ref) => []);
final activeDrawStrokeProvider = StateProvider<DrawStroke?>((ref) => null);
final drawColorProvider = StateProvider<Color>((ref) => Colors.white);
final drawWidthProvider = StateProvider<double>((ref) => 5.0);
final isEraserProvider = StateProvider<bool>((ref) => false);

class DrawCanvas extends ConsumerWidget {
  final Size canvasSize;
  const DrawCanvas({super.key, required this.canvasSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strokes = ref.watch(drawStrokesProvider);
    final active = ref.watch(activeDrawStrokeProvider);
    final color = ref.watch(drawColorProvider);
    final width = ref.watch(drawWidthProvider);
    final isEraser = ref.watch(isEraserProvider);

    return GestureDetector(
      onPanStart: (d) {
        final p = DrawPoint(
            d.localPosition.dx / canvasSize.width,
            d.localPosition.dy / canvasSize.height);
        final stroke = DrawStroke(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          points: [p],
          color: isEraser ? Colors.transparent : color,
          width: width,
          isEraser: isEraser,
        );
        ref.read(activeDrawStrokeProvider.notifier).state = stroke;
      },
      onPanUpdate: (d) {
        final cur = ref.read(activeDrawStrokeProvider);
        if (cur == null) return;
        final p = DrawPoint(
            d.localPosition.dx / canvasSize.width,
            d.localPosition.dy / canvasSize.height);
        ref.read(activeDrawStrokeProvider.notifier).state =
            cur.copyWith(points: [...cur.points, p]);
      },
      onPanEnd: (_) {
        final cur = ref.read(activeDrawStrokeProvider);
        if (cur != null && cur.points.isNotEmpty) {
          ref.read(drawStrokesProvider.notifier).state = [
            ...ref.read(drawStrokesProvider), cur
          ];
        }
        ref.read(activeDrawStrokeProvider.notifier).state = null;
      },
      child: CustomPaint(
        painter: _DrawPainter(
            strokes: strokes, activeStroke: active, size: canvasSize),
        size: canvasSize,
      ),
    );
  }
}

class _DrawPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final DrawStroke? activeStroke;
  final Size size;
  _DrawPainter({required this.strokes, this.activeStroke, required this.size});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in [...strokes, if (activeStroke != null) activeStroke!]) {
      _paintStroke(canvas, stroke, size);
    }
  }

  void _paintStroke(Canvas canvas, DrawStroke stroke, Size size) {
    if (stroke.points.length < 2) return;
    final paint = Paint()
      ..color = stroke.isEraser ? Colors.transparent : stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;

    final path = Path()
      ..moveTo(stroke.points[0].x * size.width, stroke.points[0].y * size.height);
    for (int i = 1; i < stroke.points.length - 1; i++) {
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];
      path.quadraticBezierTo(
        p1.x * size.width, p1.y * size.height,
        (p1.x + p2.x) / 2 * size.width,
        (p1.y + p2.y) / 2 * size.height,
      );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DrawPainter old) =>
      old.strokes.length != strokes.length || old.activeStroke != activeStroke;
}

// ── Draw Tool Panel ────────────────────────────────────────────────

class DrawToolPanel extends ConsumerWidget {
  const DrawToolPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = ref.watch(drawColorProvider);
    final width = ref.watch(drawWidthProvider);
    final isEraser = ref.watch(isEraserProvider);
    final strokes = ref.watch(drawStrokesProvider);

    final presetColors = [
      Colors.white, Colors.black, Colors.red, Colors.orange,
      Colors.yellow, Colors.green, Colors.blue, Colors.purple, Colors.pink,
    ];

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Top row: color + eraser + clear
          Row(
            children: [
              // Color swatches
              ...presetColors.map((c) => GestureDetector(
                    onTap: () {
                      ref.read(drawColorProvider.notifier).state = c;
                      ref.read(isEraserProvider.notifier).state = false;
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.only(right: 5),
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: !isEraser && c == color
                              ? Colors.white : Colors.white24,
                          width: !isEraser && c == color ? 2.0 : 1.0,
                        ),
                      ),
                    ),
                  )),

              // Custom color picker
              GestureDetector(
                onTap: () => _pickColor(context, ref, color),
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38),
                    gradient: const SweepGradient(colors: [
                      Colors.red, Colors.orange, Colors.yellow,
                      Colors.green, Colors.blue, Colors.purple, Colors.red,
                    ]),
                  ),
                ),
              ),
              const Spacer(),

              // Eraser
              GestureDetector(
                onTap: () => ref.read(isEraserProvider.notifier).state = !isEraser,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isEraser ? AppTheme.toolbarSelected : Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(children: [
                    Icon(Icons.auto_fix_off_outlined,
                        size: 14, color: isEraser ? Colors.white : Colors.white54),
                    const SizedBox(width: 4),
                    Text('Erase',
                        style: TextStyle(
                            fontSize: 11,
                            color: isEraser ? Colors.white : Colors.white54)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),

              // Undo last stroke
              if (strokes.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    final list = ref.read(drawStrokesProvider);
                    if (list.isNotEmpty) {
                      ref.read(drawStrokesProvider.notifier).state =
                          list.sublist(0, list.length - 1);
                    }
                  },
                  child: const Icon(Icons.undo, size: 18, color: Colors.white54),
                ),
              const SizedBox(width: 8),

              // Clear all
              if (strokes.isNotEmpty)
                GestureDetector(
                  onTap: () => ref.read(drawStrokesProvider.notifier).state = [],
                  child: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Brush size slider
          Row(
            children: [
              const SizedBox(width: 70,
                  child: Text('Brush', style: TextStyle(fontSize: 12, color: Colors.white60))),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2, thumbRadius: 8,
                    activeTrackColor: color,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: width, min: 1, max: 30,
                    onChanged: (v) => ref.read(drawWidthProvider.notifier).state = v,
                  ),
                ),
              ),
              Container(
                width: width.round().toString().length > 1 ? 36 : 28,
                alignment: Alignment.centerRight,
                child: Text('${width.round()}px',
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _pickColor(BuildContext context, WidgetRef ref, Color current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: ColorPicker(
          pickerColor: current,
          onColorChanged: (c) {
            ref.read(drawColorProvider.notifier).state = c;
            ref.read(isEraserProvider.notifier).state = false;
          },
          pickerAreaHeightPercent: 0.5,
          labelTypes: const [],
        ),
      ),
    );
  }
}
