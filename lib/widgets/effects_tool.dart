import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor_provider.dart';
import '../theme/app_theme.dart';

/// Phase 8.2 + 8.3 — frames/borders and light overlays. All effects are
/// rendered procedurally in the processor (no bundled artwork), so they stay
/// lightweight and fully offline. Picking one applies it live to the preview;
/// a strength/width slider tunes it.
class EffectsToolPanel extends ConsumerWidget {
  const EffectsToolPanel({super.key});

  static const _frames = [
    ('none', 'None', Icons.block),
    ('white', 'White', Icons.crop_square),
    ('black', 'Black', Icons.crop_square),
    ('film', 'Film', Icons.movie_outlined),
    ('polaroid', 'Polaroid', Icons.photo_outlined),
    ('rounded', 'Rounded', Icons.rounded_corner),
  ];

  static const _overlays = [
    ('none', 'None', Icons.block),
    ('leak_warm', 'Warm leak', Icons.wb_sunny_outlined),
    ('leak_cool', 'Cool leak', Icons.ac_unit_outlined),
    ('sunflare', 'Sun flare', Icons.flare_outlined),
    ('bokeh', 'Bokeh', Icons.blur_on_outlined),
    ('grain', 'Film grain', Icons.grain_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(editorProvider).current;
    final n = ref.read(editorProvider.notifier);

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Frame', style: TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 8),
            _chipRow(
              items: _frames,
              selected: s.frameStyle,
              onTap: (id) => n.setFrame(id),
            ),
            if (s.frameStyle != 'none')
              _slider('Width', s.frameWidth, (v) => n.setFrameWidth(v)),
            const SizedBox(height: 14),
            const Text('Light overlay',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 8),
            _chipRow(
              items: _overlays,
              selected: s.overlayEffect,
              onTap: (id) => n.setOverlay(id),
            ),
            if (s.overlayEffect != 'none')
              _slider('Strength', s.overlayStrength,
                  (v) => n.setOverlayStrength(v)),
          ],
        ),
      ),
    );
  }

  Widget _chipRow({
    required List<(String, String, IconData)> items,
    required String selected,
    required ValueChanged<String> onTap,
  }) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final (id, label, icon) = items[i];
          final isSel = id == selected;
          return GestureDetector(
            onTap: () => onTap(id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSel ? AppTheme.primary.withValues(alpha: 0.25) : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel ? AppTheme.primaryLight : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(icon,
                      size: 20, color: isSel ? AppTheme.primaryLight : Colors.white60),
                ),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 9,
                        color: isSel ? Colors.white : Colors.white38)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
              width: 60,
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.white54))),
          Expanded(
            child: Slider(
              value: value.clamp(0, 100),
              min: 0,
              max: 100,
              activeColor: AppTheme.primary,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 30,
            child: Text('${value.round()}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ),
        ],
      ),
    );
  }
}
