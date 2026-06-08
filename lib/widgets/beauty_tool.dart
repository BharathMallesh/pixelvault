import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';
import '../theme/app_theme.dart';
import '../utils/face_detector.dart';
import '../utils/beauty_ops.dart';
import '../utils/photo_saver.dart';
import '../utils/database_helper.dart';
import '../providers/editor_provider.dart';

/// Phase 9 — portrait beauty retouch. Detects a face on-device (model-free
/// classical detector today; TFLite landmark model is a drop-in upgrade), then
/// applies skin smooth / teeth whiten / eye brighten within the face region.
/// All offline. Saves to the gallery.
class BeautyToolPanel extends ConsumerStatefulWidget {
  final String assetId;
  const BeautyToolPanel({super.key, required this.assetId});

  @override
  ConsumerState<BeautyToolPanel> createState() => _BeautyToolPanelState();
}

class _BeautyToolPanelState extends ConsumerState<BeautyToolPanel> {
  bool _busy = false;
  String? _status;
  Uint8List? _originBytes;
  Face? _face;

  double _smooth = 0.5;
  double _teeth = 0.0;
  double _eyes = 0.3;
  double _lip = 0.0;
  double _blush = 0.0;

  Future<Uint8List?> _loadOrigin() async {
    if (_originBytes != null) return _originBytes;
    final asset = await AssetEntity.fromId(widget.assetId);
    _originBytes = await asset?.originBytes;
    return _originBytes;
  }

  Future<void> _detect() async {
    setState(() {
      _busy = true;
      _status = 'Detecting face…';
    });
    try {
      final bytes = await _loadOrigin();
      if (bytes == null) throw Exception('Could not read photo data');
      final face = await const FaceDetector().detect(bytes);
      if (!mounted) return;
      setState(() {
        _face = face;
        _status = face == null
            ? 'No face detected — try a clearer portrait'
            : 'Face detected — adjust and save';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Detection failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final face = _face;
    final bytes = _originBytes;
    if (face == null || bytes == null) return;
    setState(() {
      _busy = true;
      _status = 'Applying retouch…';
    });
    try {
      if (!await PhotoSaver.ensureAccess()) {
        setState(() => _status = 'Gallery permission denied');
        return;
      }
      final out = await applyBeauty(BeautyJob(
        bytes: bytes,
        face: face,
        smooth: _smooth,
        teeth: _teeth,
        eyes: _eyes,
        lip: _lip,
        blush: _blush,
      ));
      await PhotoSaver.saveBytes(out, asPng: false);
      try {
        await DatabaseHelper()
            .saveEditHistory(widget.assetId, ref.read(editorProvider).current);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Retouch saved to the "PixelVault" album'),
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
    final hasFace = _face != null;
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
                Icon(Icons.face_retouching_natural,
                    size: 16, color: AppTheme.primaryLight),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Beauty · on-device face detection, offline',
                      style: TextStyle(fontSize: 11, color: Colors.white54)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasFace)
              FilledButton.icon(
                onPressed: _busy ? null : _detect,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.face_outlined),
                label: Text(_busy ? 'Working…' : 'Detect face'),
              )
            else ...[
              _slider('Skin smooth', _smooth, (v) => setState(() => _smooth = v)),
              _slider('Teeth whiten', _teeth, (v) => setState(() => _teeth = v)),
              _slider('Eye brighten', _eyes, (v) => setState(() => _eyes = v)),
              _slider('Lip tint', _lip, (v) => setState(() => _lip = v)),
              _slider('Cheek blush', _blush, (v) => setState(() => _blush = v)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Apply & save'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _face = null;
                          _status = null;
                        }),
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

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
            width: 84,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.white60))),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 1,
            activeColor: AppTheme.primary,
            onChanged: _busy ? null : onChanged,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text('${(value * 100).round()}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ),
      ],
    );
  }
}
