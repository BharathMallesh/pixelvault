import 'edit_settings.dart';

class PhotoFilter {
  final String id;
  final String name;
  final EditSettings settings;

  const PhotoFilter({
    required this.id,
    required this.name,
    required this.settings,
  });
}

// 20 built-in offline filters
final List<PhotoFilter> builtInFilters = [
  PhotoFilter(
    id: 'original',
    name: 'Original',
    settings: EditSettings.defaults,
  ),
  PhotoFilter(
    id: 'vivid',
    name: 'Vivid',
    settings: EditSettings(saturation: 40, vibrance: 30, contrast: 15),
  ),
  PhotoFilter(
    id: 'warm',
    name: 'Warm',
    settings: EditSettings(warmth: 40, brightness: 5, saturation: 10),
  ),
  PhotoFilter(
    id: 'cool',
    name: 'Cool',
    settings: EditSettings(warmth: -35, saturation: 10, brightness: 5),
  ),
  PhotoFilter(
    id: 'bw',
    name: 'B&W',
    settings: EditSettings(saturation: -100, contrast: 20, clarity: 15),
  ),
  PhotoFilter(
    id: 'vintage',
    name: 'Vintage',
    settings: EditSettings(warmth: 30, saturation: -20, contrast: -10, vignette: 30, brightness: -5),
  ),
  PhotoFilter(
    id: 'fade',
    name: 'Fade',
    settings: EditSettings(contrast: -25, saturation: -15, brightness: 10, highlights: -20),
  ),
  PhotoFilter(
    id: 'drama',
    name: 'Drama',
    settings: EditSettings(contrast: 40, clarity: 30, shadows: -20, highlights: -10),
  ),
  PhotoFilter(
    id: 'soft',
    name: 'Soft',
    settings: EditSettings(contrast: -15, brightness: 8, saturation: 5, sharpness: -10),
  ),
  PhotoFilter(
    id: 'golden',
    name: 'Golden',
    settings: EditSettings(warmth: 50, saturation: 20, brightness: 8, highlights: -10),
  ),
  PhotoFilter(
    id: 'matte',
    name: 'Matte',
    settings: EditSettings(contrast: -20, shadows: 25, saturation: -10, brightness: 5),
  ),
  PhotoFilter(
    id: 'chrome',
    name: 'Chrome',
    settings: EditSettings(saturation: 30, contrast: 25, sharpness: 20, warmth: -10),
  ),
  PhotoFilter(
    id: 'lush',
    name: 'Lush',
    settings: EditSettings(saturation: 50, vibrance: 20, brightness: 5, contrast: 10),
  ),
  PhotoFilter(
    id: 'dusty',
    name: 'Dusty',
    settings: EditSettings(saturation: -30, warmth: 20, contrast: -10, vignette: 20),
  ),
  PhotoFilter(
    id: 'nordic',
    name: 'Nordic',
    settings: EditSettings(warmth: -20, saturation: -10, clarity: 15, contrast: 10),
  ),
  PhotoFilter(
    id: 'moody',
    name: 'Moody',
    settings: EditSettings(shadows: -30, highlights: -20, saturation: -15, contrast: 20, vignette: 25),
  ),
  PhotoFilter(
    id: 'pop',
    name: 'Pop',
    settings: EditSettings(saturation: 60, contrast: 20, vibrance: 30, clarity: 10),
  ),
  PhotoFilter(
    id: 'film',
    name: 'Film',
    settings: EditSettings(contrast: -10, saturation: -5, warmth: 15, vignette: 15, noiseReduction: -20),
  ),
  PhotoFilter(
    id: 'bright',
    name: 'Bright',
    settings: EditSettings(brightness: 20, highlights: 10, saturation: 10, contrast: -5),
  ),
  PhotoFilter(
    id: 'deep',
    name: 'Deep',
    settings: EditSettings(shadows: -40, contrast: 30, saturation: 20, sharpness: 15),
  ),
];
