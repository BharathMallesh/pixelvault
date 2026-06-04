import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/edit_settings.dart';

enum EditorTool { filter, adjust, hsl, crop, heal, perspective, blur, text, draw, sticker }

class EditorState {
  final String? assetId;
  final EditSettings current;
  final List<EditSettings> history;
  final int historyIndex;
  final EditorTool activeTool;
  final bool isSaving;
  final bool showBeforeAfter;

  const EditorState({
    this.assetId,
    this.current = EditSettings.defaults,
    this.history = const [EditSettings.defaults],
    this.historyIndex = 0,
    this.activeTool = EditorTool.filter,
    this.isSaving = false,
    this.showBeforeAfter = false,
  });

  bool get canUndo => historyIndex > 0;
  bool get canRedo => historyIndex < history.length - 1;

  EditorState copyWith({
    String? assetId,
    EditSettings? current,
    List<EditSettings>? history,
    int? historyIndex,
    EditorTool? activeTool,
    bool? isSaving,
    bool? showBeforeAfter,
  }) {
    return EditorState(
      assetId: assetId ?? this.assetId,
      current: current ?? this.current,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
      activeTool: activeTool ?? this.activeTool,
      isSaving: isSaving ?? this.isSaving,
      showBeforeAfter: showBeforeAfter ?? this.showBeforeAfter,
    );
  }
}

class EditorNotifier extends StateNotifier<EditorState> {
  EditorNotifier() : super(const EditorState());

  void loadPhoto(String assetId) {
    state = EditorState(
      assetId: assetId,
      current: EditSettings.defaults,
      history: const [EditSettings.defaults],
      historyIndex: 0,
    );
  }

  void updateSetting(EditSettings newSettings) {
    final trimmed = state.history.sublist(0, state.historyIndex + 1);
    final newHistory = [...trimmed, newSettings];
    state = state.copyWith(
      current: newSettings,
      history: newHistory,
      historyIndex: newHistory.length - 1,
    );
  }

  void undo() {
    if (!state.canUndo) return;
    final newIndex = state.historyIndex - 1;
    state = state.copyWith(current: state.history[newIndex], historyIndex: newIndex);
  }

  void redo() {
    if (!state.canRedo) return;
    final newIndex = state.historyIndex + 1;
    state = state.copyWith(current: state.history[newIndex], historyIndex: newIndex);
  }

  void resetAll() {
    state = state.copyWith(
      current: EditSettings.defaults,
      history: const [EditSettings.defaults],
      historyIndex: 0,
    );
  }

  void setTool(EditorTool tool) => state = state.copyWith(activeTool: tool);
  void toggleBeforeAfter(bool v) => state = state.copyWith(showBeforeAfter: v);

  // Basic adjustments
  void setBrightness(double v)    => updateSetting(state.current.copyWith(brightness: v));
  void setContrast(double v)      => updateSetting(state.current.copyWith(contrast: v));
  void setSaturation(double v)    => updateSetting(state.current.copyWith(saturation: v));
  void setVibrance(double v)      => updateSetting(state.current.copyWith(vibrance: v));
  void setHighlights(double v)    => updateSetting(state.current.copyWith(highlights: v));
  void setShadows(double v)       => updateSetting(state.current.copyWith(shadows: v));
  void setSharpness(double v)     => updateSetting(state.current.copyWith(sharpness: v));
  void setClarity(double v)       => updateSetting(state.current.copyWith(clarity: v));
  void setWarmth(double v)        => updateSetting(state.current.copyWith(warmth: v));
  void setTint(double v)          => updateSetting(state.current.copyWith(tint: v));
  void setVignette(double v)      => updateSetting(state.current.copyWith(vignette: v));
  void setDehaze(double v)        => updateSetting(state.current.copyWith(dehaze: v));
  void setNoiseReduction(double v)=> updateSetting(state.current.copyWith(noiseReduction: v));

  // HSL
  void setHsl(String channel, String prop, double v) {
    EditSettings s = state.current;
    switch ('${channel}_$prop') {
      case 'red_hue':    s = s.copyWith(hslRedHue: v); break;
      case 'red_sat':    s = s.copyWith(hslRedSat: v); break;
      case 'red_lum':    s = s.copyWith(hslRedLum: v); break;
      case 'orange_hue': s = s.copyWith(hslOrangeHue: v); break;
      case 'orange_sat': s = s.copyWith(hslOrangeSat: v); break;
      case 'orange_lum': s = s.copyWith(hslOrangeLum: v); break;
      case 'yellow_hue': s = s.copyWith(hslYellowHue: v); break;
      case 'yellow_sat': s = s.copyWith(hslYellowSat: v); break;
      case 'yellow_lum': s = s.copyWith(hslYellowLum: v); break;
      case 'green_hue':  s = s.copyWith(hslGreenHue: v); break;
      case 'green_sat':  s = s.copyWith(hslGreenSat: v); break;
      case 'green_lum':  s = s.copyWith(hslGreenLum: v); break;
      case 'blue_hue':   s = s.copyWith(hslBlueHue: v); break;
      case 'blue_sat':   s = s.copyWith(hslBlueSat: v); break;
      case 'blue_lum':   s = s.copyWith(hslBlueLum: v); break;
      case 'purple_hue': s = s.copyWith(hslPurpleHue: v); break;
      case 'purple_sat': s = s.copyWith(hslPurpleSat: v); break;
      case 'purple_lum': s = s.copyWith(hslPurpleLum: v); break;
    }
    updateSetting(s);
  }

  // Perspective
  void setPerspectiveVertical(double v)   => updateSetting(state.current.copyWith(perspectiveVertical: v));
  void setPerspectiveHorizontal(double v) => updateSetting(state.current.copyWith(perspectiveHorizontal: v));

  // Blur
  void setBlurStrength(double v) => updateSetting(state.current.copyWith(blurStrength: v));

  // Crop
  void setCrop(CropRect rect)    => updateSetting(state.current.copyWith(cropRect: rect));
  void clearCrop()               => updateSetting(state.current.copyWith(clearCrop: true));

  // Flip / rotate
  void setRotation(double v)         => updateSetting(state.current.copyWith(rotation: v));
  void toggleFlipH()                 => updateSetting(state.current.copyWith(flipHorizontal: !state.current.flipHorizontal));
  void toggleFlipV()                 => updateSetting(state.current.copyWith(flipVertical: !state.current.flipVertical));

  // Filter
  void applyFilter(String filterId, EditSettings filterSettings) {
    updateSetting(filterSettings.copyWith(activeFilter: filterId));
  }

  void setSaving(bool v) => state = state.copyWith(isSaving: v);
}

final editorProvider = StateNotifierProvider<EditorNotifier, EditorState>(
    (ref) => EditorNotifier());
