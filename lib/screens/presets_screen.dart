import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/preset_model.dart';
import '../models/edit_settings.dart';
import '../providers/editor_provider.dart';
import '../utils/database_helper.dart';
import '../theme/app_theme.dart';

final presetsProvider = StateNotifierProvider<PresetsNotifier, List<CustomPreset>>(
    (ref) => PresetsNotifier());

class PresetsNotifier extends StateNotifier<List<CustomPreset>> {
  PresetsNotifier() : super([]) { _load(); }
  final _db = DatabaseHelper();

  Future<void> _load() async {
    final rows = await _db.getAllPresets();
    state = rows.map((r) => CustomPreset(
      id: r['id'] as String,
      name: r['name'] as String,
      settings: r['settings'] as EditSettings,
      createdAt: DateTime.now(),
    )).toList();
  }

  Future<void> save(String name, EditSettings settings) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _db.savePreset(id, name, settings);
    state = [...state, CustomPreset(id: id, name: name, settings: settings, createdAt: DateTime.now())];
  }

  Future<void> delete(String id) async {
    await _db.deletePreset(id);
    state = state.where((p) => p.id != id).toList();
  }
}

class PresetsScreen extends ConsumerWidget {
  const PresetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Presets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Save current edits as preset',
            onPressed: () => _saveCurrentAsPreset(context, ref),
          ),
        ],
      ),
      body: presets.isEmpty
          ? _EmptyState(onAdd: () => _saveCurrentAsPreset(context, ref))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: presets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final preset = presets[i];
                return _PresetCard(
                  preset: preset,
                  onApply: () {
                    ref.read(editorProvider.notifier).applyFilter(preset.id, preset.settings);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Applied "${preset.name}"'),
                          backgroundColor: Colors.green),
                    );
                  },
                  onDelete: () => ref.read(presetsProvider.notifier).delete(preset.id),
                );
              },
            ),
    );
  }

  void _saveCurrentAsPreset(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save as preset'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Preset name…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              final settings = ref.read(editorProvider).current;
              ref.read(presetsProvider.notifier).save(ctrl.text.trim(), settings);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Saved preset "${ctrl.text.trim()}"'),
                    backgroundColor: Colors.green),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final CustomPreset preset;
  final VoidCallback onApply;
  final VoidCallback onDelete;
  const _PresetCard({required this.preset, required this.onApply, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary.withOpacity(0.7), AppTheme.accent.withOpacity(0.7)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.tune, color: Colors.white, size: 20),
        ),
        title: Text(preset.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(_settingsSummary(preset.settings),
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: onApply, child: const Text('Apply')),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _settingsSummary(EditSettings s) {
    final parts = <String>[];
    if (s.brightness != 0) parts.add('Bright ${s.brightness > 0 ? '+' : ''}${s.brightness.round()}');
    if (s.contrast != 0)   parts.add('Contrast ${s.contrast.round()}');
    if (s.saturation != 0) parts.add('Sat ${s.saturation.round()}');
    if (s.warmth != 0)     parts.add('Warmth ${s.warmth.round()}');
    if (parts.isEmpty)     parts.add('Custom edit');
    return parts.take(3).join(' · ');
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('No saved presets',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Edit a photo, then save your adjustments as a reusable preset.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Save current edits'),
          ),
        ],
      ),
    );
  }
}
