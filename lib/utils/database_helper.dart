import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/edit_settings.dart';

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
        'rotation': s.rotation,
        'flipH': s.flipHorizontal,
        'flipV': s.flipVertical,
        'filter': s.activeFilter,
      };

  EditSettings _settingsFromMap(Map<String, dynamic> m) => EditSettings(
        brightness: (m['brightness'] as num).toDouble(),
        contrast: (m['contrast'] as num).toDouble(),
        saturation: (m['saturation'] as num).toDouble(),
        vibrance: (m['vibrance'] as num).toDouble(),
        highlights: (m['highlights'] as num).toDouble(),
        shadows: (m['shadows'] as num).toDouble(),
        sharpness: (m['sharpness'] as num).toDouble(),
        clarity: (m['clarity'] as num).toDouble(),
        warmth: (m['warmth'] as num).toDouble(),
        tint: (m['tint'] as num).toDouble(),
        vignette: (m['vignette'] as num).toDouble(),
        dehaze: (m['dehaze'] as num).toDouble(),
        noiseReduction: (m['noiseReduction'] as num).toDouble(),
        rotation: (m['rotation'] as num).toDouble(),
        flipHorizontal: m['flipH'] as bool,
        flipVertical: m['flipV'] as bool,
        activeFilter: m['filter'] as String?,
      );
}
