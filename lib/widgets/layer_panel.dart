import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layer.dart';
import '../providers/layer_provider.dart';
import '../theme/app_theme.dart';

/// Phase 6.2 — the layer panel. Lists layers top-to-bottom (top of the stack
/// shown first, matching how users think), with drag-to-reorder, show/hide,
/// opacity, blend mode, duplicate, and delete. Selecting a layer drives the
/// rest of the editor (which layer edits apply to).
class LayerPanel extends ConsumerWidget {
  const LayerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stack = ref.watch(layerProvider);
    final n = ref.read(layerProvider.notifier);

    // Display top-of-stack first. The stack stores bottom..top, so reverse for
    // display and translate indices back when reordering.
    final display = stack.layers.reversed.toList();
    final count = stack.layers.length;

    return Container(
      color: const Color(0xFF1A1A1A),
      constraints: const BoxConstraints(maxHeight: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text('Layers · drag to reorder',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
          ),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: display.length,
              onReorder: (oldDisplay, newDisplay) {
                // Convert display indices (reversed) to stack indices.
                final from = count - 1 - oldDisplay;
                var toDisplay = newDisplay;
                if (toDisplay > oldDisplay) toDisplay -= 1;
                final to = count - 1 - toDisplay;
                n.reorder(from, to);
              },
              itemBuilder: (ctx, i) {
                final layer = display[i];
                return _LayerTile(
                  key: ValueKey(layer.id),
                  layer: layer,
                  displayIndex: i,
                  selected: layer.id == stack.selectedId,
                  onSelect: () => n.select(layer.id),
                  onToggle: () => n.toggleVisible(layer.id),
                  onOpacity: (v) => n.setOpacity(layer.id, v),
                  onBlend: (b) => n.setBlend(layer.id, b),
                  onDuplicate: () => n.duplicate(layer.id),
                  onDelete: layer.kind == LayerKind.base
                      ? null
                      : () => n.remove(layer.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerTile extends StatelessWidget {
  final Layer layer;
  final int displayIndex;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onToggle;
  final ValueChanged<double> onOpacity;
  final ValueChanged<LayerBlend> onBlend;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;

  const _LayerTile({
    super.key,
    required this.layer,
    required this.displayIndex,
    required this.selected,
    required this.onSelect,
    required this.onToggle,
    required this.onOpacity,
    required this.onBlend,
    required this.onDuplicate,
    required this.onDelete,
  });

  IconData get _kindIcon {
    switch (layer.kind) {
      case LayerKind.base:
        return Icons.photo_outlined;
      case LayerKind.image:
        return Icons.image_outlined;
      case LayerKind.text:
        return Icons.text_fields_outlined;
      case LayerKind.sticker:
        return Icons.emoji_emotions_outlined;
      case LayerKind.draw:
        return Icons.brush_outlined;
      case LayerKind.adjustment:
        return Icons.tune_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary.withValues(alpha: 0.18) : Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? AppTheme.primaryLight : Colors.transparent,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: displayIndex,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Icon(Icons.drag_indicator, size: 18, color: Colors.white38),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onToggle,
                icon: Icon(
                  layer.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18,
                  color: layer.visible ? Colors.white70 : Colors.white24,
                ),
              ),
              Icon(_kindIcon, size: 16, color: Colors.white54),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: onSelect,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    layer.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: layer.visible ? Colors.white : Colors.white38,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDuplicate,
                icon: const Icon(Icons.copy_outlined, size: 16, color: Colors.white54),
                tooltip: 'Duplicate',
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline,
                    size: 16, color: onDelete == null ? Colors.white12 : Colors.white54),
                tooltip: 'Delete',
              ),
            ],
          ),
          // Per-layer controls only when selected, to keep the list compact.
          if (selected)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  const Text('Opacity', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  Expanded(
                    child: Slider(
                      value: layer.opacity,
                      min: 0, max: 1,
                      activeColor: AppTheme.primary,
                      onChanged: onOpacity,
                    ),
                  ),
                  _BlendDropdown(value: layer.blend, onChanged: onBlend),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BlendDropdown extends StatelessWidget {
  final LayerBlend value;
  final ValueChanged<LayerBlend> onChanged;
  const _BlendDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<LayerBlend>(
      value: value,
      isDense: true,
      dropdownColor: const Color(0xFF222222),
      underline: const SizedBox.shrink(),
      style: const TextStyle(fontSize: 11, color: Colors.white70),
      items: [
        for (final b in LayerBlend.values)
          DropdownMenuItem(value: b, child: Text(b.label)),
      ],
      onChanged: (b) {
        if (b != null) onChanged(b);
      },
    );
  }
}
