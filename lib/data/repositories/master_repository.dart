import 'package:sqflite/sqflite.dart';

import '../../core/security.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../db/app_database.dart';

class CustomerRepository {
  CustomerRepository(this._db);

  final AppDatabase _db;

  Future<List<Customer>> search(String query, {int limit = 30}) async {
    final db = await _db.database;
    final term = query.trim();

    // Kata kunci tanpa satu pun angka ("Budi") menghasilkan nomor kosong
    // setelah dinormalkan. Pola LIKE '%%' cocok dengan SEMUA baris, jadi
    // bila klausa nomor ikut dipasang, mencari nama selalu mengembalikan
    // seluruh pelanggan.
    final digits = normalizePhone(term);

    final rows = term.isEmpty
        ? await db.query('customers', orderBy: 'name COLLATE NOCASE', limit: limit)
        : await db.query(
            'customers',
            where: digits.isEmpty ? 'name LIKE ?' : 'name LIKE ? OR phone LIKE ?',
            whereArgs: [
              '%$term%',
              if (digits.isNotEmpty) '%$digits%',
            ],
            orderBy: 'name COLLATE NOCASE',
            limit: limit,
          );

    return rows.map(Customer.fromMap).toList();
  }

  /// Mencari pelanggan dari nomornya. Nomor kosong tidak pernah cocok:
  /// pelanggan tanpa nomor tidak bisa dibedakan lewat nomor.
  Future<Customer?> findByPhone(String rawPhone) async {
    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) return null;

    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: 'phone = ?',
      whereArgs: [phone],
      limit: 1,
    );
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<Customer?> findById(int id) async {
    final db = await _db.database;
    final rows =
        await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  /// Menyimpan pelanggan baru, atau mengembalikan yang sudah ada bila
  /// nomornya sama. Duplikat pelanggan adalah sumber kekacauan paling umum
  /// di data laundry.
  ///
  /// Pelanggan tanpa nomor HP dikenali dari namanya (huruf besar kecil tidak
  /// dibedakan). Tanpa aturan ini, semua pelanggan tanpa nomor melebur jadi
  /// satu orang dan order mereka tercatat atas nama pelanggan yang pertama.
  Future<Customer> saveOrGet(Customer customer) async {
    final phone = normalizePhone(customer.phone);
    final db = await _db.database;

    if (phone.isEmpty) {
      final rows = await db.query(
        'customers',
        where: "phone = '' AND name = ? COLLATE NOCASE",
        whereArgs: [customer.name.trim()],
        limit: 1,
      );
      if (rows.isNotEmpty) return Customer.fromMap(rows.first);
    } else {
      final existing = await findByPhone(phone);
      if (existing != null) return existing;
    }

    final id = await db.insert('customers', {
      ...customer.toMap(),
      'name': customer.name.trim(),
      'phone': phone,
      'created_at': DateTime.now().toIso8601String(),
    });

    return customer.copyWith(id: id, phone: phone);
  }

  Future<void> update(Customer customer) async {
    final db = await _db.database;
    await db.update(
      'customers',
      {...customer.toMap(), 'phone': normalizePhone(customer.phone)},
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<int> count() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM customers');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Menambahkan banyak pelanggan sekaligus dari impor CSV (FR-13).
  ///
  /// Nomor yang sudah ada dilewati, bukan ditimpa: data pelanggan lama
  /// biasanya lebih akurat daripada berkas impor yang entah dari mana.
  Future<ImportReport> importMany(List<Customer> rows) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();

    var added = 0;
    var skipped = 0;
    final invalid = <String>[];

    await db.transaction((txn) async {
      for (final row in rows) {
        final name = row.name.trim();
        final phone = normalizePhone(row.phone);

        if (name.isEmpty || !isValidPhone(phone)) {
          invalid.add(name.isEmpty ? '(tanpa nama)' : name);
          continue;
        }

        final existing = await txn.query('customers',
            where: 'phone = ?', whereArgs: [phone], limit: 1);

        if (existing.isNotEmpty) {
          skipped++;
          continue;
        }

        await txn.insert('customers', {
          'name': name,
          'phone': phone,
          'address': row.address,
          'note': row.note,
          'notify_enabled': 1,
          'created_at': now,
        });
        added++;
      }
    });

    return ImportReport(added: added, skipped: skipped, invalid: invalid);
  }

  /// Pelanggan yang boleh dikirimi pesan promo (FR-64).
  Future<List<Customer>> broadcastTargets() async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: "notify_enabled = 1 AND phone != ''",
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Customer.fromMap).toList();
  }
}

class ImportReport {
  const ImportReport({
    required this.added,
    required this.skipped,
    required this.invalid,
  });

  final int added;
  final int skipped;
  final List<String> invalid;

  String get summary {
    final parts = ['$added pelanggan ditambahkan'];
    if (skipped > 0) parts.add('$skipped sudah ada');
    if (invalid.isNotEmpty) parts.add('${invalid.length} baris tidak valid');
    return parts.join(', ');
  }
}

class ServiceRepository {
  ServiceRepository(this._db);

  final AppDatabase _db;

  Future<List<LaundryService>> all({bool activeOnly = true}) async {
    final db = await _db.database;
    final rows = await db.query(
      'services',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'active DESC, name COLLATE NOCASE',
    );
    return rows.map(LaundryService.fromMap).toList();
  }

  Future<int> insert(LaundryService service) async {
    final db = await _db.database;
    return db.insert('services', service.toMap());
  }

  Future<void> update(LaundryService service) async {
    final db = await _db.database;
    await db.update('services', service.toMap(),
        where: 'id = ?', whereArgs: [service.id]);
  }

  /// Layanan tidak pernah dihapus, hanya dinonaktifkan, supaya nota lama
  /// yang memakainya tetap bisa dibaca.
  Future<void> deactivate(int id) async {
    final db = await _db.database;
    await db.update('services', {'active': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Mengaktifkan lagi layanan yang tadi dinonaktifkan, untuk tombol
  /// "Urungkan" di layar layanan.
  Future<void> activate(int id) async {
    final db = await _db.database;
    await db.update('services', {'active': 1},
        where: 'id = ?', whereArgs: [id]);
  }
}

class UserRepository {
  UserRepository(this._db);

  final AppDatabase _db;

  Future<List<AppUser>> all({bool activeOnly = true}) async {
    final db = await _db.database;
    final rows = await db.query(
      'users',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'role, name',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  /// Pemilik pertama yang masih aktif. Dipakai pemulihan PIN, yang selalu
  /// menyasar akun pemilik, bukan kasir.
  Future<AppUser?> firstOwner() async {
    final users = await all();
    for (final user in users) {
      if (user.role == UserRole.owner) return user;
    }
    return null;
  }

  Future<AppUser?> authenticate(String pin) async {
    final db = await _db.database;
    final rows = await db.query('users', where: 'active = 1');

    for (final row in rows) {
      final user = AppUser.fromMap(row);
      if (verifyPin(pin, user.pinHash)) return user;
    }
    return null;
  }

  Future<int> insert(AppUser user) async {
    final db = await _db.database;
    return db.insert('users', user.toMap());
  }

  Future<void> setPin(int userId, String newPin) async {
    final db = await _db.database;
    await db.update('users', {'pin_hash': hashPin(newPin)},
        where: 'id = ?', whereArgs: [userId]);
  }

  Future<void> deactivate(int userId) async {
    final db = await _db.database;
    await db.update('users', {'active': 0},
        where: 'id = ?', whereArgs: [userId]);
  }

  /// Mencegah pemilik mengunci dirinya sendiri keluar dari aplikasi.
  Future<bool> isLastOwner(int userId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM users WHERE role = 'owner' AND active = 1 AND id != ?",
      [userId],
    );
    return (Sqflite.firstIntValue(result) ?? 0) == 0;
  }
}
