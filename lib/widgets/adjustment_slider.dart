import 'package:flutter/material.dart';

class AdjustmentSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final void Function(double) onChanged;

  const AdjustmentSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = -100,
    this.max = 100,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.round();
    final isChanged = value != 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Label
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isChanged ? Colors.white : Colors.white60,
                fontWeight:
                    isChanged ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbRadius: 8,
                activeTrackColor: isChanged
                    ? const Color(0xFF5E92F3)
                    : Colors.white30,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                overlayColor: Colors.white12,
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          // Value display
          SizedBox(
            width: 36,
            child: Text(
              displayValue >= 0 ? '+$displayValue' : '$displayValue',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: isChanged
                    ? const Color(0xFF5E92F3)
                    : Colors.white38,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Reset dot
          GestureDetector(
            onTap: isChanged ? () => onChanged(0) : null,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isChanged
                      ? const Color(0xFF5E92F3)
                      : Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
