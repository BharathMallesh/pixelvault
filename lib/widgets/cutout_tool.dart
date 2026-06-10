import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../utils/ai_service.dart';
import '../utils/cutout_engine.dart';
import '../utils/matte_ops.dart';
import '../utils/photo_saver.dart';
import '../utils/database_helper.dart';
import '../providers/editor_provider.dart';
import '../providers/matte_provider.dart';

/// On-device AI cutout (Phase 5) + matte refine & background replace (Phase 7).
/// Detection runs offline on a background isolate. After detecting, the user
/// can refine the matte (brush add/erase, feather, edge shift) and either save
/// a transparent PNG, blur the background, or replace the background with a
/// solid colour / gradient / chosen photo.
class CutoutToolPanel extends ConsumerStatefulWidget {
  final String assetId;
  const CutoutToolPanel({super.key, required this.assetId});

  @override
  ConsumerState<CutoutToolPanel> createState() => _CutoutToolPanelState();
}

class _CutoutToolPanelState extends ConsumerState<CutoutToolPanel> {
  bool _busy = false;
  String? _status;
  Uint8List? _originBytes;

  Future<Uint8List?> _loadOrigin() async {
    if (_originBytes != null) return _originBytes;
    final asset = await AssetEntity.fromId(widget.assetId);
    _originBytes = await asset?.originBytes;
    return _originBytes;
  }

  Future<void> _detect() async {
    setState(() {
      _busy = true;
      _status = 'Detecting subject…';
    });
    try {
      final bytes = await _loadOrigin();
      if (bytes == null) throw Exception('Could not read photo data');
      final matte = await const AiService().removeBackground(bytes);
      ref.read(matteEditProvider.notifier).setBase(matte);
      final usingMl = await CutoutEngine.mlAvailable;
      if (!mounted) return;
      setState(() => _status = usingMl
          ? '✓ Detected with on-device ML model — refine or pick an output'
          : 'Detected (classical) — refine or pick an output');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Cutout failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveTransparent() => _run('Cutting out…', (bytes, matte) =>
      CutoutEngine.applyTransparent(bytes, matte), asPng: true);

  Future<void> _saveBlur() => _run('Blurring background…', (bytes, matte) =>
      CutoutEngine.applyBackgroundBlur(bytes, matte));

  Future<void> _saveBg(BgKind kind,
      {List<int> color = const [255, 255, 255], Uint8List? bgBytes}) {
    return _run('Replacing background…', (bytes, matte) {
      return replaceBackground(BgReplaceRequest(
        photoBytes: bytes,
        matte: matte,
        kind: kind,
        color: color,
        bgBytes: bgBytes,
      ));
    });
  }

  /// Shared save runner: builds the final (refined) matte, runs [op], writes.
  Future<void> _run(
    String working,
    Future<Uint8List> Function(Uint8List bytes, CutoutResult matte) op, {
    bool asPng = false,
  }) async {
    final matte = ref.read(matteEditProvider).buildFinal();
    final bytes = _originBytes;
    if (matte == null || bytes == null) return;
    setState(() {
      _busy = true;
      _status = working;
    });
    try {
      if (!await PhotoSaver.ensureAccess()) {
        setState(() => _status = 'Gallery permission denied');
        return;
      }
      final out = await op(bytes, matte);
      await PhotoSaver.saveBytes(out, asPng: asPng);
      try {
        await DatabaseHelper()
            .saveEditHistory(widget.assetId, ref.read(editorProvider).current);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Saved to the "PixelVault" album'),
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

  Future<void> _pickBgPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await _saveBg(BgKind.photo, bgBytes: bytes);
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not load background: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final matte = ref.watch(matteEditProvider);
    final mn = ref.read(matteEditProvider.notifier);
    final hasMatte = matte.hasMatte;

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: const [
                Icon(Icons.auto_awesome_outlined,
                    size: 16, color: AppTheme.primaryLight),
                SizedBox(width: 6),
                Expanded(
                  child: Text('AI Cutout · on-device, fully offline',
                      style: TextStyle(fontSize: 11, color: Colors.white54)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasMatte)
              FilledButton.icon(
                onPressed: _busy ? null : _detect,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.center_focus_strong_outlined),
                label: Text(_busy ? 'Working…' : 'Detect subject'),
              )
            else ...[
              _refineControls(matte, mn),
              const Divider(color: Colors.white12, height: 22),
              _outputControls(),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        mn.reset();
                        setState(() => _status = null);
                      },
                child: const Text('Re-detect', style: TextStyle(fontSize: 12)),
              ),
            ],
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _refineControls(MatteEditState m, MatteEditNotifier mn) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Refine edges',
            style: TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 6),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Add', style: TextStyle(fontSize: 12)),
              selected: m.brushAdd,
              onSelected: (_) => mn.setBrushAdd(true),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Erase', style: TextStyle(fontSize: 12)),
              selected: !m.brushAdd,
              onSelected: (_) => mn.setBrushAdd(false),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Undo refine stroke',
              onPressed: m.dabs.isEmpty ? null : mn.undoDab,
              icon: const Icon(Icons.undo, size: 18, color: Colors.white70),
            ),
          ],
        ),
        _slider('Brush size', m.brushRadius, 0.01, 0.2,
            (v) => mn.setBrushRadius(v)),
        _slider('Edge shift', (m.edgeShift + 1) / 2, 0, 1,
            (v) => mn.setEdgeShift(v * 2 - 1)),
        _slider('Feather', m.featherRadius / 10, 0, 1,
            (v) => mn.setFeather((v * 10).round())),
        const Text('Tip: brush on the photo above to add/erase the subject.',
            style: TextStyle(fontSize: 10, color: Colors.white38)),
      ],
    );
  }

  Widget _outputControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Output',
            style: TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _saveTransparent,
                icon: const Icon(Icons.layers_clear_outlined, size: 18),
                label: const Text('Transparent'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _saveBlur,
                icon: const Icon(Icons.lens_blur_outlined, size: 18),
                label: const Text('Blur BG'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Replace background',
            style: TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _bgSwatches)
              GestureDetector(
                onTap: _busy ? null : () => _saveBg(BgKind.solid, color: c.rgb),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, c.rgb[0], c.rgb[1], c.rgb[2]),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
              ),
            // Gradient (sky blue -> white)
            GestureDetector(
              onTap: _busy
                  ? null
                  : () => _saveBg(BgKind.gradient,
                      color: const [120, 180, 255, 255, 255, 255]),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF78B4FF), Colors.white],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ),
            // Photo background
            GestureDetector(
              onTap: _busy ? null : _pickBgPhoto,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.add_photo_alternate_outlined,
                    size: 16, color: Colors.white54),
              ),
            ),
          ],
        ),
      ],
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

class _Swatch {
  final List<int> rgb;
  const _Swatch(this.rgb);
}

const _bgSwatches = [
  _Swatch([255, 255, 255]),
  _Swatch([0, 0, 0]),
  _Swatch([230, 230, 230]),
  _Swatch([255, 80, 80]),
  _Swatch([80, 160, 255]),
  _Swatch([80, 200, 120]),
  _Swatch([255, 200, 60]),
];
