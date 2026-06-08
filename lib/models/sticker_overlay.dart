class StickerOverlay {
  final String id;
  final String emoji;
  final double x; // normalized
  final double y;
  final double size;
  final double rotation;

  const StickerOverlay({
    required this.id, required this.emoji,
    this.x = 0.5, this.y = 0.5, this.size = 48, this.rotation = 0,
  });

  StickerOverlay copyWith({String? emoji, double? x, double? y, double? size, double? rotation}) {
    return StickerOverlay(
      id: id, emoji: emoji ?? this.emoji,
      x: x ?? this.x, y: y ?? this.y,
      size: size ?? this.size, rotation: rotation ?? this.rotation,
    );
  }
}

// Built-in sticker set, grouped into categories (Phase 8.1). Each entry pairs
// an emoji with simple keywords used by search.
class StickerItem {
  final String emoji;
  final String keywords;
  const StickerItem(this.emoji, this.keywords);
}

class StickerCategory {
  final String name;
  final List<StickerItem> items;
  const StickerCategory(this.name, this.items);
}

const stickerCategories = <StickerCategory>[
  StickerCategory('Smileys', [
    StickerItem('😍', 'love heart eyes happy'),
    StickerItem('😂', 'laugh joy lol'),
    StickerItem('😎', 'cool sunglasses'),
    StickerItem('🥰', 'love hearts'),
    StickerItem('😜', 'wink tongue silly'),
    StickerItem('🤩', 'star struck wow'),
    StickerItem('😇', 'angel halo'),
    StickerItem('🥳', 'party celebrate'),
    StickerItem('😴', 'sleep tired'),
    StickerItem('🤔', 'think hmm'),
  ]),
  StickerCategory('Love', [
    StickerItem('❤️', 'heart love red'),
    StickerItem('💕', 'hearts love'),
    StickerItem('💖', 'sparkle heart love'),
    StickerItem('💘', 'cupid arrow heart'),
    StickerItem('💋', 'kiss lips'),
    StickerItem('🌹', 'rose flower love'),
    StickerItem('💍', 'ring engagement'),
    StickerItem('💝', 'gift heart'),
  ]),
  StickerCategory('Celebrate', [
    StickerItem('🎉', 'party celebrate confetti'),
    StickerItem('🎊', 'confetti party'),
    StickerItem('🎈', 'balloon party'),
    StickerItem('🎂', 'cake birthday'),
    StickerItem('🎁', 'gift present'),
    StickerItem('🏆', 'trophy win award'),
    StickerItem('👑', 'crown king queen'),
    StickerItem('💯', 'hundred perfect'),
  ]),
  StickerCategory('Nature', [
    StickerItem('🌸', 'flower blossom pink'),
    StickerItem('🌻', 'sunflower flower'),
    StickerItem('🌈', 'rainbow'),
    StickerItem('☀️', 'sun sunny'),
    StickerItem('🌙', 'moon night'),
    StickerItem('⭐', 'star'),
    StickerItem('✨', 'sparkles shine'),
    StickerItem('🦋', 'butterfly'),
    StickerItem('🍀', 'clover luck'),
    StickerItem('🔥', 'fire flame hot'),
  ]),
  StickerCategory('Fun', [
    StickerItem('🚀', 'rocket space launch'),
    StickerItem('📸', 'camera photo'),
    StickerItem('🎵', 'music note'),
    StickerItem('💎', 'diamond gem'),
    StickerItem('⚡', 'lightning bolt energy'),
    StickerItem('🍕', 'pizza food'),
    StickerItem('☕', 'coffee'),
    StickerItem('🍦', 'icecream dessert'),
    StickerItem('👍', 'thumbs up like'),
    StickerItem('🙌', 'hands celebrate'),
  ]),
];

// Flat list kept for any legacy callers.
List<String> get builtInStickers =>
    [for (final c in stickerCategories) ...c.items.map((i) => i.emoji)];

/// Search across all categories by keyword or the emoji itself.
List<StickerItem> searchStickers(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out = <StickerItem>[];
  for (final c in stickerCategories) {
    for (final i in c.items) {
      if (i.keywords.contains(q) || i.emoji == q) out.add(i);
    }
  }
  return out;
}
