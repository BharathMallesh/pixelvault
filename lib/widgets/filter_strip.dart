import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../models/filter_model.dart';

class FilterStrip extends StatelessWidget {
  final String activeFilterId;
  final String assetId;
  final void Function(PhotoFilter) onFilterSelected;

  const FilterStrip({
    super.key,
    required this.activeFilterId,
    required this.assetId,
    required this.onFilterSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      color: const Color(0xFF111111),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: builtInFilters.length,
        itemBuilder: (ctx, i) {
          final filter = builtInFilters[i];
          final isActive = filter.id == activeFilterId;
          return GestureDetector(
            onTap: () => onFilterSelected(filter),
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                children: [
                  // Thumbnail
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFF5E92F3)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: _FilterThumbnail(assetId: assetId),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Label
                  Text(
                    filter.name,
                    style: TextStyle(
                      fontSize: 10,
                      color: isActive
                          ? const Color(0xFF5E92F3)
                          : Colors.white54,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterThumbnail extends StatelessWidget {
  final String assetId;
  const _FilterThumbnail({required this.assetId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetEntity?>(
      future: AssetEntity.fromId(assetId),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return Container(color: Colors.grey.shade800);
        }
        return AssetEntityImage(
          snap.data!,
          isOriginal: false,
          thumbnailSize: const ThumbnailSize.square(100),
          fit: BoxFit.cover,
        );
      },
    );
  }
}
