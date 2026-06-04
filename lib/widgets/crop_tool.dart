import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor_provider.dart';
import '../models/edit_settings.dart';
import '../theme/app_theme.dart';

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

class CropToolPanel extends ConsumerStatefulWidget {
  const CropToolPanel({super.key});
  @override
  ConsumerState<CropToolPanel> createState() => _CropToolPanelState();
}

class _CropToolPanelState extends ConsumerState<CropToolPanel> {
  double _selectedRatio = 0.0;

  @override
  Widget build(BuildContext context) {
    final n = ref.read(editorProvider.notifier);
    final state = ref.watch(editorProvider);

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Aspect ratio chips
          const Text('Aspect ratio',
              style: TextStyle(fontSize: 11, color: Colors.white54, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _ratios.map((r) {
                final isActive = _selectedRatio == r.ratio;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedRatio = r.ratio);
                    // Apply a default full crop with chosen ratio
                    if (r.ratio == 0.0) {
                      n.clearCrop();
                    } else {
                      n.setCrop(const CropRect(left: 0, top: 0, right: 1, bottom: 1));
                    }
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
                onTap: n.clearCrop,
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
