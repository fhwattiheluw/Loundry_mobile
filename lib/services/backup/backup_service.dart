import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

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

  /// Folder tempat backup otomatis disimpan.
  ///
  /// Di Android dipilih penyimpanan luar milik aplikasi, bukan folder
  /// dalam: jalurnya bisa dibuka pemilik lewat Pengelola File mana pun,
  /// sehingga berkasnya bisa disalin ke flashdisk atau dilampirkan ke
  /// WhatsApp tanpa lewat aplikasi ini.
  ///
  /// Folder Download dan Documents tidak dipakai. Sejak Android 10 aplikasi
  /// tidak boleh menulis ke sana tanpa izin akses seluruh penyimpanan, dan
  /// izin itu hampir selalu ditolak Google Play untuk aplikasi kasir.
  ///
  /// Yang harus diingat: folder ini ikut terhapus bila aplikasi dicopot.
  /// Backup di dalam HP yang sama tidak menolong saat HP-nya hilang, jadi
  /// salinan mingguan ke luar HP tetap wajib.
  Future<Directory> _backupDir() async {
    Directory? base;

    if (Platform.isAndroid) {
      try {
        base = await getExternalStorageDirectory();
      } catch (_) {
        base = null;
      }
    }

    base ??= await getApplicationDocumentsDirectory();

    final dir = Directory(p.join(base.path, _folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Jalur folder backup apa adanya, untuk ditampilkan di Pengaturan.
  /// Pemilik yang tahu jalurnya bisa menemukan berkasnya sendiri.
  Future<String> backupFolderPath() async => (await _backupDir()).path;

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

  /// Membuat backup yang bisa dibuka di perangkat lain.
  ///
  /// Database aslinya terenkripsi dengan kunci yang hanya ada di Keystore
  /// ponsel ini. Menyalin berkasnya mentah-mentah akan menghasilkan backup
  /// yang tidak bisa dipulihkan di ponsel baru, yaitu justru saat backup
  /// paling dibutuhkan.
  ///
  /// Karena itu isi database diekspor ke salinan TANPA enkripsi memakai
  /// `sqlcipher_export`. Konsekuensinya berkas backup bisa dibaca siapa pun
  /// yang memegangnya, jadi pemilik diingatkan menyimpannya di tempat
  /// pribadi, bukan di grup WhatsApp.
  Future<BackupResult> createLocal() async {
    try {
      final source = await _databaseFile();
      if (!await source.exists()) {
        return const BackupResult.failed('Database belum ada.');
      }

      final dir = await _backupDir();
      final now = DateTime.now();
      final target = File(p.join(dir.path, 'laundry-${_stamp(now)}.db'));

      if (await target.exists()) await target.delete();

      final exported = await _exportPlain(target);

      if (!exported) {
        // Perangkat tidak mendukung sqlcipher_export. Salin mentah supaya
        // tetap ada backup, meski hanya bisa dipulihkan di ponsel ini.
        await _db.close();
        await source.copy(target.path);
      }

      await _rotate(dir);

      return BackupResult.ok(
        exported
            ? 'Backup tersimpan di perangkat.'
            : 'Backup tersimpan, tapi hanya bisa dipulihkan di ponsel ini.',
        file: target,
      );
    } catch (e) {
      return BackupResult.failed('Backup gagal: $e');
    }
  }

  /// Menyalin seluruh isi database ke berkas tanpa enkripsi.
  /// Mengembalikan false bila perintah SQLCipher tidak tersedia.
  Future<bool> _exportPlain(File target) async {
    try {
      final db = await _db.database;
      final path = target.path.replaceAll("'", "''");

      await db.rawQuery("ATTACH DATABASE '$path' AS plainbackup KEY ''");
      await db.rawQuery("SELECT sqlcipher_export('plainbackup')");
      await db.rawQuery('DETACH DATABASE plainbackup');

      return await target.exists();
    } catch (_) {
      return false;
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
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.file!.path)],
          subject: 'Backup Laundry Manise',
          text: 'Simpan berkas ini di tempat pribadi di luar ponsel. '
              'Isinya memuat data pelanggan dan riwayat transaksi, '
              'jadi jangan dikirim ke grup.',
        ),
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
          'Berkas itu bukan backup Laundry Manise yang sah.',
        );
      }

      final target = await _databaseFile();

      // Salinan pengaman: kalau berkas backup ternyata tidak utuh,
      // data lama masih bisa diselamatkan secara manual.
      if (await target.exists()) {
        final dir = await _backupDir();
        await createLocal();
        await target.copy(
          p.join(dir.path, 'pre-restore-${_stamp(DateTime.now())}.db'),
        );
      }

      await _db.close();
      await target.delete().catchError((_) => target);

      // Backup tanpa enkripsi diimpor dengan membalik sqlcipher_export:
      // berkas backup dibuka apa adanya, lalu isinya ditulis ke database
      // baru yang terenkripsi dengan kunci ponsel ini.
      final imported = await _importPlain(backup, target);

      if (!imported) {
        // Backup ternyata sudah terenkripsi dengan kunci ponsel ini.
        await backup.copy(target.path);
      }

      // Dibuka ulang untuk memastikan berkasnya benar-benar bisa dipakai.
      await _db.database;

      return const BackupResult.ok(
        'Data berhasil dikembalikan. Tutup dan buka ulang aplikasi.',
      );
    } catch (e) {
      return BackupResult.failed('Restore gagal: $e');
    }
  }

  /// Menulis isi backup tanpa enkripsi ke database baru yang terenkripsi.
  /// Mengembalikan false bila backup itu ternyata sudah terenkripsi.
  Future<bool> _importPlain(File backup, File target) async {
    cipher.Database? plain;

    try {
      final key = await _db.encryptionKey();
      final path = target.path.replaceAll("'", "''");

      // Password kosong berarti berkas dibuka sebagai SQLite biasa.
      plain = await cipher.openDatabase(backup.path, password: '');

      await plain.rawQuery(
        "ATTACH DATABASE '$path' AS encrypted KEY '${key.replaceAll("'", "''")}'",
      );
      await plain.rawQuery("SELECT sqlcipher_export('encrypted')");
      await plain.rawQuery('DETACH DATABASE encrypted');

      return await target.exists();
    } catch (_) {
      return false;
    } finally {
      await plain?.close();
    }
  }

  /// Berkas SQLite selalu diawali teks "SQLite format 3".
  /// Memeriksanya mencegah pemilik salah memilih foto atau dokumen lain.
  Future<bool> _looksLikeSqlite(File file) async {
    try {
      final handle = await file.open();
      final header = await handle.read(16);
      await handle.close();

      if (String.fromCharCodes(header.take(15)) == 'SQLite format 3') {
        return true;
      }

      // Backup yang masih terenkripsi tidak punya header itu, karena seluruh
      // berkasnya teracak. Yang bisa diperiksa hanyalah ukurannya masuk akal.
      // Berkas foto atau dokumen yang salah pilih akan gagal saat dibuka,
      // dan salinan pengaman sudah dibuat sebelum itu terjadi.
      return await file.length() > 4096;
    } catch (_) {
      return false;
    }
  }
}
