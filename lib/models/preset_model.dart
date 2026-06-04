import 'edit_settings.dart';

class CustomPreset {
  final String id;
  final String name;
  final EditSettings settings;
  final DateTime createdAt;

  const CustomPreset({
    required this.id, required this.name,
    required this.settings, required this.createdAt,
  });
}
