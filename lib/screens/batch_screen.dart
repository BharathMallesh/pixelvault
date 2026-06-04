import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../providers/gallery_provider.dart';
import '../models/filter_model.dart';
import '../models/edit_settings.dart';
import '../theme/app_theme.dart';
import '../utils/photo_saver.dart';
import 'settings_screen.dart';

class BatchScreen extends ConsumerStatefulWidget {
  const BatchScreen({super.key});

  @override
  ConsumerState<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends ConsumerState<BatchScreen> {
  String _selectedFilterId = 'original';
  bool _isProcessing = false;
  int _processedCount = 0;

  @override
  Widget build(BuildContext context) {
    final gallery = ref.watch(galleryProvider);
    final notifier = ref.read(galleryProvider.notifier);
    final selected = gallery.selectedIds;

    return Scaffold(
      appBar: AppBar(
        title: selected.isEmpty
            ? const Text('Batch Edit')
            : Text('${selected.length} selected'),
        actions: [
          if (selected.isNotEmpty)
            TextButton(
              onPressed: notifier.clearSelection,
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Instructions banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: AppTheme.primary.withOpacity(0.08),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected.isEmpty
                        ? 'Long-press photos in Gallery or tap here to select'
                        : 'Choose a filter below and tap Apply',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.primary),
                  ),
                ),
              ],
            ),
          ),

          // Photo grid
          Expanded(
            child: _BatchGrid(
              photos: gallery.photos,
              selectedIds: selected,
              onToggle: notifier.toggleSelection,
            ),
          ),

          // Filter picker + apply button
          if (selected.isNotEmpty)
            _BottomPanel(
              selectedFilterId: _selectedFilterId,
              selectedCount: selected.length,
              isProcessing: _isProcessing,
              processedCount: _processedCount,
              onFilterSelected: (id) =>
                  setState(() => _selectedFilterId = id),
              onApply: _applyBatch,
            ),
        ],
      ),
    );
  }

  Future<void> _applyBatch() async {
    final selected = ref.read(galleryProvider).selectedIds.toList();
    final appSettings = ref.read(settingsProvider);

    // Resolve the chosen filter's settings.
    final filter = builtInFilters.firstWhere(
      (f) => f.id == _selectedFilterId,
      orElse: () => builtInFilters.first,
    );
    final EditSettings settings = filter.settings;

    // Confirm gallery access once, before the loop.
    if (!await PhotoSaver.ensureAccess()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Gallery permission denied — nothing saved'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _processedCount = 0;
    });

    var failures = 0;
    for (var i = 0; i < selected.length; i++) {
      try {
        await PhotoSaver.processAndSaveAsset(
          assetId: selected[i],
          settings: settings,
          exportFormat: appSettings.exportFormat,
          jpegQuality: appSettings.jpegQuality,
        );
      } catch (_) {
        failures++;
      }
      if (!mounted) return;
      setState(() => _processedCount = i + 1);
    }

    setState(() => _isProcessing = false);
    ref.read(galleryProvider.notifier).clearSelection();

    if (mounted) {
      final ok = selected.length - failures;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failures == 0
            ? '✓ Saved $ok photo${ok == 1 ? '' : 's'} with “${filter.name}”'
            : 'Saved $ok of ${selected.length} — $failures failed'),
        backgroundColor: failures == 0 ? Colors.green : Colors.orange,
      ));
    }
  }
}

class _BatchGrid extends StatelessWidget {
  final List photos;
  final Set<String> selectedIds;
  final void Function(String) onToggle;

  const _BatchGrid({
    required this.photos,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: photos.length,
      itemBuilder: (ctx, i) {
        final photo = photos[i];
        final isSelected = selectedIds.contains(photo.id);

        return GestureDetector(
          onTap: () => onToggle(photo.id),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<AssetEntity?>(
                future: AssetEntity.fromId(photo.id),
                builder: (ctx, snap) {
                  if (!snap.hasData)
                    return Container(color: Colors.grey.shade200);
                  return AssetEntityImage(
                    snap.data!,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(200),
                    fit: BoxFit.cover,
                  );
                },
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                color: isSelected
                    ? AppTheme.primary.withOpacity(0.3)
                    : Colors.transparent,
              ),
              Positioned(
                top: 6,
                right: 6,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppTheme.primary : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final String selectedFilterId;
  final int selectedCount;
  final bool isProcessing;
  final int processedCount;
  final void Function(String) onFilterSelected;
  final VoidCallback onApply;

  const _BottomPanel({
    required this.selectedFilterId,
    required this.selectedCount,
    required this.isProcessing,
    required this.processedCount,
    required this.onFilterSelected,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
            top: BorderSide(color: Colors.grey.shade200, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose filter',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          // Filter chips
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: builtInFilters.take(10).map((f) {
                final isActive = f.id == selectedFilterId;
                return GestureDetector(
                  onTap: () => onFilterSelected(f.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppTheme.primary
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      f.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: isActive ? Colors.white : Colors.black87,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Progress / Apply button
          if (isProcessing)
            Column(
              children: [
                LinearProgressIndicator(
                  value: processedCount / selectedCount,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Processing $processedCount of $selectedCount…',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.auto_fix_high),
                label: Text('Apply to $selectedCount photos'),
              ),
            ),
        ],
      ),
    );
  }
}
