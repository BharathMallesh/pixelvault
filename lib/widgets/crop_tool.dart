import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor_provider.dart';
import '../models/edit_settings.dart';
import '../theme/app_theme.dart';

// Currently selected crop aspect ratio (0 = free). Shared with CropOverlay.
final cropAspectRatioProvider = StateProvider<double>((ref) => 0.0);

// Preset aspect ratios
const _ratios = [
  (label: 'Free',  ratio: 0.0),
  (label: '1:1',   ratio: 1.0),
  (label: '4:3',   ratio: 4/3),
  (label: '3:4',   ratio: 3/4),
  (label: '16:9',  ratio: 16/9),
  (label: '9:16',  ratio: 9/16),
  (label: '3:2',   ratio: 3/2),
];

class CropToolPanel extends ConsumerWidget {
  const CropToolPanel({super.key});

  // Build a centered crop rect matching [ratio] (in canvas-normalized space).
  // ratio = 0 -> a roomy default box. Otherwise fit the largest centered box
  // of that aspect inside the frame (assuming a square-ish preview area).
  CropRect _rectForRatio(double ratio) {
    if (ratio <= 0) {
      return const CropRect(left: 0.05, top: 0.05, right: 0.95, bottom: 0.95);
    }
    double w = 0.9, h = 0.9;
    if (ratio >= 1) {
      h = (w / ratio).clamp(0.1, 0.9);
    } else {
      w = (h * ratio).clamp(0.1, 0.9);
    }
    final l = (1 - w) / 2, t = (1 - h) / 2;
    return CropRect(left: l, top: t, right: l + w, bottom: t + h);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(editorProvider.notifier);
    final state = ref.watch(editorProvider);
    final selectedRatio = ref.watch(cropAspectRatioProvider);

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Aspect ratio chips
          const Text('Aspect ratio · drag the box on the photo to crop',
              style: TextStyle(fontSize: 11, color: Colors.white54, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _ratios.map((r) {
                final isActive = selectedRatio == r.ratio;
                return GestureDetector(
                  onTap: () {
                    ref.read(cropAspectRatioProvider.notifier).state = r.ratio;
                    // Seed a centered crop box of the chosen shape (and let
                    // the user fine-tune by dragging the handles).
                    n.setCrop(_rectForRatio(r.ratio));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.toolbarSelected : Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(r.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: isActive ? Colors.white : Colors.white60,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Rotation row
          Row(
            children: [
              const Text('Rotate',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(width: 12),
              // Quick rotate buttons
              _RotateBtn(icon: Icons.rotate_left, label: '-90°', onTap: () {
                final cur = state.current.rotation;
                n.setRotation((cur - 90) % 360);
              }),
              const SizedBox(width: 8),
              _RotateBtn(icon: Icons.rotate_right, label: '+90°', onTap: () {
                final cur = state.current.rotation;
                n.setRotation((cur + 90) % 360);
              }),
              const SizedBox(width: 8),
              _RotateBtn(icon: Icons.flip, label: 'Flip H', onTap: n.toggleFlipH),
              const SizedBox(width: 8),
              _RotateBtn(icon: Icons.flip_outlined, label: 'Flip V', onTap: n.toggleFlipV),
            ],
          ),

          const SizedBox(height: 12),
          // Fine rotation slider
          Row(
            children: [
              const SizedBox(
                width: 60,
                child: Text('Angle', style: TextStyle(fontSize: 12, color: Colors.white60)),
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
                    value: state.current.rotation % 90,
                    min: -45,
                    max: 45,
                    onChanged: (v) => n.setRotation(v),
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '${state.current.rotation.round()}°',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
            ],
          ),

          if (state.current.cropRect != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: () {
                  n.clearCrop();
                  ref.read(cropAspectRatioProvider.notifier).state = 0.0;
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, size: 14, color: Colors.redAccent),
                    SizedBox(width: 4),
                    Text('Reset crop',
                        style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RotateBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RotateBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.white60),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        ),
      ),
    );
  }
}
