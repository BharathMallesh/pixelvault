import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/photo_model.dart';
import '../utils/database_helper.dart';

enum GalleryTab { all, edited, batch }

class GalleryState {
  final List<PhotoModel> photos;
  final bool isLoading;
  final bool hasPermission;
  final GalleryTab activeTab;
  final Set<String> selectedIds;
  final String? error;

  const GalleryState({
    this.photos = const [],
    this.isLoading = false,
    this.hasPermission = false,
    this.activeTab = GalleryTab.all,
    this.selectedIds = const {},
    this.error,
  });

  bool get isBatchMode => selectedIds.isNotEmpty;

  List<PhotoModel> get displayedPhotos {
    switch (activeTab) {
      case GalleryTab.edited:
        return photos.where((p) => p.isEdited).toList();
      case GalleryTab.all:
      case GalleryTab.batch:
        return photos;
    }
  }

  GalleryState copyWith({
    List<PhotoModel>? photos,
    bool? isLoading,
    bool? hasPermission,
    GalleryTab? activeTab,
    Set<String>? selectedIds,
    String? error,
  }) {
    return GalleryState(
      photos: photos ?? this.photos,
      isLoading: isLoading ?? this.isLoading,
      hasPermission: hasPermission ?? this.hasPermission,
      activeTab: activeTab ?? this.activeTab,
      selectedIds: selectedIds ?? this.selectedIds,
      error: error ?? this.error,
    );
  }
}

class GalleryNotifier extends StateNotifier<GalleryState> {
  GalleryNotifier() : super(const GalleryState());

  Future<void> loadPhotos() async {
    state = state.copyWith(isLoading: true);

    final permission = await PhotoManager.requestPermissionExtend();
    // Android 14+ / iOS may grant "limited" (selected photos) access. That is
    // still usable — only treat an outright denial as no access.
    final hasAccess =
        permission == PermissionState.authorized ||
        permission == PermissionState.limited;
    if (!hasAccess) {
      state = state.copyWith(
        isLoading: false,
        hasPermission: false,
        error: 'Photo permission denied. Please allow access in Settings.',
      );
      return;
    }

    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );

      if (albums.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          hasPermission: true,
          photos: [],
        );
        return;
      }

      final assets = await albums.first.getAssetListRange(
        start: 0,
        end: 300,
      );

      // Photos with a saved edit appear in the "Edited" tab.
      final editedIds = await DatabaseHelper().getEditedAssetIds();

      final photos = assets.map((asset) {
        return PhotoModel(
          id: asset.id,
          path: asset.id,
          name: asset.title ?? 'Photo',
          createdAt: asset.createDateTime,
          width: asset.width,
          height: asset.height,
          isEdited: editedIds.contains(asset.id),
        );
      }).toList();

      state = state.copyWith(
        isLoading: false,
        hasPermission: true,
        photos: photos,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load photos: $e',
      );
    }
  }

  void setTab(GalleryTab tab) {
    state = state.copyWith(activeTab: tab, selectedIds: {});
  }

  void toggleSelection(String id) {
    final current = Set<String>.from(state.selectedIds);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    state = state.copyWith(selectedIds: current);
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: {});
  }

  void selectAll() {
    final all = state.displayedPhotos.map((p) => p.id).toSet();
    state = state.copyWith(selectedIds: all);
  }
}

final galleryProvider =
    StateNotifierProvider<GalleryNotifier, GalleryState>((ref) {
  return GalleryNotifier();
});
