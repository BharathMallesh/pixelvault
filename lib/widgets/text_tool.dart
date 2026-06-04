import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/text_overlay.dart';
import '../theme/app_theme.dart';

// Provider for all text overlays on current photo
final textOverlaysProvider = StateProvider<List<TextOverlay>>((ref) => []);
final selectedTextIdProvider = StateProvider<String?>((ref) => null);

const _fontFamilies = ['Inter', 'Serif', 'Monospace'];
const _fontSizes = [16.0, 20.0, 24.0, 32.0, 40.0, 52.0, 64.0];

class TextOverlayCanvas extends ConsumerStatefulWidget {
  final Size canvasSize;
  const TextOverlayCanvas({super.key, required this.canvasSize});
  @override
  ConsumerState<TextOverlayCanvas> createState() => _TextOverlayCanvasState();
}

class _TextOverlayCanvasState extends ConsumerState<TextOverlayCanvas> {
  @override
  Widget build(BuildContext context) {
    final overlays = ref.watch(textOverlaysProvider);
    final selectedId = ref.watch(selectedTextIdProvider);

    return Stack(
      children: overlays.map((overlay) {
        final isSelected = overlay.id == selectedId;
        return _DraggableText(
          key: ValueKey(overlay.id),
          overlay: overlay,
          canvasSize: widget.canvasSize,
          isSelected: isSelected,
          onTap: () => ref.read(selectedTextIdProvider.notifier).state = overlay.id,
          onMove: (dx, dy) {
            final list = ref.read(textOverlaysProvider);
            ref.read(textOverlaysProvider.notifier).state = list.map((o) {
              if (o.id != overlay.id) return o;
              return o.copyWith(
                x: (o.x + dx / widget.canvasSize.width).clamp(0.05, 0.95),
                y: (o.y + dy / widget.canvasSize.height).clamp(0.05, 0.95),
              );
            }).toList();
          },
          onDelete: () {
            ref.read(textOverlaysProvider.notifier).state =
                ref.read(textOverlaysProvider).where((o) => o.id != overlay.id).toList();
            ref.read(selectedTextIdProvider.notifier).state = null;
          },
        );
      }).toList(),
    );
  }
}

class _DraggableText extends StatelessWidget {
  final TextOverlay overlay;
  final Size canvasSize;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(double dx, double dy) onMove;
  final VoidCallback onDelete;

  const _DraggableText({
    super.key, required this.overlay, required this.canvasSize,
    required this.isSelected, required this.onTap,
    required this.onMove, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: overlay.x * canvasSize.width - 60,
      top: overlay.y * canvasSize.height - 20,
      child: GestureDetector(
        onTap: onTap,
        onPanUpdate: (d) => onMove(d.delta.dx, d.delta.dy),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: overlay.hasBackground
                    ? overlay.backgroundColor.withOpacity(0.7)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: isSelected
                    ? Border.all(color: Colors.white.withOpacity(0.7), width: 1)
                    : null,
              ),
              child: Text(
                overlay.text,
                textAlign: _toFlutterAlign(overlay.alignment),
                style: TextStyle(
                  fontSize: overlay.fontSize,
                  color: overlay.color,
                  fontWeight: overlay.style == TextStyle2.bold ||
                          overlay.style == TextStyle2.boldItalic
                      ? FontWeight.bold
                      : FontWeight.normal,
                  fontStyle: overlay.style == TextStyle2.italic ||
                          overlay.style == TextStyle2.boldItalic
                      ? FontStyle.italic
                      : FontStyle.normal,
                  shadows: [
                    Shadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 4,
                        offset: const Offset(1, 1)),
                  ],
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                top: -10, right: -10,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  TextAlign _toFlutterAlign(TextAlignment2 a) {
    switch (a) {
      case TextAlignment2.left: return TextAlign.left;
      case TextAlignment2.center: return TextAlign.center;
      case TextAlignment2.right: return TextAlign.right;
    }
  }
}

// ── Text Tool Panel ────────────────────────────────────────────────

class TextToolPanel extends ConsumerStatefulWidget {
  const TextToolPanel({super.key});
  @override
  ConsumerState<TextToolPanel> createState() => _TextToolPanelState();
}

class _TextToolPanelState extends ConsumerState<TextToolPanel> {
  final _ctrl = TextEditingController();
  Color _color = Colors.white;
  double _fontSize = 24;
  TextStyle2 _style = TextStyle2.bold;
  bool _hasBg = false;

  void _addText() {
    if (_ctrl.text.trim().isEmpty) return;
    final overlay = TextOverlay(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: _ctrl.text.trim(),
      fontSize: _fontSize,
      color: _color,
      hasBackground: _hasBg,
      style: _style,
      x: 0.5, y: 0.4,
    );
    ref.read(textOverlaysProvider.notifier).state = [
      ...ref.read(textOverlaysProvider), overlay
    ];
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final overlays = ref.watch(textOverlaysProvider);

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Type your text…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _addText,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppTheme.primary, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.add, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Controls row
          Row(
            children: [
              // Color picker dot
              GestureDetector(
                onTap: () => _pickColor(context),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Font size
              const Text('Size', style: TextStyle(fontSize: 11, color: Colors.white38)),
              const SizedBox(width: 6),
              DropdownButton<double>(
                value: _fontSize,
                dropdownColor: const Color(0xFF2A2A2A),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                underline: const SizedBox(),
                items: _fontSizes.map((s) => DropdownMenuItem(
                      value: s, child: Text('${s.round()}'))).toList(),
                onChanged: (v) => setState(() => _fontSize = v ?? 24),
              ),
              const SizedBox(width: 10),

              // Style toggle
              for (final s in TextStyle2.values)
                GestureDetector(
                  onTap: () => setState(() => _style = s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: _style == s
                          ? AppTheme.toolbarSelected
                          : Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_styleLabel(s),
                        style: TextStyle(
                            fontSize: 11,
                            color: _style == s ? Colors.white : Colors.white54)),
                  ),
                ),

              const Spacer(),
              // Background toggle
              GestureDetector(
                onTap: () => setState(() => _hasBg = !_hasBg),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _hasBg ? AppTheme.toolbarSelected : Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('BG', style: TextStyle(fontSize: 11, color: Colors.white60)),
                ),
              ),
            ],
          ),

          if (overlays.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${overlays.length} text layer${overlays.length > 1 ? 's' : ''} — drag to reposition',
                style: const TextStyle(fontSize: 10, color: Colors.white24)),
          ],
        ],
      ),
    );
  }

  String _styleLabel(TextStyle2 s) {
    switch (s) {
      case TextStyle2.normal: return 'Aa';
      case TextStyle2.bold: return 'B';
      case TextStyle2.italic: return 'I';
      case TextStyle2.boldItalic: return 'BI';
    }
  }

  void _pickColor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: ColorPicker(
          pickerColor: _color,
          onColorChanged: (c) => setState(() => _color = c),
          pickerAreaHeightPercent: 0.5,
          labelTypes: const [],
        ),
      ),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
}
