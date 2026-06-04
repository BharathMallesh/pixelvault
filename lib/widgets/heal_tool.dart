import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/brush_mask.dart';
import '../providers/editor_provider.dart';
import '../theme/app_theme.dart';

// Brush size for the healing tool, in screen pixels.
final healBrushSizeProvider = StateProvider<double>((ref) => 30.0);

// ── Heal overlay: paints dabs onto the editor's heal mask ────────────
class HealToolOverlay extends ConsumerWidget {
  final Size imageSize;
  const HealToolOverlay({super.key, required this.imageSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mask = ref.watch(editorProvider).current.healMask;
    final brushSize = ref.watch(healBrushSizeProvider);

    void addDab(Offset pos, BuildContext ctx) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final size = box.size;
      ref.read(editorProvider.notifier).addHealDab(BrushDab(
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
        painter: _HealPainter(mask: mask),
        size: Size.infinite,
      ),
    );
  }
}

class _HealPainter extends CustomPainter {
  final BrushMask mask;
  _HealPainter({required this.mask});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = AppTheme.primary.withOpacity(0.35)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final d in mask.dabs) {
      final center = Offset(d.x * size.width, d.y * size.height);
      final radius = d.radius * size.width;
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, border);
    }
  }

  @override
  bool shouldRepaint(_HealPainter old) =>
      old.mask.dabs.length != mask.dabs.length;
}

// ── Heal Tool Panel (controls shown below image) ─────────────────────
class HealToolPanel extends ConsumerWidget {
  const HealToolPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brushSize = ref.watch(healBrushSizeProvider);
    final mask = ref.watch(editorProvider).current.healMask;
    final count = mask.dabs.length;

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
              if (count > 0)
                GestureDetector(
                  onTap: () => ref.read(editorProvider.notifier).clearHeal(),
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
              Text('$count spot${count == 1 ? '' : 's'}',
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
