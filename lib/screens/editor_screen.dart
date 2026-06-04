import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../providers/editor_provider.dart';
import '../theme/app_theme.dart';
import '../utils/photo_saver.dart';
import '../utils/database_helper.dart';
import 'settings_screen.dart';
import '../widgets/adjustment_slider.dart';
import '../widgets/filter_strip.dart';
import '../widgets/hsl_panel.dart';
import '../widgets/crop_tool.dart';
import '../widgets/heal_tool.dart';
import '../widgets/perspective_tool.dart';
import '../widgets/blur_tool.dart';
import '../widgets/selective_tool.dart';
import '../widgets/text_tool.dart';
import '../widgets/draw_tool.dart';
import '../widgets/sticker_tool.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Restore the most recent saved edit for this photo, if any.
      final restored = await DatabaseHelper().getLastEdit(widget.assetId);
      if (!mounted) return;
      ref.read(editorProvider.notifier)
          .loadPhoto(widget.assetId, restored: restored);
    });
  }

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
              return Stack(
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
                  // Text overlays (always visible)
                  TextOverlayCanvas(canvasSize: size),
                  // Sticker overlays (always visible)
                  StickerCanvas(canvasSize: size),
                ],
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
                      key: ValueKey(state.activeTool), tool: state.activeTool),
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
      case EditorTool.crop:        return 'Crop & Rotate';
      case EditorTool.heal:        return 'Healing Brush';
      case EditorTool.perspective: return 'Perspective';
      case EditorTool.blur:        return 'Background Blur';
      case EditorTool.selective:   return 'Selective Edit';
      case EditorTool.text:        return 'Add Text';
      case EditorTool.draw:        return 'Draw';
      case EditorTool.sticker:     return 'Stickers';
    }
  }

  Future<void> _savePhoto() async {
    final n = ref.read(editorProvider.notifier);
    final settings = ref.read(editorProvider).current;
    final appSettings = ref.read(settingsProvider);
    n.setSaving(true);
    try {
      // Ensure gallery write access before spending time on processing.
      if (!await PhotoSaver.ensureAccess()) {
        _showError('Gallery permission denied — cannot save photo');
        return;
      }

      // Process the original asset and write it to the gallery, honoring the
      // user's export format / JPEG quality from Settings.
      await PhotoSaver.processAndSaveAsset(
        assetId: widget.assetId,
        settings: settings,
        exportFormat: appSettings.exportFormat,
        jpegQuality: appSettings.jpegQuality,
      );

      if (mounted) {
        final fmt = appSettings.exportFormat.toUpperCase();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ Saved as $fmt to gallery — no watermark'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
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

class _PhotoPreview extends StatelessWidget {
  final String assetId;
  final bool showBefore;
  const _PhotoPreview({required this.assetId, required this.showBefore});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetEntity?>(
      future: AssetEntity.fromId(assetId),
      builder: (ctx, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator(color: Colors.white38));
        return Stack(fit: StackFit.expand, children: [
          InteractiveViewer(
              child: AssetEntityImage(snap.data!, isOriginal: true, fit: BoxFit.contain)),
          if (showBefore) Container(color: Colors.black54),
        ]);
      },
    );
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
      (EditorTool.crop,        Icons.crop_outlined,          'Crop'),
      (EditorTool.heal,        Icons.healing_outlined,       'Heal'),
      (EditorTool.perspective, Icons.grid_3x3_outlined,      'Persp.'),
      (EditorTool.blur,        Icons.lens_blur_outlined,     'Blur'),
      (EditorTool.selective,   Icons.gesture_outlined,       'Select'),
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
  const _ToolPanel({super.key, required this.tool});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    switch (tool) {
      case EditorTool.filter:      return const SizedBox(height: 6);
      case EditorTool.adjust:      return _AdjustPanel(s: state.current, n: n);
      case EditorTool.hsl:         return const HslPanel();
      case EditorTool.crop:        return const CropToolPanel();
      case EditorTool.heal:        return const HealToolPanel();
      case EditorTool.perspective: return const PerspectiveToolPanel();
      case EditorTool.blur:        return const BlurToolPanel();
      case EditorTool.selective:   return const SelectiveToolPanel();
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
