import 'package:flutter/material.dart';

enum TextAlignment2 { left, center, right }
enum TextStyle2 { normal, bold, italic, boldItalic }

class TextOverlay {
  final String id;
  final String text;
  final double fontSize;
  final Color color;
  final Color backgroundColor;
  final bool hasBackground;
  final TextAlignment2 alignment;
  final TextStyle2 style;
  final double x; // normalized 0.0–1.0
  final double y;
  final double rotation;
  final String fontFamily;

  const TextOverlay({
    required this.id,
    required this.text,
    this.fontSize = 24,
    this.color = Colors.white,
    this.backgroundColor = Colors.black,
    this.hasBackground = false,
    this.alignment = TextAlignment2.center,
    this.style = TextStyle2.bold,
    this.x = 0.5,
    this.y = 0.5,
    this.rotation = 0,
    this.fontFamily = 'Inter',
  });

  TextOverlay copyWith({
    String? id, String? text, double? fontSize,
    Color? color, Color? backgroundColor, bool? hasBackground,
    TextAlignment2? alignment, TextStyle2? style,
    double? x, double? y, double? rotation, String? fontFamily,
  }) {
    return TextOverlay(
      id: id ?? this.id, text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize, color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      hasBackground: hasBackground ?? this.hasBackground,
      alignment: alignment ?? this.alignment, style: style ?? this.style,
      x: x ?? this.x, y: y ?? this.y, rotation: rotation ?? this.rotation,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}
