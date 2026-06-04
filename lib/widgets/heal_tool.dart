import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

// Stores heal brush strokes as a list of touch points.
//
// TODO(heal): These points are collected and previewed, but the pixel-level
// spot removal is NOT yet implemented. To make the heal brush functional,
// pass `healPointsProvider` into EditSettings (or a side channel) and add an
// inpainting pass in ImageProcessor — e.g. for each HealPoint, sample a clean
// neighbouring patch and blend it over the marked radius (a simple
// Telea/nearest-source fill). Until then this tool is preview-only.
class HealPoint {
  final double x; // 0.0 – 1.0 (normalized)
  final double y;
  final double radius;
  const HealPoint({required this.x, required this.y, required this.radius});
}

final healPointsProvider = StateProvider<List<HealPoint>>((ref) => []);
final healBrushSizeProvider = StateProvider<double>((ref) => 30.0);

class HealToolOverlay extends ConsumerStatefulWidget {
  final Size imageSize;
  const HealToolOverlay({super.key, required this.imageSize});

  @override
  ConsumerState<HealToolOverlay> createState() => _HealToolOverlayState();
}

class _HealToolOverlayState extends ConsumerState<HealToolOverlay> {
  @override
  Widget build(BuildContext context) {
    final points = ref.watch(healPointsProvider);
    final brushSize = ref.watch(healBrushSizeProvider);

    return GestureDetector(
      onTapDown: (d) => _addPoint(d.localPosition, context),
      onPanUpdate: (d) => _addPoint(d.localPosition, context),
      child: CustomPaint(
        painter: _HealPainter(points: points, brushSize: brushSize),
        size: Size.infinite,
      ),
    );
  }

  void _addPoint(Offset pos, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    final brushSize = ref.read(healBrushSizeProvider);
    ref.read(healPointsProvider.notifier).update((list) => [
          ...list,
          HealPoint(
            x: pos.dx / size.width,
            y: pos.dy / size.height,
            radius: brushSize / size.width,
          ),
        ]);
  }
}

class _HealPainter extends CustomPainter {
  final List<HealPoint> points;
  final double brushSize;
  _HealPainter({required this.points, required this.brushSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withOpacity(0.35)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final p in points) {
      final center = Offset(p.x * size.width, p.y * size.height);
      final radius = p.radius * size.width;
      canvas.drawCircle(center, radius, paint);
      canvas.drawCircle(center, radius, border);
    }
  }

  @override
  bool shouldRepaint(_HealPainter old) =>
      old.points.length != points.length;
}

// ── Heal Tool Panel (controls shown below image) ─────────────────

class HealToolPanel extends ConsumerWidget {
  const HealToolPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brushSize = ref.watch(healBrushSizeProvider);
    final points = ref.watch(healPointsProvider);

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 70,
                child: Text('Brush size',
                    style: TextStyle(fontSize: 12, color: Colors.white60)),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    activeTrackColor: AppTheme.primaryLight,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: brushSize,
                    min: 10,
                    max: 80,
                    onChanged: (v) =>
                        ref.read(healBrushSizeProvider.notifier).state = v,
                  ),
                ),
              ),
              Container(
                width: brushSize.round().toString().length > 1 ? 32 : 28,
                alignment: Alignment.centerRight,
                child: Text('${brushSize.round()}px',
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Brush size preview circle
              Container(
                width: brushSize.clamp(10, 50),
                height: brushSize.clamp(10, 50),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54, width: 1.5),
                  color: AppTheme.primary.withOpacity(0.2),
                ),
              ),
              const Spacer(),
              // Clear all spots button
              if (points.isNotEmpty)
                GestureDetector(
                  onTap: () =>
                      ref.read(healPointsProvider.notifier).state = [],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Colors.redAccent.withOpacity(0.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 14, color: Colors.redAccent),
                        SizedBox(width: 4),
                        Text('Clear all',
                            style: TextStyle(
                                fontSize: 12, color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              // Point count
              Text('${points.length} spot${points.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap or drag on the photo to mark spots for removal',
            style: TextStyle(fontSize: 11, color: Colors.white24),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
