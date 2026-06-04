import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor_provider.dart';
import '../widgets/adjustment_slider.dart';

class HslChannel {
  final String id;
  final String label;
  final Color color;
  const HslChannel({required this.id, required this.label, required this.color});
}

const _channels = [
  HslChannel(id: 'red',    label: 'Red',    color: Color(0xFFE53935)),
  HslChannel(id: 'orange', label: 'Orange', color: Color(0xFFFB8C00)),
  HslChannel(id: 'yellow', label: 'Yellow', color: Color(0xFFFDD835)),
  HslChannel(id: 'green',  label: 'Green',  color: Color(0xFF43A047)),
  HslChannel(id: 'blue',   label: 'Blue',   color: Color(0xFF1E88E5)),
  HslChannel(id: 'purple', label: 'Purple', color: Color(0xFF8E24AA)),
];

class HslPanel extends ConsumerStatefulWidget {
  const HslPanel({super.key});
  @override
  ConsumerState<HslPanel> createState() => _HslPanelState();
}

class _HslPanelState extends ConsumerState<HslPanel> {
  String _activeChannel = 'red';
  String _activeProp = 'sat'; // hue | sat | lum

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final s = state.current;

    double _getValue(String channel, String prop) {
      switch ('${channel}_$prop') {
        case 'red_hue':    return s.hslRedHue;
        case 'red_sat':    return s.hslRedSat;
        case 'red_lum':    return s.hslRedLum;
        case 'orange_hue': return s.hslOrangeHue;
        case 'orange_sat': return s.hslOrangeSat;
        case 'orange_lum': return s.hslOrangeLum;
        case 'yellow_hue': return s.hslYellowHue;
        case 'yellow_sat': return s.hslYellowSat;
        case 'yellow_lum': return s.hslYellowLum;
        case 'green_hue':  return s.hslGreenHue;
        case 'green_sat':  return s.hslGreenSat;
        case 'green_lum':  return s.hslGreenLum;
        case 'blue_hue':   return s.hslBlueHue;
        case 'blue_sat':   return s.hslBlueSat;
        case 'blue_lum':   return s.hslBlueLum;
        case 'purple_hue': return s.hslPurpleHue;
        case 'purple_sat': return s.hslPurpleSat;
        case 'purple_lum': return s.hslPurpleLum;
        default: return 0;
      }
    }

    final activeChannel = _channels.firstWhere((c) => c.id == _activeChannel);

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Channel dot picker
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _channels.map((ch) {
                final isActive = ch.id == _activeChannel;
                return GestureDetector(
                  onTap: () => setState(() => _activeChannel = ch.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? ch.color.withOpacity(0.25) : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isActive ? ch.color : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(color: ch.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(ch.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: isActive ? ch.color : Colors.white54,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                            )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // H/S/L tab
          Row(
            children: [
              for (final prop in [('hue', 'Hue'), ('sat', 'Saturation'), ('lum', 'Luminance')])
                GestureDetector(
                  onTap: () => setState(() => _activeProp = prop.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: _activeProp == prop.$1
                          ? Colors.white.withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(prop.$2,
                        style: TextStyle(
                          fontSize: 12,
                          color: _activeProp == prop.$1 ? Colors.white : Colors.white38,
                          fontWeight: _activeProp == prop.$1 ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Active slider
          AdjustmentSlider(
            label: activeChannel.label,
            value: _getValue(_activeChannel, _activeProp),
            onChanged: (v) => n.setHsl(_activeChannel, _activeProp, v),
          ),

          const SizedBox(height: 6),
          // Quick overview — all channels dot matrix
          _ChannelMatrix(getValue: _getValue),
        ],
      ),
    );
  }
}

class _ChannelMatrix extends StatelessWidget {
  final double Function(String, String) getValue;
  const _ChannelMatrix({required this.getValue});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: _channels.map((ch) {
        final hasEdit = getValue(ch.id, 'hue') != 0 ||
            getValue(ch.id, 'sat') != 0 ||
            getValue(ch.id, 'lum') != 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: hasEdit ? ch.color : Colors.white24,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 3),
            Text(ch.label[0],
                style: TextStyle(
                  fontSize: 10,
                  color: hasEdit ? ch.color : Colors.white24,
                )),
          ],
        );
      }).toList(),
    );
  }
}
