import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';
import '../theme/app_theme.dart';
import '../utils/liquify_ops.dart';
import '../utils/photo_saver.dart';
import '../utils/database_helper.dart';
import '../providers/editor_provider.dart';
import 'crop_overlay.dart' show editorImageAspectProvider;

/// Phase 9.5 — liquify/reshape. The user picks a mode (push/bloat/pinch) and
/// brushes on the photo; strokes are recorded as normalized [WarpStroke]s and
/// applied to the full-res image on save (off the UI thread).
final liquifyStrokesProvider = StateProvider<List<WarpStroke>>((ref) => []);
final liquifyModeProvider = StateProvider<WarpMode>((ref) => WarpMode.push);
final liquifyRadiusProvider = StateProvider<double>((ref) => 0.12);
final liquifyStrengthProvider = StateProvider<double>((ref) => 0.5);

/// Overlay: records brush strokes onto liquifyStrokesProvider.
class LiquifyOverlay extends ConsumerStatefulWidget {
  final Size canvasSize;
  const LiquifyOverlay({super.key, required this.canvasSize});
  @override
  ConsumerState<LiquifyOverlay> createState() => _LiquifyOverlayState();
}

class _LiquifyOverlayState extends ConsumerState<LiquifyOverlay> {
  Offset? _last;

  Rect _photoRect(Size canvas, double? aspect) {
    if (aspect == null || aspect <= 0) return Offset.zero & canvas;
    final ca = canvas.width / canvas.height;
    double w, h;
    if (aspect > ca) {
      w = canvas.width;
      h = w / aspect;
    } else {
      h = canvas.height;
      w = h * aspect;
    }
    return Rect.fromLTWH((canvas.width - w) / 2, (canvas.height - h) / 2, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final aspect = ref.watch(editorImageAspectProvider);
    final rect = _photoRect(widget.canvasSize, aspect);
    final mode = ref.watch(liquifyModeProvider);
    final radius = ref.watch(liquifyRadiusProvider);
    final strength = ref.watch(liquifyStrengthProvider);

    void record(Offset pos, Offset delta) {
      if (!rect.contains(pos)) return;
      final nx = ((pos.dx - rect.left) / rect.width).clamp(0.0, 1.0);
      final ny = ((pos.dy - rect.top) / rect.height).clamp(0.0, 1.0);
      ref.read(liquifyStrokesProvider.notifier).state = [
        ...ref.read(liquifyStrokesProvider),
        WarpStroke(
          x: nx,
          y: ny,
          radius: radius,
          dx: delta.dx / rect.width,
          dy: delta.dy / rect.height,
          strength: strength,
          mode: mode,
        ),
      ];
    }

    return GestureDetector(
      onPanStart: (d) => _last = d.localPosition,
      onPanUpdate: (d) {
        final prev = _last ?? d.localPosition;
        record(d.localPosition, d.localPosition - prev);
        _last = d.localPosition;
      },
      onPanEnd: (_) => _last = null,
      child: CustomPaint(size: Size.infinite, painter: _LiquifyPainter(rect, radius)),
    );
  }
}

class _LiquifyPainter extends CustomPainter {
  final Rect rect;
  final double radius;
  _LiquifyPainter(this.rect, this.radius);
  @override
  void paint(Canvas canvas, Size size) {
    // Light hint of the brush footprint at the rect centre.
    final r = radius * (rect.width > rect.height ? rect.width : rect.height);
    canvas.drawCircle(
      rect.center,
      r,
      Paint()
        ..color = AppTheme.primary.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_LiquifyPainter old) => old.radius != radius;
}

/// Tool panel: mode + brush controls + apply/save.
class LiquifyToolPanel extends ConsumerStatefulWidget {
  final String assetId;
  const LiquifyToolPanel({super.key, required this.assetId});
  @override
  ConsumerState<LiquifyToolPanel> createState() => _LiquifyToolPanelState();
}

class _LiquifyToolPanelState extends ConsumerState<LiquifyToolPanel> {
  bool _busy = false;
  String? _status;

  Future<void> _save() async {
    final strokes = ref.read(liquifyStrokesProvider);
    if (strokes.isEmpty) {
      setState(() => _status = 'Brush on the photo first');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Reshaping…';
    });
    try {
      if (!await PhotoSaver.ensureAccess()) {
        setState(() => _status = 'Gallery permission denied');
        return;
      }
      final asset = await AssetEntity.fromId(widget.assetId);
      final bytes = await asset?.originBytes;
      if (bytes == null) throw Exception('Could not read photo data');
      final out = await applyLiquify(LiquifyJob(bytes: bytes, strokes: strokes));
      await PhotoSaver.saveBytes(out, asPng: false);
      try {
        await DatabaseHelper()
            .saveEditHistory(widget.assetId, ref.read(editorProvider).current);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Reshaped photo saved to the "PixelVault" album'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ));
      setState(() => _status = 'Saved to gallery');
    } on GalException catch (e) {
      setState(() => _status = 'Could not save: ${e.type.message}');
    } catch (e) {
      setState(() => _status = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(liquifyModeProvider);
    final radius = ref.watch(liquifyRadiusProvider);
    final strength = ref.watch(liquifyStrengthProvider);
    final count = ref.watch(liquifyStrokesProvider).length;

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final m in WarpMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      m == WarpMode.push
                          ? 'Push'
                          : m == WarpMode.bloat
                              ? 'Bloat'
                              : 'Pinch',
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: mode == m,
                    onSelected: (_) =>
                        ref.read(liquifyModeProvider.notifier).state = m,
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Undo stroke',
                onPressed: count == 0
                    ? null
                    : () => ref.read(liquifyStrokesProvider.notifier).state =
                        ref.read(liquifyStrokesProvider).sublist(0, count - 1),
                icon: const Icon(Icons.undo, size: 18, color: Colors.white70),
              ),
            ],
          ),
          _slider('Brush size', radius, 0.04, 0.3,
              (v) => ref.read(liquifyRadiusProvider.notifier).state = v),
          _slider('Strength', strength, 0.1, 1.0,
              (v) => ref.read(liquifyStrengthProvider.notifier).state = v),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(_busy ? 'Working…' : 'Apply & save'),
          ),
          if (count > 0)
            TextButton(
              onPressed: () =>
                  ref.read(liquifyStrokesProvider.notifier).state = [],
              child: const Text('Clear strokes', style: TextStyle(fontSize: 12)),
            ),
          const Text('Drag on the photo to push/reshape.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.white38)),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_status!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.white54))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: AppTheme.primary,
            onChanged: _busy ? null : onChanged,
          ),
        ),
      ],
    );
  }
}
