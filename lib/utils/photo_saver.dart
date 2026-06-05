import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/edit_settings.dart';
import 'image_processor.dart';
import 'database_helper.dart';

/// Shared "process an asset and save it to the gallery" pipeline used by the
/// editor (single photo) and the batch screen (many photos). Centralizes
/// format/quality handling, gallery permission, the temp-file write that `gal`
/// requires, and optional edit-history persistence.
class PhotoSaver {
  static const String album = 'PixelVault';

  /// Ensure we can write to the gallery. Returns false if the user declined.
  static Future<bool> ensureAccess() async {
    if (await Gal.hasAccess(toAlbum: true)) return true;
    return Gal.requestAccess(toAlbum: true);
  }

  /// Process [assetId] with [settings] and write the result to the gallery.
  /// Honors [exportFormat] ('jpeg' | 'png') and [jpegQuality]. When
  /// [recordHistory] is true, the applied settings are saved to SQLite for the
  /// asset. Throws on failure so callers can surface a specific message.
  static Future<void> processAndSaveAsset({
    required String assetId,
    required EditSettings settings,
    String exportFormat = 'jpeg',
    int jpegQuality = 95,
    bool recordHistory = true,
  }) async {
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) throw Exception('Original photo not found');
    final originBytes = await asset.originBytes;
    if (originBytes == null) throw Exception('Could not read photo data');

    final asPng = exportFormat.toLowerCase() == 'png';
    // Full-resolution decode/process/encode runs on a background isolate so it
    // never freezes the UI.
    Uint8List processed;
    try {
      processed = await ImageProcessor.processBytesIsolated(
        inputBytes: originBytes,
        settings: settings,
        jpegQuality: jpegQuality,
        asPng: asPng,
      );
    } catch (_) {
      // The original may be a format the Dart image package can't decode
      // (HEIC / camera RAW). Fall back to a full-size JPEG the OS hands us.
      final fallback = await asset.thumbnailDataWithSize(
        ThumbnailSize(asset.width.clamp(1, 4096), asset.height.clamp(1, 4096)),
        quality: 95,
      );
      if (fallback == null) rethrow;
      processed = await ImageProcessor.processBytesIsolated(
        inputBytes: fallback,
        settings: settings,
        jpegQuality: jpegQuality,
        asPng: asPng,
      );
    }

    await _writeToGallery(processed, asPng: asPng);

    if (recordHistory) {
      // Persist best-effort; a DB hiccup shouldn't fail an otherwise-good save.
      try {
        await DatabaseHelper().saveEditHistory(assetId, settings);
      } catch (_) {}
    }
  }

  /// Write already-encoded image [bytes] to the gallery album. `gal` saves
  /// from a file path, so we stage a temp file and clean it up afterward.
  static Future<void> _writeToGallery(Uint8List bytes,
      {required bool asPng}) async {
    final dir = await getTemporaryDirectory();
    final ext = asPng ? 'png' : 'jpg';
    final tmpPath = p.join(
        dir.path, 'pixelvault_${DateTime.now().microsecondsSinceEpoch}.$ext');
    final file = File(tmpPath);
    await file.writeAsBytes(bytes);
    try {
      await Gal.putImage(tmpPath, album: album);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  /// Save raw encoded [bytes] (e.g. a composited collage) directly to the
  /// gallery. Assumes access has already been granted.
  static Future<void> saveBytes(Uint8List bytes, {bool asPng = false}) =>
      _writeToGallery(bytes, asPng: asPng);
}
