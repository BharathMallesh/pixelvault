import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor_provider.dart';
import '../theme/app_theme.dart';

class BlurToolPanel extends ConsumerWidget {
  const BlurToolPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final blurStrength = state.current.blurStrength;

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Visual blur preview strip
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _BlurPreviewStrip(strength: blurStrength),
            ),
          ),

          // Blur type selector
          const Text('Blur type',
              style: TextStyle(fontSize: 11, color: Colors.white54, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              _BlurTypeChip(label: 'Portrait', icon: Icons.person_outline, isActive: true),
              const SizedBox(width: 8),
              _BlurTypeChip(label: 'Radial', icon: Icons.lens_blur_outlined, isActive: false),
              const SizedBox(width: 8),
              _BlurTypeChip(label: 'Linear', icon: Icons.linear_scale_outlined, isActive: false),
            ],
          ),
          const SizedBox(height: 14),

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
                    thumbRadius: 8,
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

          const SizedBox(height: 10),
          const Text(
            'Portrait mode blurs the background behind the subject.',
            style: TextStyle(fontSize: 11, color: Colors.white24),
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

class _BlurPreviewStrip extends StatelessWidget {
  final double strength;
  const _BlurPreviewStrip({required this.strength});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.8),
            Colors.white.withOpacity(0.8 - strength / 100 * 0.6),
            Colors.white.withOpacity(0.8 - strength / 100 * 0.75),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person, size: 20, color: Color(0xFF1565C0)),
          const SizedBox(width: 8),
          Text(
            'Focus',
            style: TextStyle(
              fontSize: 12,
              color: const Color(0xFF1565C0).withOpacity(
                  1.0 - strength / 200),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  const _BlurTypeChip(
      {required this.label, required this.icon, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.toolbarSelected
            : Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive ? AppTheme.primaryLight : Colors.transparent,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 14,
              color: isActive ? Colors.white : Colors.white54),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? Colors.white : Colors.white54,
              )),
        ],
      ),
    );
  }
}
