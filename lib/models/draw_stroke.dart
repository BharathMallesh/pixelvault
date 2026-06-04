import 'package:flutter/material.dart';

class DrawPoint {
  final double x; // normalized 0.0–1.0
  final double y;
  const DrawPoint(this.x, this.y);
}

class DrawStroke {
  final String id;
  final List<DrawPoint> points;
  final Color color;
  final double width;
  final bool isEraser;

  const DrawStroke({
    required this.id, required this.points,
    this.color = Colors.white, this.width = 4.0, this.isEraser = false,
  });

  DrawStroke copyWith({List<DrawPoint>? points, Color? color, double? width, bool? isEraser}) {
    return DrawStroke(
      id: id, points: points ?? this.points,
      color: color ?? this.color, width: width ?? this.width,
      isEraser: isEraser ?? this.isEraser,
    );
  }
}
