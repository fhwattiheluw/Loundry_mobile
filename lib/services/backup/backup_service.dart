import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/db/app_database.dart';

class BackupResult {
  const BackupResult.ok(this.message, {this.file})
      : success = true;
  const BackupResult.failed(this.message)
      : success = false,
        file = null;

  final bool success;
  final String message;
  final File? file;
}

class BackupInfo {
  const BackupInfo({
    required this.file,
    required this.createdAt,
    required this.sizeBytes,
  });

  final File file;
  final DateTime createdAt;
  final int sizeBytes;

  String get name => p.basename(file.path);
  String get sizeLabel => '${(sizeBytes / 1024).round()} KB';
}

/// Backup adalah satu-satunya pengaman data di aplikasi ini.
///
/// Tidak ada server, jadi ponsel hilang, rusak, atau aplikasi terhapus berarti
/// seluruh riwayat dan piutang hilang permanen. Karena itu backup otomatis
/// dijalankan setiap aplikasi dibuka, dan pemilik diingatkan mengekspor
/// salinannya ke luar perangkat.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const _folderName = 'backup';
  static const _keepCount = 7;

  Future<Directory> _backupDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _databaseFile() async {
    final dir = await getDatabasesPath();
    return File(p.join(dir, 'laundry_pos.db'));
  }

  String _stamp(DateTime at) =>
      '${at.year}'
      '${at.month.toString().padLeft(2, '0')}'
      '${at.day.toString().padLeft(2, '0')}'
      '-'
      '${at.hour.toString().padLeft(2, '0')}'
      '${at.minute.toString().padLeft(2, '0')}';

  /// Menyalin database ke folder backup di dalam penyimpanan aplikasi.
  ///
  /// Database ditutup lebih dulu agar seluruh isi WAL ikut tersalin. Backup
  /// yang diambil saat database terbuka bisa kehilangan transaksi terakhir.
  Future<BackupResult> createLocal() async {
    try {
      final source = await _databaseFile();
      if (!await source.exists()) {
        return const BackupResult.failed('Database belum ada.');
      }

      await _db.close();

      final dir = await _backupDir();
      final now = DateTime.now();
      final target = File(p.join(dir.path, 'laundry-${_stamp(now)}.db'));

      await source.copy(target.path);
      await _rotate(dir);

      return BackupResult.ok(
        'Backup tersimpan di perangkat.',
        file: target,
      );
    } catch (e) {
      return BackupResult.failed('Backup gagal: $e');
    }
  }

  /// Menyisakan [_keepCount] backup terbaru. Tanpa ini, penyimpanan konter
  /// yang pas-pasan akan penuh dalam beberapa bulan.
  Future<void> _rotate(Directory dir) async {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));

    for (final file in files.skip(_keepCount)) {
      try {
        await file.delete();
      } catch (_) {
        // Berkas sedang dipakai proses lain. Akan terhapus di rotasi berikutnya.
      }
    }
  }

  /// Backup otomatis maksimal sekali sehari. Dipanggil saat aplikasi dibuka.
  Future<void> autoBackupIfDue() async {
    try {
      final dir = await _backupDir();
      final today = _stamp(DateTime.now()).substring(0, 8);

      final existsToday = dir
          .listSync()
          .whereType<File>()
          .any((f) => p.basename(f.path).contains(today));

      if (!existsToday) await createLocal();
    } catch (_) {
      // Backup otomatis tidak boleh menghalangi aplikasi dibuka.
    }
  }

  Future<List<BackupInfo>> list() async {
    final dir = await _backupDir();

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));

    return files.map((f) {
      final stat = f.statSync();
      return BackupInfo(
        file: f,
        createdAt: stat.modified,
        sizeBytes: stat.size,
      );
    }).toList();
  }

  /// Membagikan backup ke luar perangkat: WhatsApp, email, Google Drive.
  ///
  /// Backup yang hanya tersimpan di dalam ponsel tidak menolong saat
  /// ponselnya yang hilang.
  Future<BackupResult> shareLatest() async {
    final result = await createLocal();
    if (!result.success || result.file == null) return result;

    try {
      await Share.shareXFiles(
        [XFile(result.file!.path)],
        subject: 'Backup POS Laundry',
        text: 'Simpan berkas ini di tempat aman di luar ponsel.',
      );
      return const BackupResult.ok('Backup siap dibagikan.');
    } catch (e) {
      return BackupResult.failed('Gagal membagikan backup: $e');
    }
  }

  /// Mengembalikan data dari berkas backup.
  ///
  /// Sebelum menimpa, database yang sedang dipakai disalin dulu ke
  /// `pre-restore`. Kalau berkas backup ternyata rusak, data lama masih bisa
  /// diselamatkan secara manual.
  Future<BackupResult> restoreFrom(File backup) async {
    try {
      if (!await backup.exists()) {
        return const BackupResult.failed('Berkas backup tidak ditemukan.');
      }

      if (!await _looksLikeSqlite(backup)) {
        return const BackupResult.failed(
          'Berkas itu bukan backup POS Laundry yang sah.',
        );
      }

      final target = await _databaseFile();
      await _db.close();

      if (await target.exists()) {
        final dir = await _backupDir();
        await target.copy(
          p.join(dir.path, 'pre-restore-${_stamp(DateTime.now())}.db'),
        );
      }

      await backup.copy(target.path);

      // Dibuka ulang untuk memastikan berkasnya benar-benar bisa dipakai.
      await _db.database;

      return const BackupResult.ok(
        'Data berhasil dikembalikan. Tutup dan buka ulang aplikasi.',
      );
    } catch (e) {
      return BackupResult.failed('Restore gagal: $e');
    }
  }

  /// Berkas SQLite selalu diawali teks "SQLite format 3".
  /// Memeriksanya mencegah pemilik salah memilih foto atau dokumen lain.
  Future<bool> _looksLikeSqlite(File file) async {
    try {
      final handle = await file.open();
      final header = await handle.read(16);
      await handle.close();

      return String.fromCharCodes(header.take(15)) == 'SQLite format 3';
    } catch (_) {
      return false;
    }
  }
}
