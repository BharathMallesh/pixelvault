/// A single circular brush "dab" in normalized image coordinates.
/// x, y and radius are fractions of the image width (0.0–1.0) so the mask is
/// resolution-independent and can be rasterized at any output size.
class BrushDab {
  final double x;
  final double y;
  final double radius; // fraction of image width
  const BrushDab({required this.x, required this.y, required this.radius});

  Map<String, double> toMap() => {'x': x, 'y': y, 'r': radius};
  static BrushDab fromMap(Map<String, dynamic> m) => BrushDab(
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        radius: (m['r'] as num).toDouble(),
      );
}

/// A painted region built from many dabs. Used by the healing brush, the
/// background-blur focus mask, and the selective-edit brush.
class BrushMask {
  final List<BrushDab> dabs;
  const BrushMask({this.dabs = const []});

  bool get isEmpty => dabs.isEmpty;
  bool get isNotEmpty => dabs.isNotEmpty;

  BrushMask add(BrushDab dab) => BrushMask(dabs: [...dabs, dab]);
  BrushMask clear() => const BrushMask();
}
