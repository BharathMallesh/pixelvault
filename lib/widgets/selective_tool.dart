import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/brush_mask.dart';
import '../providers/editor_provider.dart';
import '../theme/app_theme.dart';
import 'adjustment_slider.dart';

// Brush size for the selective-edit region, in screen pixels.
final selectiveBrushSizeProvider = StateProvider<double>((ref) => 45.0);

// ── Selective overlay: paint the region to adjust ────────────────────
class SelectiveToolOverlay extends ConsumerWidget {
  final Size imageSize;
  const SelectiveToolOverlay({super.key, required this.imageSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mask = ref.watch(editorProvider).current.selectiveMask;
    final brushSize = ref.watch(selectiveBrushSizeProvider);

    void addDab(Offset pos, BuildContext ctx) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final size = box.size;
      ref.read(editorProvider.notifier).addSelectiveDab(BrushDab(
            x: (pos.dx / size.width).clamp(0.0, 1.0),
            y: (pos.dy / size.height).clamp(0.0, 1.0),
            radius: brushSize / size.width,
          ));
    }

    return GestureDetector(
      onTapDown: (d) {
        addDab(d.localPosition, context);
        ref.read(editorProvider.notifier).commitHistory();
      },
      onPanUpdate: (d) => addDab(d.localPosition, context),
      onPanEnd: (_) => ref.read(editorProvider.notifier).commitHistory(),
      child: CustomPaint(
        painter: _SelectivePainter(mask: mask),
        size: Size.infinite,
      ),
    );
  }
}

class _SelectivePainter extends CustomPainter {
  final BrushMask mask;
  _SelectivePainter({required this.mask});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = AppTheme.primaryLight.withOpacity(0.25)
      ..style = PaintingStyle.fill;
    for (final d in mask.dabs) {
      canvas.drawCircle(
          Offset(d.x * size.width, d.y * size.height),
          d.radius * size.width, fill);
    }
  }

  @override
  bool shouldRepaint(_SelectivePainter old) =>
      old.mask.dabs.length != mask.dabs.length;
}

// ── Selective Tool Panel ─────────────────────────────────────────────
class SelectiveToolPanel extends ConsumerWidget {
  const SelectiveToolPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final s = state.current;
    final hasMask = s.selectiveMask.isNotEmpty;
    final brushSize = ref.watch(selectiveBrushSizeProvider);

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.brush, size: 15, color: AppTheme.primaryLight),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasMask
                      ? 'Adjustments below apply to the painted area'
                      : 'Brush over an area, then adjust it below',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
              if (hasMask)
                GestureDetector(
                  onTap: n.clearSelective,
                  child: const Text('Clear',
                      style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Brush size
          Row(
            children: [
              const SizedBox(
                width: 70,
                child: Text('Brush',
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
                    min: 15,
                    max: 90,
                    onChanged: (v) =>
                        ref.read(selectiveBrushSizeProvider.notifier).state = v,
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text('${brushSize.round()}px',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 18),

          // Local adjustments (disabled visually until a region is painted)
          Opacity(
            opacity: hasMask ? 1.0 : 0.4,
            child: IgnorePointer(
              ignoring: !hasMask,
              child: Column(children: [
                AdjustmentSlider(
                    label: 'Brightness', value: s.selBrightness, onChanged: n.setSelBrightness),
                AdjustmentSlider(
                    label: 'Contrast', value: s.selContrast, onChanged: n.setSelContrast),
                AdjustmentSlider(
                    label: 'Saturation', value: s.selSaturation, onChanged: n.setSelSaturation),
                AdjustmentSlider(
                    label: 'Warmth', value: s.selWarmth, onChanged: n.setSelWarmth),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
