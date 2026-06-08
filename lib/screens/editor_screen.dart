import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';
import '../providers/editor_provider.dart';
import '../theme/app_theme.dart';
import '../utils/photo_saver.dart';
import '../utils/image_processor.dart';
import '../utils/overlay_compositor.dart';
import '../utils/database_helper.dart';
import 'settings_screen.dart';
import '../widgets/adjustment_slider.dart';
import '../widgets/filter_strip.dart';
import '../widgets/hsl_panel.dart';
import '../widgets/curves_tool.dart';
import '../widgets/crop_tool.dart';
import '../widgets/crop_overlay.dart';
import '../widgets/heal_tool.dart';
import '../widgets/perspective_tool.dart';
import '../widgets/blur_tool.dart';
import '../widgets/selective_tool.dart';
import '../widgets/cutout_tool.dart';
import '../widgets/cutout_refine_overlay.dart';
import '../widgets/effects_tool.dart';
import '../widgets/beauty_tool.dart';
import '../providers/matte_provider.dart';
import '../widgets/text_tool.dart';
import '../widgets/draw_tool.dart';
import '../widgets/sticker_tool.dart';
import '../widgets/bridged_layer_panel.dart';
import '../providers/layer_bridge.dart';
import 'presets_screen.dart';

// Expose EditSettings for _AdjustPanel
import '../models/edit_settings.dart';

class EditorScreen extends ConsumerStatefulWidget {
  final String assetId;
  const EditorScreen({super.key, required this.assetId});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  // Wraps the photo + overlay stack so we can rasterize text/draw/stickers
  // into the saved image. Without this, overlays were preview-only.
  final GlobalKey _captureKey = GlobalKey();
  // The preview area size overlays were laid out in (for full-res compositing).
  Size _canvasSize = Size.zero;
  // Whether the Layers panel is shown (Phase 6.5 bridge).
  bool _showLayers = false;

  @override
  void initState() {
    super.initState();
    // Overlays (text/draw/stickers) live in global providers, so clear any
    // left over from a previously edited photo — otherwise they'd bleed onto
    // this photo and into its saved output.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(textOverlaysProvider.notifier).state = [];
      ref.read(selectedTextIdProvider.notifier).state = null;
      ref.read(stickerOverlaysProvider.notifier).state = [];
      ref.read(selectedStickerIdProvider.notifier).state = null;
      ref.read(drawStrokesProvider.notifier).state = [];
      ref.read(activeDrawStrokeProvider.notifier).state = null;
      ref.read(groupVisibilityProvider.notifier).reset();
      ref.read(matteEditProvider.notifier).reset();

      // Restore the most recent saved edit for this photo, if any.
      final restored = await DatabaseHelper().getLastEdit(widget.assetId);
      if (!mounted) return;
      ref.read(editorProvider.notifier)
          .loadPhoto(widget.assetId, restored: restored);
    });
  }

  bool get _hasOverlays =>
      ref.read(textOverlaysProvider).isNotEmpty ||
      ref.read(stickerOverlaysProvider).isNotEmpty ||
      ref.read(drawStrokesProvider).isNotEmpty;


  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(state, n),
      body: Column(
        children: [
          // ── Photo + overlay canvases ─────────────────────────────
          Expanded(
            child: LayoutBuilder(builder: (ctx, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              _canvasSize = size;
              return RepaintBoundary(
                key: _captureKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Base photo
                    GestureDetector(
                      onLongPressStart: (_) => n.toggleBeforeAfter(true),
                      onLongPressEnd: (_) => n.toggleBeforeAfter(false),
                      child: _PhotoPreview(
                          assetId: widget.assetId, showBefore: state.showBeforeAfter),
                    ),
                    // Draw canvas
                    if (state.activeTool == EditorTool.draw)
                      DrawCanvas(canvasSize: size),
                    // Heal overlay
                    if (state.activeTool == EditorTool.heal)
                      HealToolOverlay(imageSize: size),
                    // Background-blur focus brush overlay
                    if (state.activeTool == EditorTool.blur)
                      FocusToolOverlay(imageSize: size),
                    // Selective edit brush overlay
                    if (state.activeTool == EditorTool.selective)
                      SelectiveToolOverlay(imageSize: size),
                    // Cutout matte refine brush overlay
                    if (state.activeTool == EditorTool.cutout)
                      CutoutRefineOverlay(canvasSize: size),
                    // Interactive crop rectangle
                    if (state.activeTool == EditorTool.crop)
                      CropOverlay(
                        canvasSize: size,
                        aspectRatio: ref.watch(cropAspectRatioProvider),
                      ),
                    // Sticker overlays (hidden if the Stickers layer is off)
                    if (ref.watch(groupVisibilityProvider).sticker)
                      StickerCanvas(canvasSize: size),
                    // Text overlays (hidden if the Text layer is off)
                    if (ref.watch(groupVisibilityProvider).text)
                      TextOverlayCanvas(canvasSize: size),
                  ],
                ),
              );
            }),
          ),

          // Before/after bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: state.showBeforeAfter ? 26 : 0,
            color: Colors.black,
            child: const Center(
              child: Text('ORIGINAL',
                  style: TextStyle(color: Colors.white60, fontSize: 10,
                      letterSpacing: 2, fontWeight: FontWeight.w600)),
            ),
          ),

          // Filter strip (only for filter/adjust tabs)
          if (_showFilterStrip(state.activeTool))
            FilterStrip(
              activeFilterId: state.current.activeFilter ?? 'original',
              assetId: widget.assetId,
              onFilterSelected: (f) => n.applyFilter(f.id, f.settings),
            ),

          // Layers panel (Phase 6.5 bridge) — toggled from the app bar.
          if (_showLayers) const BridgedLayerPanel(),

          // Tool area
          Container(
            color: AppTheme.toolbarBg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolTabBar(active: state.activeTool, onTap: n.setTool),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _ToolPanel(
                      key: ValueKey(state.activeTool),
                      tool: state.activeTool,
                      assetId: widget.assetId),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _showFilterStrip(EditorTool tool) =>
      tool == EditorTool.filter || tool == EditorTool.adjust;

  AppBar _buildAppBar(EditorState state, EditorNotifier n) {
    return AppBar(
      backgroundColor: AppTheme.toolbarBg,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new),
        onPressed: () => _confirmExit(state),
      ),
      title: Text(_toolLabel(state.activeTool),
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      actions: [
        // Layers panel toggle (Phase 6.5 bridge)
        IconButton(
          icon: const Icon(Icons.layers_outlined, size: 20),
          color: _showLayers ? AppTheme.primaryLight : Colors.white70,
          tooltip: 'Layers',
          onPressed: () => setState(() => _showLayers = !_showLayers),
        ),
        // Presets button
        IconButton(
          icon: const Icon(Icons.bookmarks_outlined, size: 19),
          color: Colors.white70,
          tooltip: 'My Presets',
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const PresetsScreen())),
        ),
        IconButton(
          icon: const Icon(Icons.undo),
          onPressed: state.canUndo ? n.undo : null,
          color: state.canUndo ? Colors.white : Colors.white24,
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          onPressed: state.canRedo ? n.redo : null,
          color: state.canRedo ? Colors.white : Colors.white24,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: state.current.isDefault ? null : n.resetAll,
          color: state.current.isDefault ? Colors.white24 : Colors.white,
        ),
        state.isSaving
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                    child: SizedBox(width: 17, height: 17,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))),
              )
            : TextButton(
                onPressed: _savePhoto,
                child: const Text('Save',
                    style: TextStyle(
                        color: AppTheme.primaryLight,
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
      ],
    );
  }

  String _toolLabel(EditorTool tool) {
    switch (tool) {
      case EditorTool.filter:      return 'Filters';
      case EditorTool.adjust:      return 'Adjust';
      case EditorTool.hsl:         return 'Color (HSL)';
      case EditorTool.curves:      return 'Curves';
      case EditorTool.crop:        return 'Crop & Rotate';
      case EditorTool.heal:        return 'Healing Brush';
      case EditorTool.perspective: return 'Perspective';
      case EditorTool.blur:        return 'Background Blur';
      case EditorTool.selective:   return 'Selective Edit';
      case EditorTool.cutout:      return 'AI Cutout';
      case EditorTool.beauty:      return 'Beauty Retouch';
      case EditorTool.effects:     return 'Frames & Effects';
      case EditorTool.text:        return 'Add Text';
      case EditorTool.draw:        return 'Draw';
      case EditorTool.sticker:     return 'Stickers';
    }
  }

  Future<void> _savePhoto() async {
    final n = ref.read(editorProvider.notifier);
    final settings = ref.read(editorProvider).current;
    final appSettings = ref.read(settingsProvider);
    final hasOverlays = _hasOverlays;

    n.setSaving(true);
    try {
      // Ensure gallery write access before spending time on processing.
      if (!await PhotoSaver.ensureAccess()) {
        _showError('Gallery permission denied — cannot save photo');
        return;
      }

      if (hasOverlays) {
        // Process the photo at full resolution (off the UI thread), then burn
        // the text/draw/sticker overlays in at that same full resolution — no
        // longer a screen-resolution screenshot.
        final asset = await AssetEntity.fromId(widget.assetId);
        final origin = await asset?.originBytes;
        if (origin == null) throw Exception('Could not read photo data');
        final processed = await ImageProcessor.processBytesIsolated(
          inputBytes: origin, settings: settings, jpegQuality: appSettings.jpegQuality,
        );
        // Honor per-group visibility from the Layers panel.
        final vis = ref.read(groupVisibilityProvider);
        final composite = await OverlayCompositor.compose(
          photoBytes: processed,
          canvasSize: _canvasSize,
          strokes: vis.draw ? ref.read(drawStrokesProvider) : const [],
          texts: vis.text ? ref.read(textOverlaysProvider) : const [],
          stickers: vis.sticker ? ref.read(stickerOverlaysProvider) : const [],
        );
        await PhotoSaver.saveBytes(composite, asPng: true);
        // Record history so this photo shows in the "Edited" tab.
        try { await DatabaseHelper().saveEditHistory(widget.assetId, settings); }
        catch (_) {}
      } else {
        // No overlays: full-resolution pipeline straight from the original.
        await PhotoSaver.processAndSaveAsset(
          assetId: widget.assetId,
          settings: settings,
          exportFormat: appSettings.exportFormat,
          jpegQuality: appSettings.jpegQuality,
        );
      }

      if (mounted) {
        final fmt = appSettings.exportFormat.toUpperCase();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ Saved as $fmt to the "PixelVault" album in your gallery'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ));
        Navigator.pop(context);
      }
    } on GalException catch (e) {
      _showError('Could not save: ${e.type.message}');
    } catch (e) {
      _showError('Could not save: $e');
    } finally {
      if (mounted) n.setSaving(false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _confirmExit(EditorState state) async {
    if (state.current.isDefault) { Navigator.pop(context); return; }
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Exit without saving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (result == true && mounted) Navigator.pop(context);
  }
}

// ── Photo Preview ──────────────────────────────────────────────────
// Shows a LIVE preview of the current edit. It loads a downscaled copy of the
// asset once, then re-runs the real ImageProcessor pipeline (off the UI thread)
// whenever the edit settings change, so filters/adjustments are visible before
// saving. Holding (showBefore) reveals the untouched original.

class _PhotoPreview extends ConsumerStatefulWidget {
  final String assetId;
  final bool showBefore;
  const _PhotoPreview({required this.assetId, required this.showBefore});

  @override
  ConsumerState<_PhotoPreview> createState() => _PhotoPreviewState();
}

class _PhotoPreviewState extends ConsumerState<_PhotoPreview> {
  Uint8List? _baseBytes;   // downscaled original, loaded once
  Uint8List? _original;    // same, shown for before/after
  Uint8List? _preview;     // latest processed result
  EditSettings? _lastSettings;
  bool _processing = false;
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  Future<void> _loadBase() async {
    final asset = await AssetEntity.fromId(widget.assetId);
    if (asset == null) return;
    // Publish the real image aspect ratio so the crop overlay can map its
    // rectangle to the letterboxed photo rect (BoxFit.contain).
    if (asset.width > 0 && asset.height > 0) {
      ref.read(editorImageAspectProvider.notifier).state =
          asset.width / asset.height;
    }
    // A ~1280px thumbnail keeps preview processing fast and responsive.
    final bytes = await asset.thumbnailDataWithSize(
        const ThumbnailSize(1280, 1280), quality: 90);
    if (!mounted || bytes == null) return;
    setState(() {
      _baseBytes = bytes;
      _original = bytes;
      _preview = bytes;
    });
    _reprocess(ref.read(editorProvider).current);
  }

  Future<void> _reprocess(EditSettings settings) async {
    if (_baseBytes == null) return;
    if (settings.isDefault) {
      // Nothing to apply — show the original directly.
      if (mounted) setState(() => _preview = _original);
      _lastSettings = settings;
      return;
    }
    if (_processing) { _queued = true; return; }
    _processing = true;
    _lastSettings = settings;
    try {
      final out = await ImageProcessor.processBytes(
          inputBytes: _baseBytes!, settings: settings);
      if (mounted) setState(() => _preview = out);
    } catch (_) {
      // Keep showing the last good preview on a transient error.
    } finally {
      _processing = false;
      if (_queued) {
        _queued = false;
        final latest = ref.read(editorProvider).current;
        if (latest != _lastSettings) _reprocess(latest);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-run the pipeline whenever the current settings change.
    final settings = ref.watch(editorProvider.select((s) => s.current));
    if (_baseBytes != null && settings != _lastSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reprocess(settings));
    }

    if (_preview == null) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white38));
    }
    final shown = widget.showBefore ? _original! : _preview!;
    return Stack(fit: StackFit.expand, children: [
      InteractiveViewer(child: Image.memory(shown, fit: BoxFit.contain,
          gaplessPlayback: true)),
    ]);
  }
}

// ── Tool Tab Bar ───────────────────────────────────────────────────

class _ToolTabBar extends StatelessWidget {
  final EditorTool active;
  final void Function(EditorTool) onTap;
  const _ToolTabBar({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tools = [
      (EditorTool.filter,      Icons.auto_awesome_outlined,  'Filter'),
      (EditorTool.adjust,      Icons.tune_outlined,          'Adjust'),
      (EditorTool.hsl,         Icons.palette_outlined,       'Color'),
      (EditorTool.curves,      Icons.show_chart,             'Curves'),
      (EditorTool.crop,        Icons.crop_outlined,          'Crop'),
      (EditorTool.heal,        Icons.healing_outlined,       'Heal'),
      (EditorTool.perspective, Icons.grid_3x3_outlined,      'Persp.'),
      (EditorTool.blur,        Icons.lens_blur_outlined,     'Blur'),
      (EditorTool.selective,   Icons.gesture_outlined,       'Select'),
      (EditorTool.cutout,      Icons.auto_awesome_outlined,  'Cutout'),
      (EditorTool.beauty,      Icons.face_retouching_natural,'Beauty'),
      (EditorTool.effects,     Icons.filter_frames_outlined, 'Frames'),
      (EditorTool.text,        Icons.text_fields_outlined,   'Text'),
      (EditorTool.draw,        Icons.brush_outlined,         'Draw'),
      (EditorTool.sticker,     Icons.emoji_emotions_outlined,'Sticker'),
    ];

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: tools.map((t) {
          final isActive = t.$1 == active;
          return GestureDetector(
            onTap: () => onTap(t.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: isActive ? AppTheme.toolbarSelected : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Icon(t.$2, size: 14,
                    color: isActive ? Colors.white : Colors.white54),
                const SizedBox(width: 4),
                Text(t.$3, style: TextStyle(
                  fontSize: 11,
                  color: isActive ? Colors.white : Colors.white54,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                )),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Tool Panel switcher ────────────────────────────────────────────

class _ToolPanel extends ConsumerWidget {
  final EditorTool tool;
  final String assetId;
  const _ToolPanel({super.key, required this.tool, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    switch (tool) {
      case EditorTool.filter:      return const SizedBox(height: 6);
      case EditorTool.adjust:      return _AdjustPanel(s: state.current, n: n);
      case EditorTool.hsl:         return const HslPanel();
      case EditorTool.curves:      return const CurvesToolPanel();
      case EditorTool.crop:        return const CropToolPanel();
      case EditorTool.heal:        return const HealToolPanel();
      case EditorTool.perspective: return const PerspectiveToolPanel();
      case EditorTool.blur:        return const BlurToolPanel();
      case EditorTool.selective:   return const SelectiveToolPanel();
      case EditorTool.cutout:      return CutoutToolPanel(assetId: assetId);
      case EditorTool.beauty:      return BeautyToolPanel(assetId: assetId);
      case EditorTool.effects:     return const EffectsToolPanel();
      case EditorTool.text:        return const TextToolPanel();
      case EditorTool.draw:        return const DrawToolPanel();
      case EditorTool.sticker:     return const StickerToolPanel();
    }
  }
}

class _AdjustPanel extends StatelessWidget {
  final EditSettings s;
  final EditorNotifier n;
  const _AdjustPanel({required this.s, required this.n});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: const Color(0xFF1A1A1A),
      child: Column(children: [
        AdjustmentSlider(label: 'Brightness',   value: s.brightness,     onChanged: n.setBrightness),
        AdjustmentSlider(label: 'Contrast',     value: s.contrast,       onChanged: n.setContrast),
        AdjustmentSlider(label: 'Saturation',   value: s.saturation,     onChanged: n.setSaturation),
        AdjustmentSlider(label: 'Vibrance',     value: s.vibrance,       onChanged: n.setVibrance),
        AdjustmentSlider(label: 'Highlights',   value: s.highlights,     onChanged: n.setHighlights),
        AdjustmentSlider(label: 'Shadows',      value: s.shadows,        onChanged: n.setShadows),
        AdjustmentSlider(label: 'Warmth',       value: s.warmth,         onChanged: n.setWarmth),
        AdjustmentSlider(label: 'Sharpness',    value: s.sharpness,      onChanged: n.setSharpness),
        AdjustmentSlider(label: 'Clarity',      value: s.clarity,        onChanged: n.setClarity),
        AdjustmentSlider(label: 'Vignette',     value: s.vignette,       onChanged: n.setVignette, min: 0, max: 100),
        AdjustmentSlider(label: 'Dehaze',       value: s.dehaze,         onChanged: n.setDehaze),
        AdjustmentSlider(label: 'Noise Reduc.', value: s.noiseReduction, onChanged: n.setNoiseReduction),
      ]),
    );
  }
}
