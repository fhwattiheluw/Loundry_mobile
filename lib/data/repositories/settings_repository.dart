import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

/// Pengaturan disimpan sebagai pasangan kunci dan nilai, bukan ditulis keras
/// di kode, supaya pemilik bisa mengubah teks nota dan template WhatsApp
/// tanpa menunggu rilis baru.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Map<String, String> _cache = {};
  bool _loaded = false;

  Future<Map<String, String>> loadAll({bool force = false}) async {
    if (_loaded && !force) return _cache;

    final db = await _db.database;
    final rows = await db.query('settings');

    _cache = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    _loaded = true;
    return _cache;
  }

  String get(String key, {String fallback = ''}) =>
      _cache[key] ?? fallback;

  int getInt(String key, {int fallback = 0}) =>
      int.tryParse(_cache[key] ?? '') ?? fallback;

  bool getBool(String key, {bool fallback = false}) {
    final value = _cache[key];
    if (value == null) return fallback;
    return value == '1' || value.toLowerCase() == 'true';
  }

  List<String> getList(String key) {
    final value = _cache[key];
    if (value == null || value.isEmpty) return const [];
    return value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> set(String key, String value) async {
    final db = await _db.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _cache[key] = value;
  }

  Future<void> setAll(Map<String, String> values) async {
    final db = await _db.database;
    final batch = db.batch();

    for (final entry in values.entries) {
      batch.insert(
        'settings',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    _cache.addAll(values);
  }
}
