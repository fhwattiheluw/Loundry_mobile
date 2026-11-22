import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Kunci enkripsi database (NFR-05).
///
/// Kunci dibuat acak sekali saat aplikasi pertama dipasang, lalu disimpan di
/// penyimpanan aman bawaan Android (Keystore). Kunci TIDAK PERNAH ditulis ke
/// dalam kode maupun ke dalam database itu sendiri.
///
/// Konsekuensi yang harus dipahami pemilik: kalau aplikasi dihapus,
/// kuncinya ikut hilang, dan berkas database lama tidak bisa dibuka lagi.
/// Karena itu backup tetap wajib, dan backup disimpan sebagai berkas
/// yang terenkripsi dengan kunci yang sama.
class DatabaseKey {
  // Bukan const: kunci yang sudah diambil disimpan di _cached, dan
  // konstruktor const melarang field yang bisa berubah.
  DatabaseKey();

  static const _storageKey = 'db_encryption_key_v1';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _cached;

  /// Mengambil kunci yang tersimpan, atau membuat kunci baru bila ini
  /// pemasangan pertama.
  Future<String> obtain() async {
    if (_cached != null) return _cached!;

    final existing = await _storage.read(key: _storageKey);
    if (existing != null && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }

    final fresh = _generate();
    await _storage.write(key: _storageKey, value: fresh);
    _cached = fresh;
    return fresh;
  }

  /// Benar bila kunci sudah pernah dibuat. Dipakai untuk membedakan
  /// pemasangan baru dari pemasangan yang kuncinya hilang.
  Future<bool> exists() async {
    final value = await _storage.read(key: _storageKey);
    return value != null && value.isNotEmpty;
  }

  /// 32 byte acak dari Random.secure, bukan Random biasa.
  /// Random biasa bisa ditebak bila penyerang tahu waktu pembuatannya.
  String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
