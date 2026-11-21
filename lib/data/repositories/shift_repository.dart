import 'package:sqflite/sqflite.dart';

import '../../domain/models/models.dart';
import '../db/app_database.dart';

/// Shift kasir: kas awal di laci, uang masuk selama shift, lalu kas fisik
/// saat tutup. Selisihnya yang memberi tahu pemilik ada yang tidak beres.
class ShiftRepository {
  ShiftRepository(this._db);

  final AppDatabase _db;

  /// Shift yang sedang terbuka untuk satu pengguna. Null bila belum dibuka.
  Future<Shift?> openShiftOf(int userId) async {
    final db = await _db.database;

    final rows = await db.query(
      'shifts',
      where: 'user_id = ? AND closed_at IS NULL',
      whereArgs: [userId],
      orderBy: 'opened_at DESC',
      limit: 1,
    );

    return rows.isEmpty ? null : Shift.fromMap(rows.first);
  }

  /// Membuka shift baru. Bila pengguna masih punya shift terbuka, shift itu
  /// yang dikembalikan, supaya tidak ada dua shift berjalan bersamaan.
  Future<Shift> open({
    required int userId,
    required int openingCash,
  }) async {
    final existing = await openShiftOf(userId);
    if (existing != null) return existing;

    final db = await _db.database;
    final now = DateTime.now();

    final id = await db.insert('shifts', {
      'user_id': userId,
      'opened_at': now.toIso8601String(),
      'opening_cash': openingCash,
    });

    return Shift(id: id, userId: userId, openedAt: now, openingCash: openingCash);
  }

  /// Uang tunai yang seharusnya ada di laci: kas awal ditambah seluruh
  /// pembayaran tunai yang tercatat pada shift ini. Transfer dan QRIS tidak
  /// dihitung karena uangnya tidak masuk laci.
  Future<int> expectedCash(Shift shift) async {
    final db = await _db.database;

    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS c FROM payments "
      "WHERE shift_id = ? AND method = 'Tunai'",
      [shift.id],
    );

    final cashPayments = (result.first['c'] as num).toInt();
    return shift.openingCash + cashPayments;
  }

  Future<Shift> close({
    required Shift shift,
    required int closingCash,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final expected = await expectedCash(shift);

    await db.update(
      'shifts',
      {
        'closed_at': now.toIso8601String(),
        'closing_cash': closingCash,
        'expected_cash': expected,
      },
      where: 'id = ?',
      whereArgs: [shift.id],
    );

    return Shift(
      id: shift.id,
      userId: shift.userId,
      openedAt: shift.openedAt,
      closedAt: now,
      openingCash: shift.openingCash,
      closingCash: closingCash,
      expectedCash: expected,
    );
  }

  /// Ringkasan angka satu shift, dipakai layar tutup shift dan cetakannya.
  Future<ShiftTotals> totalsOf(Shift shift) async {
    final db = await _db.database;

    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS net, '
      'COUNT(*) AS c, '
      'COALESCE(SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END), 0) AS refund '
      'FROM payments WHERE shift_id = ?',
      [shift.id],
    );

    final byMethod = await db.rawQuery(
      'SELECT method, COALESCE(SUM(amount), 0) AS amount, COUNT(*) AS c '
      'FROM payments WHERE shift_id = ? GROUP BY method ORDER BY amount DESC',
      [shift.id],
    );

    final orderCount = await db.rawQuery(
      'SELECT COUNT(DISTINCT o.id) AS c FROM orders o '
      'WHERE o.created_by = ? AND o.created_at >= ? '
      "AND o.laundry_status != 'dibatalkan'",
      [
        shift.userId,
        shift.openedAt.toIso8601String(),
      ],
    );

    return ShiftTotals(
      paymentCount: (rows.first['c'] as num).toInt(),
      cashIn: (rows.first['net'] as num).toInt(),
      refundTotal: (rows.first['refund'] as num).toInt(),
      orderCount: (orderCount.first['c'] as num).toInt(),
      byMethod: {
        for (final row in byMethod)
          row['method'] as String: (row['amount'] as num).toInt(),
      },
    );
  }

  /// Riwayat shift yang sudah ditutup, untuk Owner.
  Future<List<Map<String, Object?>>> history({int limit = 30}) async {
    final db = await _db.database;

    return db.rawQuery('''
      SELECT s.*, u.name AS user_name
      FROM shifts s JOIN users u ON u.id = s.user_id
      WHERE s.closed_at IS NOT NULL
      ORDER BY s.opened_at DESC
      LIMIT ?
    ''', [limit]);
  }
}

class ShiftTotals {
  const ShiftTotals({
    required this.paymentCount,
    required this.cashIn,
    required this.refundTotal,
    required this.orderCount,
    required this.byMethod,
  });

  final int paymentCount;
  final int cashIn;
  final int refundTotal;
  final int orderCount;
  final Map<String, int> byMethod;

  int get cashOnly => byMethod['Tunai'] ?? 0;

  static const empty = ShiftTotals(
    paymentCount: 0,
    cashIn: 0,
    refundTotal: 0,
    orderCount: 0,
    byMethod: {},
  );
}
