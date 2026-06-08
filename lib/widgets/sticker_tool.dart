import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sticker_overlay.dart';
import '../theme/app_theme.dart';

final stickerOverlaysProvider = StateProvider<List<StickerOverlay>>((ref) => []);
final selectedStickerIdProvider = StateProvider<String?>((ref) => null);

class StickerCanvas extends ConsumerWidget {
  final Size canvasSize;
  const StickerCanvas({super.key, required this.canvasSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stickers = ref.watch(stickerOverlaysProvider);
    final selectedId = ref.watch(selectedStickerIdProvider);

    return Stack(
      children: stickers.map((s) {
        final isSelected = s.id == selectedId;
        return Positioned(
          left: s.x * canvasSize.width - s.size / 2,
          top:  s.y * canvasSize.height - s.size / 2,
          child: GestureDetector(
            onTap: () => ref.read(selectedStickerIdProvider.notifier).state =
                isSelected ? null : s.id,
            onPanUpdate: (d) {
              ref.read(stickerOverlaysProvider.notifier).state =
                  ref.read(stickerOverlaysProvider).map((o) {
                if (o.id != s.id) return o;
                return o.copyWith(
                  x: (o.x + d.delta.dx / canvasSize.width).clamp(0.05, 0.95),
                  y: (o.y + d.delta.dy / canvasSize.height).clamp(0.05, 0.95),
                );
              }).toList();
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: isSelected
                      ? BoxDecoration(
                          border: Border.all(color: Colors.white54, width: 1),
                          borderRadius: BorderRadius.circular(6),
                        )
                      : null,
                  padding: const EdgeInsets.all(2),
                  child: Text(s.emoji, style: TextStyle(fontSize: s.size * 0.8)),
                ),
                if (isSelected) ...[
                  // Delete button
                  Positioned(
                    top: -8, right: -8,
                    child: GestureDetector(
                      onTap: () {
                        ref.read(stickerOverlaysProvider.notifier).state =
                            ref.read(stickerOverlaysProvider)
                                .where((o) => o.id != s.id).toList();
                        ref.read(selectedStickerIdProvider.notifier).state = null;
                      },
                      child: Container(
                        width: 18, height: 18,
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 11, color: Colors.white),
                      ),
                    ),
                  ),
                  // Scale handle
                  Positioned(
                    bottom: -8, right: -8,
                    child: GestureDetector(
                      onPanUpdate: (d) {
                        ref.read(stickerOverlaysProvider.notifier).state =
                            ref.read(stickerOverlaysProvider).map((o) {
                          if (o.id != s.id) return o;
                          return o.copyWith(size: (o.size + d.delta.dx).clamp(20, 120));
                        }).toList();
                      },
                      child: Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                            color: AppTheme.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.open_in_full, size: 10, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Phase 8.1 — sticker picker with category tabs + keyword search.
class StickerToolPanel extends ConsumerStatefulWidget {
  const StickerToolPanel({super.key});
  @override
  ConsumerState<StickerToolPanel> createState() => _StickerToolPanelState();
}

class _StickerToolPanelState extends ConsumerState<StickerToolPanel> {
  int _category = 0;
  String _query = '';

  void _add(String emoji) {
    final s = StickerOverlay(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      emoji: emoji, x: 0.5, y: 0.4, size: 48,
    );
    ref.read(stickerOverlaysProvider.notifier).state = [
      ...ref.read(stickerOverlaysProvider), s
    ];
    ref.read(selectedStickerIdProvider.notifier).state = s.id;
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final List<String> emojis = searching
        ? searchStickers(_query).map((i) => i.emoji).toList()
        : stickerCategories[_category].items.map((i) => i.emoji).toList();

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search field.
          SizedBox(
            height: 36,
            child: TextField(
              style: const TextStyle(fontSize: 13, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search stickers…',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.white30),
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
                filled: true,
                fillColor: Colors.white10,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          // Category tabs (hidden while searching).
          if (!searching)
            SizedBox(
              height: 26,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: stickerCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final sel = i == _category;
                  return GestureDetector(
                    onTap: () => setState(() => _category = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: sel ? AppTheme.primary.withOpacity(0.25) : Colors.white10,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(stickerCategories[i].name,
                          style: TextStyle(
                              fontSize: 11,
                              color: sel ? Colors.white : Colors.white54)),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          // Sticker grid.
          SizedBox(
            height: 96,
            child: emojis.isEmpty
                ? const Center(
                    child: Text('No stickers match',
                        style: TextStyle(fontSize: 12, color: Colors.white38)))
                : GridView.count(
                    crossAxisCount: 8,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: emojis.map((emoji) {
                      return GestureDetector(
                        onTap: () => _add(emoji),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(emoji, style: const TextStyle(fontSize: 22)),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
