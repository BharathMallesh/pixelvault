import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../providers/gallery_provider.dart';
import '../theme/app_theme.dart';
import '../utils/image_processor.dart';
import '../utils/photo_saver.dart';
import 'settings_screen.dart';

// Layout definition
class CollageLayout {
  final String id;
  final String label;
  final int count;
  final IconData icon;
  final List<_Cell> cells; // normalized rects
  const CollageLayout({required this.id, required this.label, required this.count, required this.icon, required this.cells});
}

class _Cell {
  final double l, t, r, b;
  const _Cell(this.l, this.t, this.r, this.b);
}

final _layouts = [
  CollageLayout(id: '1x2h', label: '2 Side by Side', count: 2, icon: Icons.view_agenda_outlined,
    cells: [_Cell(0,0,.5,1), _Cell(.5,0,1,1)]),
  CollageLayout(id: '1x2v', label: '2 Stacked', count: 2, icon: Icons.view_stream_outlined,
    cells: [_Cell(0,0,1,.5), _Cell(0,.5,1,1)]),
  CollageLayout(id: '2x2', label: '4 Grid', count: 4, icon: Icons.grid_view_outlined,
    cells: [_Cell(0,0,.5,.5), _Cell(.5,0,1,.5), _Cell(0,.5,.5,1), _Cell(.5,.5,1,1)]),
  CollageLayout(id: 'mag', label: 'Magazine', count: 3, icon: Icons.view_quilt_outlined,
    cells: [_Cell(0,0,1,.55), _Cell(0,.55,.5,1), _Cell(.5,.55,1,1)]),
  CollageLayout(id: '1big2', label: '1 Big + 2', count: 3, icon: Icons.view_column_outlined,
    cells: [_Cell(0,0,.65,1), _Cell(.65,0,1,.5), _Cell(.65,.5,1,1)]),
  CollageLayout(id: '3x2', label: '6 Grid', count: 6, icon: Icons.apps_outlined,
    cells: [
      _Cell(0,0,1/3,.5), _Cell(1/3,0,2/3,.5), _Cell(2/3,0,1,.5),
      _Cell(0,.5,1/3,1), _Cell(1/3,.5,2/3,1), _Cell(2/3,.5,1,1),
    ]),
];

// Providers
final selectedLayoutProvider = StateProvider<CollageLayout>((ref) => _layouts[0]);
final collagePhotosProvider = StateProvider<List<String?>>((ref) => List.filled(2, null));
final collageBorderWidthProvider = StateProvider<double>((ref) => 3.0);
final collageBorderColorProvider = StateProvider<Color>((ref) => Colors.white);

class CollageScreen extends ConsumerWidget {
  const CollageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(selectedLayoutProvider);
    final photos = ref.watch(collagePhotosProvider);
    final borderW = ref.watch(collageBorderWidthProvider);
    final borderColor = ref.watch(collageBorderColorProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collage Maker'),
        actions: [
          TextButton.icon(
            onPressed: photos.any((p) => p != null)
                ? () => _export(context, ref)
                : null,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Export'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Preview canvas
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LayoutBuilder(builder: (ctx, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;
                        return Stack(
                          children: List.generate(layout.cells.length, (i) {
                            final cell = layout.cells[i];
                            final assetId = i < photos.length ? photos[i] : null;
                            return Positioned(
                              left: cell.l * w + borderW / 2,
                              top: cell.t * h + borderW / 2,
                              width: (cell.r - cell.l) * w - borderW,
                              height: (cell.b - cell.t) * h - borderW,
                              child: GestureDetector(
                                onTap: () => _pickPhoto(context, ref, i),
                                child: _CellWidget(assetId: assetId, index: i),
                              ),
                            );
                          }),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Controls
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                // Layout selector
                _SectionLabel('Layout'),
                SizedBox(
                  height: 70,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: _layouts.map((l) {
                      final isActive = l.id == layout.id;
                      return GestureDetector(
                        onTap: () {
                          ref.read(selectedLayoutProvider.notifier).state = l;
                          ref.read(collagePhotosProvider.notifier).state =
                              List.filled(l.count, null);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 10, bottom: 8, top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppTheme.primary.withOpacity(0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isActive ? AppTheme.primary : Colors.grey.shade300,
                              width: isActive ? 1.5 : 0.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(l.icon,
                                  size: 20,
                                  color: isActive ? AppTheme.primary : Colors.grey),
                              const SizedBox(height: 3),
                              Text(l.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isActive ? AppTheme.primary : Colors.grey,
                                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                  )),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Border settings
                _SectionLabel('Border'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Width', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: borderW, min: 0, max: 20,
                          activeColor: AppTheme.primary,
                          onChanged: (v) =>
                              ref.read(collageBorderWidthProvider.notifier).state = v,
                        ),
                      ),
                      Text('${borderW.round()}px',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.primary)),

                      const SizedBox(width: 12),
                      // Color dots
                      for (final c in [Colors.white, Colors.black, Colors.grey.shade300,
                        AppTheme.primary, Colors.transparent])
                        GestureDetector(
                          onTap: () =>
                              ref.read(collageBorderColorProvider.notifier).state = c,
                          child: Container(
                            margin: const EdgeInsets.only(left: 4),
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: c == Colors.transparent ? null : c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: borderColor == c ? AppTheme.primary : Colors.grey.shade400,
                                width: borderColor == c ? 2 : 0.5,
                              ),
                              gradient: c == Colors.transparent
                                  ? const LinearGradient(
                                      colors: [Colors.white, Colors.grey])
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto(BuildContext context, WidgetRef ref, int index) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => const _PhotoPickerSheet(),
    );
    if (result != null) {
      final list = List<String?>.from(ref.read(collagePhotosProvider));
      while (list.length <= index) list.add(null);
      list[index] = result;
      ref.read(collagePhotosProvider.notifier).state = list;
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final layout = ref.read(selectedLayoutProvider);
    final photoIds = ref.read(collagePhotosProvider);
    final borderW = ref.read(collageBorderWidthProvider);
    final borderColor = ref.read(collageBorderColorProvider);
    final appSettings = ref.read(settingsProvider);

    final messenger = ScaffoldMessenger.of(context);

    if (!await PhotoSaver.ensureAccess()) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Gallery permission denied — nothing saved'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    // Show a blocking progress dialog while we fetch + composite.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Resolve each cell's full-size bytes from its asset.
      final cells = <CollageCell>[];
      for (var i = 0; i < layout.cells.length; i++) {
        final cell = layout.cells[i];
        final id = i < photoIds.length ? photoIds[i] : null;
        Uint8List? bytes;
        if (id != null) {
          final asset = await AssetEntity.fromId(id);
          bytes = await asset?.originBytes;
        }
        cells.add(CollageCell(
          left: cell.l, top: cell.t, right: cell.r, bottom: cell.b,
          bytes: bytes,
        ));
      }

      final transparent = borderColor == Colors.transparent;
      final asPng = appSettings.exportFormat.toLowerCase() == 'png' || transparent;

      final bytes = await compute(_composeInIsolate, _CollageJob(
        cells: cells,
        canvasSize: 2000,
        borderWidth: borderW,
        r: (borderColor.r * 255).round(),
        g: (borderColor.g * 255).round(),
        b: (borderColor.b * 255).round(),
        transparent: transparent,
        asPng: asPng,
        jpegQuality: appSettings.jpegQuality,
      ));

      await PhotoSaver.saveBytes(bytes, asPng: asPng);

      if (context.mounted) Navigator.pop(context); // dismiss progress
      messenger.showSnackBar(const SnackBar(
        content: Text('✓ Collage saved to gallery'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text('Could not export collage: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }
}

// Run the heavy compositing off the UI isolate.
class _CollageJob {
  final List<CollageCell> cells;
  final int canvasSize;
  final double borderWidth;
  final int r, g, b;
  final bool transparent;
  final bool asPng;
  final int jpegQuality;
  const _CollageJob({
    required this.cells,
    required this.canvasSize,
    required this.borderWidth,
    required this.r,
    required this.g,
    required this.b,
    required this.transparent,
    required this.asPng,
    required this.jpegQuality,
  });
}

Uint8List _composeInIsolate(_CollageJob job) => ImageProcessor.composeCollage(
      cells: job.cells,
      canvasSize: job.canvasSize,
      borderWidth: job.borderWidth,
      borderR: job.r,
      borderG: job.g,
      borderB: job.b,
      transparentBorder: job.transparent,
      asPng: job.asPng,
      jpegQuality: job.jpegQuality,
    );

class _CellWidget extends StatelessWidget {
  final String? assetId;
  final int index;
  const _CellWidget({required this.assetId, required this.index});

  @override
  Widget build(BuildContext context) {
    if (assetId == null) {
      return Container(
        color: Colors.grey.shade800,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_photo_alternate_outlined,
                color: Colors.white38, size: 28),
            const SizedBox(height: 4),
            Text('Tap to add', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      );
    }
    return FutureBuilder<AssetEntity?>(
      future: AssetEntity.fromId(assetId!),
      builder: (ctx, snap) {
        if (!snap.hasData) return Container(color: Colors.grey.shade900);
        return AssetEntityImage(
          snap.data!,
          isOriginal: false,
          thumbnailSize: const ThumbnailSize.square(400),
          fit: BoxFit.cover,
        );
      },
    );
  }
}

class _PhotoPickerSheet extends ConsumerWidget {
  const _PhotoPickerSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gallery = ref.watch(galleryProvider);
    return Container(
      height: 300,
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, crossAxisSpacing: 2, mainAxisSpacing: 2),
        itemCount: gallery.photos.length,
        itemBuilder: (ctx, i) {
          final photo = gallery.photos[i];
          return GestureDetector(
            onTap: () => Navigator.pop(context, photo.id),
            child: FutureBuilder<AssetEntity?>(
              future: AssetEntity.fromId(photo.id),
              builder: (ctx, snap) {
                if (!snap.hasData) return Container(color: Colors.grey.shade200);
                return AssetEntityImage(
                  snap.data!,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(200),
                  fit: BoxFit.cover,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(label.toUpperCase(),
          style: const TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: AppTheme.primary, letterSpacing: 0.8)),
    ),
  );
}
