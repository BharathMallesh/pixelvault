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

// Built-in sticker set
const builtInStickers = [
  '❤️','😍','🔥','⭐','✨','💫','🌟','🎉','🎊','🎈',
  '🌸','🌺','🌻','🍀','🦋','🌈','🌙','☀️','⚡','🎵',
  '💎','👑','🏆','🎯','💪','🙌','👍','✌️','🤙','💯',
  '🍓','🍕','☕','🍦','🎂','🎁','📸','💻','🚀','🌍',
];
