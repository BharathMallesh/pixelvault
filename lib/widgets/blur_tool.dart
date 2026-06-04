import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/brush_mask.dart';
import '../providers/editor_provider.dart';
import '../theme/app_theme.dart';

// Brush size for painting the in-focus subject, in screen pixels.
final focusBrushSizeProvider = StateProvider<double>((ref) => 40.0);

// ── Focus overlay: paint the subject region to keep sharp ────────────
class FocusToolOverlay extends ConsumerWidget {
  final Size imageSize;
  const FocusToolOverlay({super.key, required this.imageSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mask = ref.watch(editorProvider).current.focusMask;
    final brushSize = ref.watch(focusBrushSizeProvider);

    void addDab(Offset pos, BuildContext ctx) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final size = box.size;
      ref.read(editorProvider.notifier).addFocusDab(BrushDab(
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
        painter: _FocusPainter(mask: mask),
        size: Size.infinite,
      ),
    );
  }
}

class _FocusPainter extends CustomPainter {
  final BrushMask mask;
  _FocusPainter({required this.mask});

  @override
  void paint(Canvas canvas, Size size) {
    // Tint the painted (in-focus) region so users see what stays sharp.
    final fill = Paint()
      ..color = Colors.yellow.withOpacity(0.22)
      ..style = PaintingStyle.fill;
    for (final d in mask.dabs) {
      canvas.drawCircle(
          Offset(d.x * size.width, d.y * size.height),
          d.radius * size.width, fill);
    }
  }

  @override
  bool shouldRepaint(_FocusPainter old) =>
      old.mask.dabs.length != mask.dabs.length;
}

// ── Blur Tool Panel ──────────────────────────────────────────────────
class BlurToolPanel extends ConsumerWidget {
  const BlurToolPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final blurStrength = state.current.blurStrength;
    final hasFocus = state.current.focusMask.isNotEmpty;
    final brushSize = ref.watch(focusBrushSizeProvider);

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode indicator
          Row(
            children: [
              Icon(hasFocus ? Icons.brush : Icons.lens_blur,
                  size: 15, color: AppTheme.primaryLight),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasFocus
                      ? 'Subject painted — background will blur'
                      : 'Brush over the subject to keep it sharp',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
              if (hasFocus)
                GestureDetector(
                  onTap: n.clearFocus,
                  child: const Text('Clear',
                      style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Brush size for the subject mask
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
                        ref.read(focusBrushSizeProvider.notifier).state = v,
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

          // Strength slider
          Row(
            children: [
              const SizedBox(
                width: 70,
                child: Text('Strength',
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
                    value: blurStrength,
                    min: 0,
                    max: 100,
                    onChanged: n.setBlurStrength,
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  blurStrength.round().toString(),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: blurStrength > 0
                        ? AppTheme.primaryLight
                        : Colors.white38,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Text(
            hasFocus
                ? 'Everything outside the painted subject is blurred by the strength above.'
                : 'No subject painted — a center-weighted blur is used instead.',
            style: const TextStyle(fontSize: 11, color: Colors.white24),
            textAlign: TextAlign.center,
          ),

          if (blurStrength > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: GestureDetector(
                onTap: () => n.setBlurStrength(0),
                child: const Center(
                  child: Text('Remove blur',
                      style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
