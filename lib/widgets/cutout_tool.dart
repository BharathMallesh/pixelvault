import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';
import '../theme/app_theme.dart';
import '../utils/ai_service.dart';
import '../utils/cutout_engine.dart';
import '../utils/photo_saver.dart';
import '../utils/database_helper.dart';
import '../providers/editor_provider.dart';

/// On-device AI cutout: detects the subject and either saves it on a
/// transparent background or keeps it sharp while blurring the background.
/// Runs entirely offline (no network), so it works regardless of the online-AI
/// opt-in toggle. The heavy segmentation runs on a background isolate.
class CutoutToolPanel extends ConsumerStatefulWidget {
  final String assetId;
  const CutoutToolPanel({super.key, required this.assetId});

  @override
  ConsumerState<CutoutToolPanel> createState() => _CutoutToolPanelState();
}

class _CutoutToolPanelState extends ConsumerState<CutoutToolPanel> {
  bool _busy = false;
  String? _status;
  CutoutResult? _matte;
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
      if (!mounted) return;
      setState(() {
        _matte = matte;
        _status = 'Subject detected — choose an output below';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Cutout failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({required bool transparent}) async {
    final matte = _matte;
    final bytes = _originBytes;
    if (matte == null || bytes == null) return;
    setState(() {
      _busy = true;
      _status = transparent ? 'Cutting out…' : 'Blurring background…';
    });
    try {
      if (!await PhotoSaver.ensureAccess()) {
        setState(() => _status = 'Gallery permission denied');
        return;
      }
      final Uint8List out = transparent
          ? await CutoutEngine.applyTransparent(bytes, matte)
          : await CutoutEngine.applyBackgroundBlur(bytes, matte);
      await PhotoSaver.saveBytes(out, asPng: transparent);
      try {
        await DatabaseHelper()
            .saveEditHistory(widget.assetId, ref.read(editorProvider).current);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(transparent
            ? '✓ Cutout saved (transparent PNG) to the "PixelVault" album'
            : '✓ Background blur saved to the "PixelVault" album'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
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
    final hasMatte = _matte != null;
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined,
                  size: 16, color: AppTheme.primaryLight),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('AI Cutout · runs on-device, fully offline',
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
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _save(transparent: true),
                    icon: const Icon(Icons.layers_clear_outlined, size: 18),
                    label: const Text('Transparent'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _save(transparent: false),
                    icon: const Icon(Icons.lens_blur_outlined, size: 18),
                    label: const Text('Blur BG'),
                  ),
                ),
              ],
            ),
          if (hasMatte && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: () => setState(() {
                  _matte = null;
                  _status = null;
                }),
                child: const Text('Re-detect', style: TextStyle(fontSize: 12)),
              ),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_status!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ),
        ],
      ),
    );
  }
}
