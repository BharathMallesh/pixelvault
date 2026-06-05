import 'brush_mask.dart';

class EditSettings {
  // Basic adjustments (-100 to 100)
  final double brightness;
  final double contrast;
  final double saturation;
  final double vibrance;
  final double highlights;
  final double shadows;
  final double sharpness;
  final double clarity;

  // Color
  final double warmth;
  final double tint;

  // Effects
  final double vignette;
  final double dehaze;
  final double noiseReduction;

  // Phase 2 — HSL per channel
  final double hslRedHue;
  final double hslRedSat;
  final double hslRedLum;
  final double hslOrangeHue;
  final double hslOrangeSat;
  final double hslOrangeLum;
  final double hslYellowHue;
  final double hslYellowSat;
  final double hslYellowLum;
  final double hslGreenHue;
  final double hslGreenSat;
  final double hslGreenLum;
  final double hslBlueHue;
  final double hslBlueSat;
  final double hslBlueLum;
  final double hslPurpleHue;
  final double hslPurpleSat;
  final double hslPurpleLum;

  // Phase 2 — Perspective
  final double perspectiveVertical;
  final double perspectiveHorizontal;

  // Phase 2 — Background blur strength (0 = off)
  final double blurStrength;

  // Phase 2 — Brush masks (resolution-independent, normalized dabs)
  // Spots to clone-heal:
  final BrushMask healMask;
  // In-focus subject region for background blur (empty = center-weighted):
  final BrushMask focusMask;
  // Region for selective adjustments, plus the adjustments to apply there:
  final BrushMask selectiveMask;
  final double selBrightness;
  final double selContrast;
  final double selSaturation;
  final double selWarmth;

  // Rotation & flip
  final double rotation;
  final bool flipHorizontal;
  final bool flipVertical;

  // Crop rect (normalized 0.0–1.0, null = no crop)
  final CropRect? cropRect;

  // Active filter name
  final String? activeFilter;

  const EditSettings({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.vibrance = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.sharpness = 0,
    this.clarity = 0,
    this.warmth = 0,
    this.tint = 0,
    this.vignette = 0,
    this.dehaze = 0,
    this.noiseReduction = 0,
    // HSL
    this.hslRedHue = 0,    this.hslRedSat = 0,    this.hslRedLum = 0,
    this.hslOrangeHue = 0, this.hslOrangeSat = 0, this.hslOrangeLum = 0,
    this.hslYellowHue = 0, this.hslYellowSat = 0, this.hslYellowLum = 0,
    this.hslGreenHue = 0,  this.hslGreenSat = 0,  this.hslGreenLum = 0,
    this.hslBlueHue = 0,   this.hslBlueSat = 0,   this.hslBlueLum = 0,
    this.hslPurpleHue = 0, this.hslPurpleSat = 0, this.hslPurpleLum = 0,
    // Perspective
    this.perspectiveVertical = 0,
    this.perspectiveHorizontal = 0,
    // Blur
    this.blurStrength = 0,
    // Brush masks
    this.healMask = const BrushMask(),
    this.focusMask = const BrushMask(),
    this.selectiveMask = const BrushMask(),
    this.selBrightness = 0,
    this.selContrast = 0,
    this.selSaturation = 0,
    this.selWarmth = 0,
    // Transform
    this.rotation = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.cropRect,
    this.activeFilter,
  });

  bool get isDefault =>
      brightness == 0 && contrast == 0 && saturation == 0 &&
      vibrance == 0 && highlights == 0 && shadows == 0 &&
      sharpness == 0 && clarity == 0 && warmth == 0 && tint == 0 &&
      vignette == 0 && dehaze == 0 && noiseReduction == 0 &&
      hslRedHue == 0 && hslRedSat == 0 && hslRedLum == 0 &&
      hslGreenHue == 0 && hslGreenSat == 0 && hslGreenLum == 0 &&
      hslBlueHue == 0 && hslBlueSat == 0 && hslBlueLum == 0 &&
      perspectiveVertical == 0 && perspectiveHorizontal == 0 &&
      blurStrength == 0 && rotation == 0 &&
      healMask.isEmpty && focusMask.isEmpty && selectiveMask.isEmpty &&
      selBrightness == 0 && selContrast == 0 &&
      selSaturation == 0 && selWarmth == 0 &&
      !flipHorizontal && !flipVertical &&
      cropRect == null && activeFilter == null;

  EditSettings copyWith({
    double? brightness, double? contrast, double? saturation,
    double? vibrance, double? highlights, double? shadows,
    double? sharpness, double? clarity, double? warmth, double? tint,
    double? vignette, double? dehaze, double? noiseReduction,
    double? hslRedHue, double? hslRedSat, double? hslRedLum,
    double? hslOrangeHue, double? hslOrangeSat, double? hslOrangeLum,
    double? hslYellowHue, double? hslYellowSat, double? hslYellowLum,
    double? hslGreenHue, double? hslGreenSat, double? hslGreenLum,
    double? hslBlueHue, double? hslBlueSat, double? hslBlueLum,
    double? hslPurpleHue, double? hslPurpleSat, double? hslPurpleLum,
    double? perspectiveVertical, double? perspectiveHorizontal,
    double? blurStrength,
    BrushMask? healMask, BrushMask? focusMask, BrushMask? selectiveMask,
    double? selBrightness, double? selContrast,
    double? selSaturation, double? selWarmth,
    double? rotation, bool? flipHorizontal, bool? flipVertical,
    CropRect? cropRect, bool clearCrop = false,
    String? activeFilter, bool clearFilter = false,
  }) {
    return EditSettings(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      vibrance: vibrance ?? this.vibrance,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      sharpness: sharpness ?? this.sharpness,
      clarity: clarity ?? this.clarity,
      warmth: warmth ?? this.warmth,
      tint: tint ?? this.tint,
      vignette: vignette ?? this.vignette,
      dehaze: dehaze ?? this.dehaze,
      noiseReduction: noiseReduction ?? this.noiseReduction,
      hslRedHue: hslRedHue ?? this.hslRedHue,
      hslRedSat: hslRedSat ?? this.hslRedSat,
      hslRedLum: hslRedLum ?? this.hslRedLum,
      hslOrangeHue: hslOrangeHue ?? this.hslOrangeHue,
      hslOrangeSat: hslOrangeSat ?? this.hslOrangeSat,
      hslOrangeLum: hslOrangeLum ?? this.hslOrangeLum,
      hslYellowHue: hslYellowHue ?? this.hslYellowHue,
      hslYellowSat: hslYellowSat ?? this.hslYellowSat,
      hslYellowLum: hslYellowLum ?? this.hslYellowLum,
      hslGreenHue: hslGreenHue ?? this.hslGreenHue,
      hslGreenSat: hslGreenSat ?? this.hslGreenSat,
      hslGreenLum: hslGreenLum ?? this.hslGreenLum,
      hslBlueHue: hslBlueHue ?? this.hslBlueHue,
      hslBlueSat: hslBlueSat ?? this.hslBlueSat,
      hslBlueLum: hslBlueLum ?? this.hslBlueLum,
      hslPurpleHue: hslPurpleHue ?? this.hslPurpleHue,
      hslPurpleSat: hslPurpleSat ?? this.hslPurpleSat,
      hslPurpleLum: hslPurpleLum ?? this.hslPurpleLum,
      perspectiveVertical: perspectiveVertical ?? this.perspectiveVertical,
      perspectiveHorizontal: perspectiveHorizontal ?? this.perspectiveHorizontal,
      blurStrength: blurStrength ?? this.blurStrength,
      healMask: healMask ?? this.healMask,
      focusMask: focusMask ?? this.focusMask,
      selectiveMask: selectiveMask ?? this.selectiveMask,
      selBrightness: selBrightness ?? this.selBrightness,
      selContrast: selContrast ?? this.selContrast,
      selSaturation: selSaturation ?? this.selSaturation,
      selWarmth: selWarmth ?? this.selWarmth,
      rotation: rotation ?? this.rotation,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      cropRect: clearCrop ? null : (cropRect ?? this.cropRect),
      activeFilter: clearFilter ? null : (activeFilter ?? this.activeFilter),
    );
  }

  static const EditSettings defaults = EditSettings();
}

class CropRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const CropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  @override
  bool operator ==(Object other) =>
      other is CropRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  Map<String, double> toMap() =>
      {'left': left, 'top': top, 'right': right, 'bottom': bottom};

  static CropRect fromMap(Map<String, dynamic> m) => CropRect(
        left: (m['left'] as num).toDouble(),
        top: (m['top'] as num).toDouble(),
        right: (m['right'] as num).toDouble(),
        bottom: (m['bottom'] as num).toDouble(),
      );
}
