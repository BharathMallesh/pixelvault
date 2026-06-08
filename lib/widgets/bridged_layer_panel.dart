import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layer.dart';
import '../providers/layer_bridge.dart';

/// Phase 6.5 bridge UI — a Layers panel backed by [bridgedLayersProvider].
/// Shows the real composition (Photo + Text/Drawing/Stickers groups) and lets
/// the user show/hide each group. Reorder/opacity/blend per group are part of
/// the deferred full migration; this gives users a true layers view now.
class BridgedLayerPanel extends ConsumerWidget {
  const BridgedLayerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layers = ref.watch(bridgedLayersProvider);
    final groups = ref.read(groupVisibilityProvider.notifier);

    // Display top-first.
    final display = layers.reversed.toList();

    return Container(
      color: const Color(0xFF1A1A1A),
      constraints: const BoxConstraints(maxHeight: 240),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text('Layers',
                style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          if (display.length == 1)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Text(
                'Add text, drawings, or stickers and they appear here as layers.',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: display.length,
              itemBuilder: (ctx, i) {
                final layer = display[i];
                return _GroupTile(
                  layer: layer,
                  onToggle: () {
                    switch (layer.id) {
                      case kTextGroupId:
                        groups.toggleText();
                        break;
                      case kDrawGroupId:
                        groups.toggleDraw();
                        break;
                      case kStickerGroupId:
                        groups.toggleSticker();
                        break;
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final Layer layer;
  final VoidCallback onToggle;
  const _GroupTile({required this.layer, required this.onToggle});

  IconData get _icon {
    switch (layer.kind) {
      case LayerKind.base:
        return Icons.photo_outlined;
      case LayerKind.text:
        return Icons.text_fields_outlined;
      case LayerKind.sticker:
        return Icons.emoji_emotions_outlined;
      case LayerKind.draw:
        return Icons.brush_outlined;
      case LayerKind.image:
        return Icons.image_outlined;
      case LayerKind.adjustment:
        return Icons.tune_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBase = layer.kind == LayerKind.base;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: isBase ? null : onToggle,
            icon: Icon(
              layer.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 18,
              color: isBase
                  ? Colors.white24
                  : (layer.visible ? Colors.white70 : Colors.white24),
            ),
          ),
          Icon(_icon, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              layer.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: layer.visible ? Colors.white : Colors.white38,
              ),
            ),
          ),
          if (isBase)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('base', style: TextStyle(fontSize: 10, color: Colors.white24)),
            ),
        ],
      ),
    );
  }
}
