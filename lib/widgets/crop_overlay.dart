import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor_provider.dart';
import '../models/edit_settings.dart';
import '../theme/app_theme.dart';

/// Interactive crop rectangle drawn over the photo. Drag the corner handles to
/// resize, or the interior to move. The selection is stored as a normalized
/// [CropRect] (0..1) in the editor settings, which the processor applies.
///
/// [aspectRatio] of 0 = free; otherwise width/height is locked to that ratio.
class CropOverlay extends ConsumerWidget {
  final Size canvasSize;
  final double aspectRatio;
  const CropOverlay({super.key, required this.canvasSize, required this.aspectRatio});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(editorProvider.select((s) => s.current.cropRect));
    const initial = CropRect(left: 0.05, top: 0.05, right: 0.95, bottom: 0.95);
    // Seed a starting crop box the first time the tool is opened so there is
    // something to drag (without adding an undo step).
    if (stored == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(editorProvider.notifier).setCropLive(initial);
      });
    }
    final crop = stored ?? initial;
    return _CropEditor(
      canvasSize: canvasSize,
      aspectRatio: aspectRatio,
      crop: crop,
      onChanged: (c) => ref.read(editorProvider.notifier).setCropLive(c),
      onChangeEnd: () => ref.read(editorProvider.notifier).commitHistory(),
    );
  }
}

enum _Handle { none, move, tl, tr, bl, br }

class _CropEditor extends StatefulWidget {
  final Size canvasSize;
  final double aspectRatio;
  final CropRect crop;
  final ValueChanged<CropRect> onChanged;
  final VoidCallback onChangeEnd;
  const _CropEditor({
    required this.canvasSize,
    required this.aspectRatio,
    required this.crop,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<_CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<_CropEditor> {
  _Handle _active = _Handle.none;
  static const double _hit = 28; // px hit-radius for corner handles
  static const double _minSize = 0.08; // min crop fraction

  CropRect get _c => widget.crop;
  double get _w => widget.canvasSize.width;
  double get _h => widget.canvasSize.height;

  Offset _px(double nx, double ny) => Offset(nx * _w, ny * _h);

  _Handle _hitTest(Offset p) {
    final corners = {
      _Handle.tl: _px(_c.left, _c.top),
      _Handle.tr: _px(_c.right, _c.top),
      _Handle.bl: _px(_c.left, _c.bottom),
      _Handle.br: _px(_c.right, _c.bottom),
    };
    for (final e in corners.entries) {
      if ((p - e.value).distance <= _hit) return e.key;
    }
    final rect = Rect.fromLTRB(
        _c.left * _w, _c.top * _h, _c.right * _w, _c.bottom * _h);
    if (rect.contains(p)) return _Handle.move;
    return _Handle.none;
  }

  void _onStart(DragStartDetails d) {
    _active = _hitTest(d.localPosition);
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_active == _Handle.none) return;
    final dx = d.delta.dx / _w;
    final dy = d.delta.dy / _h;
    double l = _c.left, t = _c.top, r = _c.right, b = _c.bottom;

    switch (_active) {
      case _Handle.move:
        final cw = r - l, ch = b - t;
        l = (l + dx).clamp(0.0, 1 - cw);
        t = (t + dy).clamp(0.0, 1 - ch);
        r = l + cw;
        b = t + ch;
        break;
      case _Handle.tl:
        l = (l + dx).clamp(0.0, r - _minSize);
        t = (t + dy).clamp(0.0, b - _minSize);
        break;
      case _Handle.tr:
        r = (r + dx).clamp(l + _minSize, 1.0);
        t = (t + dy).clamp(0.0, b - _minSize);
        break;
      case _Handle.bl:
        l = (l + dx).clamp(0.0, r - _minSize);
        b = (b + dy).clamp(t + _minSize, 1.0);
        break;
      case _Handle.br:
        r = (r + dx).clamp(l + _minSize, 1.0);
        b = (b + dy).clamp(t + _minSize, 1.0);
        break;
      case _Handle.none:
        return;
    }

    // Lock aspect ratio (in pixel space) by adjusting the moved edge.
    if (widget.aspectRatio > 0 && _active != _Handle.move) {
      final targetWpx = (r - l) * _w;
      final neededHpx = targetWpx / widget.aspectRatio;
      final neededH = (neededHpx / _h).clamp(_minSize, 1.0);
      if (_active == _Handle.tl || _active == _Handle.tr) {
        t = (b - neededH).clamp(0.0, b - _minSize);
      } else {
        b = (t + neededH).clamp(t + _minSize, 1.0);
      }
    }

    widget.onChanged(CropRect(left: l, top: t, right: r, bottom: b));
  }

  void _onEnd(DragEndDetails d) {
    if (_active != _Handle.none) widget.onChangeEnd();
    _active = _Handle.none;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onStart,
      onPanUpdate: _onUpdate,
      onPanEnd: _onEnd,
      child: CustomPaint(
        painter: _CropPainter(_c),
        size: Size.infinite,
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final CropRect c;
  _CropPainter(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
        c.left * size.width, c.top * size.height,
        c.right * size.width, c.bottom * size.height);

    // Dim everything outside the crop rect.
    final dim = Paint()..color = Colors.black.withOpacity(0.55);
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(rect);
    canvas.drawPath(
        Path.combine(PathOperation.difference, outer, inner), dim);

    // Border
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, border);

    // Rule-of-thirds grid
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1;
    for (int i = 1; i < 3; i++) {
      final dx = rect.left + rect.width * i / 3;
      final dy = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(dx, rect.top), Offset(dx, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, dy), Offset(rect.right, dy), grid);
    }

    // Corner handles
    final handle = Paint()..color = AppTheme.primaryLight;
    const hs = 7.0;
    for (final corner in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      canvas.drawCircle(corner, hs, handle);
      canvas.drawCircle(corner, hs, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.c != c;
}
