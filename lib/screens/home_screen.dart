import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../providers/gallery_provider.dart';
import '../models/photo_model.dart';
import '../theme/app_theme.dart';
import 'editor_screen.dart';
import 'batch_screen.dart';
import 'collage_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _bottomNavIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(galleryProvider.notifier).loadPhotos();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _GalleryPage(),
      const BatchScreen(),
      const CollageScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: pages[_bottomNavIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: (i) => setState(() => _bottomNavIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library_outlined),
            activeIcon: Icon(Icons.photo_library),
            label: 'Gallery',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_filter_outlined),
            activeIcon: Icon(Icons.photo_filter),
            label: 'Batch',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_outlined),
            activeIcon: Icon(Icons.grid_view),
            label: 'Collage',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _GalleryPage extends ConsumerWidget {
  const _GalleryPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(galleryProvider);
    final notifier = ref.read(galleryProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: state.isBatchMode
            ? Text('${state.selectedIds.length} selected')
            : const Text('PixelVault'),
        actions: [
          if (state.isBatchMode) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete selected',
              onPressed: () => _confirmDelete(context, ref, state.selectedIds.toList()),
            ),
            TextButton(
              onPressed: notifier.selectAll,
              child: const Text('All'),
            ),
            TextButton(
              onPressed: notifier.clearSelection,
              child: const Text('Clear'),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search_outlined),
              onPressed: () {},
              tooltip: 'Search',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Tab bar
          _TabBar(
            active: state.activeTab,
            onTap: notifier.setTab,
          ),
          // Content
          Expanded(
            child: state.isLoading
                ? const _LoadingView()
                : !state.hasPermission
                    ? const _PermissionView()
                    : state.photos.isEmpty
                        ? const _EmptyView()
                        : _PhotoGrid(photos: state.displayedPhotos),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, List<String> ids) async {
    if (ids.isEmpty) return;
    final n = ids.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete $n photo${n == 1 ? '' : 's'}?'),
        content: const Text(
          'This permanently removes the selected photos from your device — '
          'including originals. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final deleted = await ref.read(galleryProvider.notifier).deletePhotos(ids);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(deleted.isEmpty
            ? 'No photos deleted'
            : 'Deleted ${deleted.length} photo${deleted.length == 1 ? '' : 's'}'),
        backgroundColor: deleted.isEmpty ? Colors.grey : Colors.green,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not delete: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }
}

class _TabBar extends StatelessWidget {
  final GalleryTab active;
  final void Function(GalleryTab) onTap;

  const _TabBar({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).appBarTheme.backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: GalleryTab.values.map((tab) {
          final isActive = tab == active;
          final labels = {
            GalleryTab.all: 'All Photos',
            GalleryTab.edited: 'Edited',
            GalleryTab.batch: 'Batch Select',
          };
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onTap(tab),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.primary
                      : Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  labels[tab]!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PhotoGrid extends ConsumerWidget {
  final List<PhotoModel> photos;
  const _PhotoGrid({required this.photos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(galleryProvider);
    final notifier = ref.read(galleryProvider.notifier);
    final isBatch = state.activeTab == GalleryTab.batch;

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
        final isSelected = state.selectedIds.contains(photo.id);

        return GestureDetector(
          onTap: () {
            if (isBatch) {
              notifier.toggleSelection(photo.id);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditorScreen(assetId: photo.id),
                ),
              ).then((_) {
                // Reload so a photo just saved to the gallery shows up.
                notifier.loadPhotos();
              });
            }
          },
          onLongPress: () {
            if (!isBatch) {
              notifier.setTab(GalleryTab.batch);
              notifier.toggleSelection(photo.id);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo thumbnail
              _AssetThumbnail(assetId: photo.id),

              // Edited badge
              if (photo.isEdited && !isBatch)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Edited',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

              // Batch selection overlay
              if (isBatch)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withOpacity(0.35)
                        : Colors.transparent,
                  ),
                ),
              if (isBatch)
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
                        ? const Icon(Icons.check,
                            size: 14, color: Colors.white)
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

class _AssetThumbnail extends StatelessWidget {
  final String assetId;
  const _AssetThumbnail({required this.assetId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetEntity?>(
      future: AssetEntity.fromId(assetId),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) {
          return Container(color: Colors.grey.shade200);
        }
        return AssetEntityImage(
          snapshot.data!,
          isOriginal: false,
          thumbnailSize: const ThumbnailSize.square(300),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: Colors.grey.shade300),
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading photos…'),
        ],
      ),
    );
  }
}

class _PermissionView extends StatelessWidget {
  const _PermissionView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Photo access needed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Allow PixelVault to access your photos to start editing. All editing happens on your device only.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => PhotoManager.openSetting(),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'No photos yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Take some photos or import them to get started.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
