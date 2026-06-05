import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/edit_settings.dart';
import '../models/brush_mask.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'pixelvault.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Edit history per photo
        await db.execute('''
          CREATE TABLE edit_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            asset_id TEXT NOT NULL,
            settings TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');

        // Saved presets
        await db.execute('''
          CREATE TABLE presets (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            settings TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');

        // Index for fast lookup by asset
        await db.execute(
            'CREATE INDEX idx_edit_asset ON edit_history(asset_id)');
      },
    );
  }

  // ── Edit History ─────────────────────────────────────────────────

  Future<void> saveEditHistory(String assetId, EditSettings settings) async {
    final db = await database;
    await db.insert('edit_history', {
      'asset_id': assetId,
      'settings': jsonEncode(_settingsToMap(settings)),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<EditSettings?> getLastEdit(String assetId) async {
    final db = await database;
    final rows = await db.query(
      'edit_history',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _settingsFromMap(jsonDecode(rows.first['settings'] as String));
  }

  Future<void> clearEditHistory(String assetId) async {
    final db = await database;
    await db.delete('edit_history',
        where: 'asset_id = ?', whereArgs: [assetId]);
  }

  /// Distinct asset IDs that have at least one saved edit — used to flag the
  /// "Edited" tab in the gallery.
  Future<Set<String>> getEditedAssetIds() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT DISTINCT asset_id FROM edit_history');
    return rows.map((r) => r['asset_id'] as String).toSet();
  }

  // ── Presets ───────────────────────────────────────────────────────

  Future<void> savePreset(String id, String name, EditSettings settings) async {
    final db = await database;
    await db.insert(
      'presets',
      {
        'id': id,
        'name': name,
        'settings': jsonEncode(_settingsToMap(settings)),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllPresets() async {
    final db = await database;
    final rows =
        await db.query('presets', orderBy: 'created_at DESC');
    return rows.map((row) {
      return {
        'id': row['id'],
        'name': row['name'],
        'settings':
            _settingsFromMap(jsonDecode(row['settings'] as String)),
      };
    }).toList();
  }

  Future<void> deletePreset(String id) async {
    final db = await database;
    await db.delete('presets', where: 'id = ?', whereArgs: [id]);
  }

  // ── Serialization ─────────────────────────────────────────────────

  Map<String, dynamic> _settingsToMap(EditSettings s) => {
        'brightness': s.brightness,
        'contrast': s.contrast,
        'saturation': s.saturation,
        'vibrance': s.vibrance,
        'highlights': s.highlights,
        'shadows': s.shadows,
        'sharpness': s.sharpness,
        'clarity': s.clarity,
        'warmth': s.warmth,
        'tint': s.tint,
        'vignette': s.vignette,
        'dehaze': s.dehaze,
        'noiseReduction': s.noiseReduction,
        // HSL per channel
        'hslRedHue': s.hslRedHue, 'hslRedSat': s.hslRedSat, 'hslRedLum': s.hslRedLum,
        'hslOrangeHue': s.hslOrangeHue, 'hslOrangeSat': s.hslOrangeSat, 'hslOrangeLum': s.hslOrangeLum,
        'hslYellowHue': s.hslYellowHue, 'hslYellowSat': s.hslYellowSat, 'hslYellowLum': s.hslYellowLum,
        'hslGreenHue': s.hslGreenHue, 'hslGreenSat': s.hslGreenSat, 'hslGreenLum': s.hslGreenLum,
        'hslBlueHue': s.hslBlueHue, 'hslBlueSat': s.hslBlueSat, 'hslBlueLum': s.hslBlueLum,
        'hslPurpleHue': s.hslPurpleHue, 'hslPurpleSat': s.hslPurpleSat, 'hslPurpleLum': s.hslPurpleLum,
        // Perspective / blur
        'perspectiveVertical': s.perspectiveVertical,
        'perspectiveHorizontal': s.perspectiveHorizontal,
        'blurStrength': s.blurStrength,
        'curve': s.curve.map((c) => c.toMap()).toList(),
        // Brush masks
        'healMask': s.healMask.dabs.map((d) => d.toMap()).toList(),
        'focusMask': s.focusMask.dabs.map((d) => d.toMap()).toList(),
        'selectiveMask': s.selectiveMask.dabs.map((d) => d.toMap()).toList(),
        'selBrightness': s.selBrightness,
        'selContrast': s.selContrast,
        'selSaturation': s.selSaturation,
        'selWarmth': s.selWarmth,
        // Transform / crop / filter
        'rotation': s.rotation,
        'flipH': s.flipHorizontal,
        'flipV': s.flipVertical,
        'crop': s.cropRect?.toMap(),
        'filter': s.activeFilter,
      };

  // Lenient getters so older/partial rows still deserialize.
  double _d(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0.0;
  BrushMask _mask(Map m, String k) {
    final raw = m[k];
    if (raw is! List) return const BrushMask();
    return BrushMask(
      dabs: raw
          .map((e) => BrushDab.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  EditSettings _settingsFromMap(Map<String, dynamic> m) => EditSettings(
        brightness: _d(m, 'brightness'),
        contrast: _d(m, 'contrast'),
        saturation: _d(m, 'saturation'),
        vibrance: _d(m, 'vibrance'),
        highlights: _d(m, 'highlights'),
        shadows: _d(m, 'shadows'),
        sharpness: _d(m, 'sharpness'),
        clarity: _d(m, 'clarity'),
        warmth: _d(m, 'warmth'),
        tint: _d(m, 'tint'),
        vignette: _d(m, 'vignette'),
        dehaze: _d(m, 'dehaze'),
        noiseReduction: _d(m, 'noiseReduction'),
        hslRedHue: _d(m, 'hslRedHue'), hslRedSat: _d(m, 'hslRedSat'), hslRedLum: _d(m, 'hslRedLum'),
        hslOrangeHue: _d(m, 'hslOrangeHue'), hslOrangeSat: _d(m, 'hslOrangeSat'), hslOrangeLum: _d(m, 'hslOrangeLum'),
        hslYellowHue: _d(m, 'hslYellowHue'), hslYellowSat: _d(m, 'hslYellowSat'), hslYellowLum: _d(m, 'hslYellowLum'),
        hslGreenHue: _d(m, 'hslGreenHue'), hslGreenSat: _d(m, 'hslGreenSat'), hslGreenLum: _d(m, 'hslGreenLum'),
        hslBlueHue: _d(m, 'hslBlueHue'), hslBlueSat: _d(m, 'hslBlueSat'), hslBlueLum: _d(m, 'hslBlueLum'),
        hslPurpleHue: _d(m, 'hslPurpleHue'), hslPurpleSat: _d(m, 'hslPurpleSat'), hslPurpleLum: _d(m, 'hslPurpleLum'),
        perspectiveVertical: _d(m, 'perspectiveVertical'),
        perspectiveHorizontal: _d(m, 'perspectiveHorizontal'),
        blurStrength: _d(m, 'blurStrength'),
        curve: (m['curve'] is List)
            ? (m['curve'] as List)
                .map((e) => CurvePoint.fromMap(Map<String, dynamic>.from(e as Map)))
                .toList()
            : const [],
        healMask: _mask(m, 'healMask'),
        focusMask: _mask(m, 'focusMask'),
        selectiveMask: _mask(m, 'selectiveMask'),
        selBrightness: _d(m, 'selBrightness'),
        selContrast: _d(m, 'selContrast'),
        selSaturation: _d(m, 'selSaturation'),
        selWarmth: _d(m, 'selWarmth'),
        rotation: _d(m, 'rotation'),
        flipHorizontal: m['flipH'] as bool? ?? false,
        flipVertical: m['flipV'] as bool? ?? false,
        cropRect: m['crop'] != null
            ? CropRect.fromMap(Map<String, dynamic>.from(m['crop'] as Map))
            : null,
        activeFilter: m['filter'] as String?,
      );
}
