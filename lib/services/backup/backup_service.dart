import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import '../../data/db/app_database.dart';
import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';

class BackupResult {
  const BackupResult.ok(this.message, {this.file})
      : success = true,
        cancelled = false;
  const BackupResult.failed(this.message)
      : success = false,
        cancelled = false,
        file = null;

  /// Pemilik menutup lembar bagikan tanpa mengirim ke mana pun. Bukan
  /// kegagalan, tapi juga bukan backup yang boleh dihitung selesai.
  const BackupResult.cancelled(this.message, {this.file})
      : success = false,
        cancelled = true;

  final bool success;
  final bool cancelled;
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

/// Jenis folder backup otomatis.
enum BackupFolderKind { app, download, documents, custom }

/// Folder backup yang sedang dipakai.
class BackupFolder {
  const BackupFolder({required this.kind, required this.path, this.problem});

  final BackupFolderKind kind;
  final String path;

  /// Terisi bila folder pilihan pemilik tidak bisa dipakai dan backup
  /// sementara jatuh ke folder aplikasi.
  final String? problem;

  /// Folder di luar Android/data tidak ikut terhapus saat aplikasi dicopot.
  bool get survivesUninstall => kind != BackupFolderKind.app;
}

/// Nama subfolder di Download atau Documents.
const backupSubfolder = 'LaundryManise';

/// Akar penyimpanan bersama dari folder milik aplikasi:
/// /storage/emulated/0/Android/data/<paket>/files menjadi /storage/emulated/0.
String? sharedStorageRoot(String appExternalDir) {
  final i = appExternalDir.indexOf('/Android/');
  return i <= 0 ? null : appExternalDir.substring(0, i);
}

/// Pilihan yang tersimpan di pengaturan menjadi jenis folder.
BackupFolderKind folderKindOf(String pref) => switch (pref.trim()) {
      '' || 'app' => BackupFolderKind.app,
      'download' => BackupFolderKind.download,
      'documents' => BackupFolderKind.documents,
      _ => BackupFolderKind.custom,
    };

/// Jalur lengkap untuk sebuah pilihan. Null bila penyimpanan bersama
/// tidak diketahui, misalnya di luar Android.
String? folderPathFor(
  String pref, {
  required String appFolder,
  required String? storageRoot,
}) {
  return switch (folderKindOf(pref)) {
    BackupFolderKind.app => appFolder,
    BackupFolderKind.download => storageRoot == null
        ? null
        : p.join(storageRoot, 'Download', backupSubfolder),
    BackupFolderKind.documents => storageRoot == null
        ? null
        : p.join(storageRoot, 'Documents', backupSubfolder),
    BackupFolderKind.custom => pref.trim(),
  };
}

/// Backup adalah satu-satunya pengaman data di aplikasi ini.
///
/// Tidak ada server, jadi ponsel hilang, rusak, atau aplikasi terhapus berarti
/// seluruh riwayat dan piutang hilang permanen. Karena itu backup otomatis
/// dijalankan setiap aplikasi dibuka, dan pemilik diingatkan mengekspor
/// salinannya ke luar perangkat.
class BackupService {
  BackupService(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  static const _folderName = 'backup';
  static const _keepCount = 7;

  /// Folder milik aplikasi: Android/data/<paket>/files/backup.
  ///
  /// Selalu bisa ditulis tanpa izin, karena itu menjadi folder bawaan dan
  /// tempat jatuh bila folder pilihan pemilik tidak bisa dipakai. Folder
  /// ini ikut terhapus bila aplikasi dicopot.
  Future<String> _appFolderPath() async {
    Directory? base;

    if (Platform.isAndroid) {
      try {
        base = await getExternalStorageDirectory();
      } catch (_) {
        base = null;
      }
    }

    base ??= await getApplicationDocumentsDirectory();
    return p.join(base.path, _folderName);
  }

  /// Akar penyimpanan bersama, misalnya /storage/emulated/0.
  Future<String?> _storageRoot() async {
    if (!Platform.isAndroid) return null;
    try {
      final ext = await getExternalStorageDirectory();
      return ext == null ? null : sharedStorageRoot(ext.path);
    } catch (_) {
      return null;
    }
  }

  /// Uji tulis sungguhan: membuat folder, menulis berkas kecil, lalu
  /// menghapusnya. Lebih jujur daripada menebak dari versi Android, karena
  /// aturan penyimpanan berbeda antar versi dan antar merek HP.
  Future<bool> _canWrite(String path) async {
    try {
      await Directory(path).create(recursive: true);
      final probe = File(p.join(path, '.cek-tulis'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Folder backup yang benar-benar dipakai sekarang.
  ///
  /// Bila folder pilihan pemilik tidak bisa ditulis (izin dicabut, kartu
  /// memori dicabut), backup tetap berjalan di folder aplikasi dan
  /// [BackupFolder.problem] terisi supaya layar bisa memperingatkan.
  /// Backup otomatis tidak boleh berhenti diam-diam.
  Future<BackupFolder> currentFolder() async {
    final pref = _settings.get(SettingsKeys.backupFolder);
    final kind = folderKindOf(pref);
    final appFolder = await _appFolderPath();

    if (kind != BackupFolderKind.app) {
      final path = folderPathFor(
        pref,
        appFolder: appFolder,
        storageRoot: await _storageRoot(),
      );

      if (path != null && await _canWrite(path)) {
        return BackupFolder(kind: kind, path: path);
      }

      await Directory(appFolder).create(recursive: true);
      return BackupFolder(
        kind: BackupFolderKind.app,
        path: appFolder,
        problem: 'Folder pilihan Anda (${path ?? pref}) tidak bisa ditulis. '
            'Backup sementara disimpan di folder aplikasi. Pilih ulang '
            'foldernya.',
      );
    }

    await Directory(appFolder).create(recursive: true);
    return BackupFolder(kind: BackupFolderKind.app, path: appFolder);
  }

  /// Mengganti folder backup otomatis.
  ///
  /// Folder diuji dulu dengan menulis sungguhan. Di Android 8 sampai 10
  /// izin penyimpanan diminta bila perlu. Di Android 11 ke atas izin itu
  /// tidak dideklarasikan, sehingga permintaannya langsung ditolak tanpa
  /// dialog, dan memang tidak dibutuhkan: folder Download dan Documents
  /// bisa ditulis tanpa izin.
  ///
  /// Mengembalikan null bila berhasil, atau alasan yang bisa dibaca pemilik.
  Future<String?> changeFolder(String pref) async {
    final kind = folderKindOf(pref);
    final path = folderPathFor(
      pref,
      appFolder: await _appFolderPath(),
      storageRoot: await _storageRoot(),
    );

    if (path == null) {
      return 'Penyimpanan bersama tidak ditemukan di perangkat ini.';
    }

    var ok = await _canWrite(path);

    if (!ok && Platform.isAndroid && kind != BackupFolderKind.app) {
      final status = await Permission.storage.request();
      if (status.isGranted) ok = await _canWrite(path);
    }

    if (!ok) {
      return kind == BackupFolderKind.custom
          ? 'Folder itu tidak bisa ditulis. Android hanya mengizinkan '
              'aplikasi menyimpan berkas di dalam folder Download atau '
              'Documents. Pilih folder di dalam salah satunya.'
          : 'Folder itu tidak bisa ditulis di HP ini.';
    }

    await _settings.set(
      SettingsKeys.backupFolder,
      kind == BackupFolderKind.app ? '' : pref,
    );
    return null;
  }

  Future<Directory> _backupDir() async =>
      Directory((await currentFolder()).path);

  /// Jalur folder backup apa adanya, untuk ditampilkan di Pengaturan.
  /// Pemilik yang tahu jalurnya bisa menemukan berkasnya sendiri.
  Future<String> backupFolderPath() async => (await currentFolder()).path;

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
      final shared = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.file!.path)],
          subject: 'Backup Laundry Manise',
          text: 'Simpan berkas ini di tempat pribadi di luar ponsel. '
              'Isinya memuat data pelanggan dan riwayat transaksi, '
              'jadi jangan dikirim ke grup.',
        ),
      );

      // Android sering tidak melaporkan hasil bagikan (status unavailable),
      // jadi hanya penutupan yang jelas-jelas dilaporkan yang ditolak.
      if (shared.status == ShareResultStatus.dismissed) {
        return BackupResult.cancelled(
          'Backup belum dibagikan. Coba lagi dan pilih tujuan pengiriman.',
          file: result.file,
        );
      }

      return BackupResult.ok('Backup siap dibagikan.', file: result.file);
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
