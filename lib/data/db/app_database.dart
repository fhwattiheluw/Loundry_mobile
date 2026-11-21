import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sql;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import 'database_key.dart';
import 'seed.dart';

/// Database lokal. Tidak ada server: seluruh data hidup di file ini.
///
/// Aturan migrasi: JANGAN pernah mengubah blok `_v1`. Setiap perubahan skema
/// menambah nomor versi baru dan satu blok migrasi di [_migrate], supaya
/// pembaruan aplikasi tidak menghapus data pengguna (NFR-13).
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _fileName = 'laundry_pos.db';
  static const _schemaVersion = 2;

  final _key = const DatabaseKey();

  sql.Database? _db;

  Future<sql.Database> get database async => _db ??= await _open();

  /// Membuka database terenkripsi di perangkat.
  ///
  /// Kuncinya diambil dari Android Keystore, bukan ditulis di kode. Berkas
  /// database di luar aplikasi tidak bisa dibaca tanpa kunci itu, bahkan
  /// pada perangkat yang sudah di-root.
  Future<sql.Database> _open() async {
    final dir = await sql.getDatabasesPath();
    final path = p.join(dir, _fileName);
    final password = await _key.obtain();

    return cipher.openDatabase(
      path,
      password: password,
      version: _schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _v1(db);
        await _v2(db);
        await seedInitialData(db);
      },
      onUpgrade: _migrate,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Kunci enkripsi database, dipakai saat mengekspor dan memulihkan backup.
  Future<String> encryptionKey() => _key.obtain();

  /// Hanya dipakai oleh pengujian, dan sengaja TIDAK terenkripsi.
  ///
  /// Pengujian berjalan di desktop lewat sqflite_common_ffi, yang tidak
  /// memuat pustaka SQLCipher. Yang diuji di sini adalah skema dan kueri,
  /// bukan enkripsinya.
  Future<sql.Database> openInMemory() async {
    final db = await sql.openDatabase(
      sql.inMemoryDatabasePath,
      version: _schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await _v1(db);
        await _v2(db);
        await seedInitialData(db);
      },
    );
    _db = db;
    return db;
  }

  /// Migrasi dijalankan bertahap dan tidak pernah melompat, supaya pemasangan
  /// lama dari versi mana pun sampai ke bentuk skema yang sama.
  Future<void> _migrate(sql.Database db, int from, int to) async {
    if (from < 2) await _v2(db);
  }

  /// Versi 2: antrean kirim ulang notifikasi (FR-69).
  ///
  /// Pesan yang gagal kirim disimpan beserta isinya, jumlah percobaan, dan
  /// kapan boleh dicoba lagi. Tanpa menyimpan isi pesannya, kirim ulang akan
  /// memakai template yang mungkin sudah diubah pemilik sejak itu.
  Future<void> _v2(sql.Database db) async {
    await db.execute(
        'ALTER TABLE notification_logs ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE notification_logs ADD COLUMN next_attempt_at TEXT');
    await db.execute('ALTER TABLE notification_logs ADD COLUMN message TEXT');

    await db.execute(
      'CREATE INDEX idx_notif_queue ON notification_logs(status, next_attempt_at)',
    );
  }

  Future<void> _v1(sql.Database db) async {
    await db.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE users (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        name     TEXT    NOT NULL,
        pin_hash TEXT    NOT NULL,
        role     TEXT    NOT NULL,
        active   INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        name           TEXT    NOT NULL,
        phone          TEXT    NOT NULL UNIQUE,
        address        TEXT,
        note           TEXT,
        notify_enabled INTEGER NOT NULL DEFAULT 1,
        created_at     TEXT    NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_customers_name ON customers(name)');

    await db.execute('''
      CREATE TABLE services (
        id                     INTEGER PRIMARY KEY AUTOINCREMENT,
        name                   TEXT    NOT NULL,
        unit                   TEXT    NOT NULL,
        price                  INTEGER NOT NULL,
        duration_hours         INTEGER NOT NULL,
        min_qty                REAL    NOT NULL DEFAULT 0,
        rounding_step          REAL    NOT NULL DEFAULT 0,
        express_multiplier     REAL    NOT NULL DEFAULT 2.0,
        express_duration_hours INTEGER NOT NULL DEFAULT 6,
        active                 INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        order_no       TEXT    NOT NULL UNIQUE,
        customer_id    INTEGER NOT NULL REFERENCES customers(id),
        created_by     INTEGER NOT NULL REFERENCES users(id),
        created_at     TEXT    NOT NULL,
        estimated_at   TEXT    NOT NULL,
        laundry_status TEXT    NOT NULL,
        payment_status TEXT    NOT NULL,
        subtotal       INTEGER NOT NULL,
        discount       INTEGER NOT NULL DEFAULT 0,
        total          INTEGER NOT NULL,
        note           TEXT,
        picked_up_at   TEXT,
        picked_up_by   TEXT,
        cancelled_at   TEXT,
        cancel_reason  TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_orders_created ON orders(created_at)');
    await db.execute(
        'CREATE INDEX idx_orders_status ON orders(laundry_status, payment_status)');
    await db.execute(
        'CREATE INDEX idx_orders_customer ON orders(customer_id)');

    await db.execute('''
      CREATE TABLE order_items (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id     INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        service_id   INTEGER NOT NULL,
        service_name TEXT    NOT NULL,
        unit         TEXT    NOT NULL,
        qty          REAL    NOT NULL,
        unit_price   INTEGER NOT NULL,
        subtotal     INTEGER NOT NULL,
        express      INTEGER NOT NULL DEFAULT 0,
        note         TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_order_items_order ON order_items(order_id)');

    await db.execute('''
      CREATE TABLE shifts (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id       INTEGER NOT NULL REFERENCES users(id),
        opened_at     TEXT    NOT NULL,
        closed_at     TEXT,
        opening_cash  INTEGER NOT NULL DEFAULT 0,
        closing_cash  INTEGER,
        expected_cash INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id    INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        shift_id    INTEGER REFERENCES shifts(id),
        paid_at     TEXT    NOT NULL,
        amount      INTEGER NOT NULL,
        method      TEXT    NOT NULL,
        received_by INTEGER NOT NULL REFERENCES users(id),
        note        TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_payments_paid_at ON payments(paid_at)');
    await db.execute('CREATE INDEX idx_payments_order ON payments(order_id)');

    await db.execute('''
      CREATE TABLE notification_logs (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id   INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        trigger_name TEXT  NOT NULL,
        target     TEXT    NOT NULL,
        sent_at    TEXT    NOT NULL,
        status     TEXT    NOT NULL,
        error      TEXT
      )
    ''');
    // Satu pemicu hanya boleh berhasil sekali per order (FR-71).
    await db.execute('''
      CREATE UNIQUE INDEX idx_notif_once
      ON notification_logs(order_id, trigger_name)
      WHERE status = 'terkirim'
    ''');

    await db.execute('''
      CREATE TABLE status_logs (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id   INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        status     TEXT    NOT NULL,
        changed_at TEXT    NOT NULL,
        user_id    INTEGER NOT NULL REFERENCES users(id)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_status_logs_order ON status_logs(order_id)');
  }
}
