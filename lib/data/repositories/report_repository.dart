import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

/// Ringkasan satu periode.
class RevenueSummary {
  const RevenueSummary({
    required this.orderCount,
    required this.grossOrderValue,
    required this.discountTotal,
    required this.cashIn,
    required this.refundTotal,
    required this.newReceivable,
  });

  /// Jumlah order yang dibuat dalam periode, tidak termasuk yang dibatalkan.
  final int orderCount;

  /// Nilai order yang dibuat dalam periode. BUKAN pendapatan.
  final int grossOrderValue;
  final int discountTotal;

  /// Uang yang benar-benar diterima dalam periode, sudah dikurangi refund.
  /// Inilah angka pendapatan.
  final int cashIn;
  final int refundTotal;

  /// Nilai order periode ini yang belum dibayar sampai akhir periode.
  final int newReceivable;

  int get averageOrderValue =>
      orderCount == 0 ? 0 : (grossOrderValue / orderCount).round();

  static const empty = RevenueSummary(
    orderCount: 0,
    grossOrderValue: 0,
    discountTotal: 0,
    cashIn: 0,
    refundTotal: 0,
    newReceivable: 0,
  );
}

class DailyRevenue {
  const DailyRevenue({required this.date, required this.amount});

  final DateTime date;
  final int amount;
}

class NamedAmount {
  const NamedAmount({
    required this.name,
    required this.amount,
    this.count = 0,
    this.qty = 0,
  });

  final String name;
  final int amount;
  final int count;
  final double qty;
}

class ReceivableRow {
  const ReceivableRow({
    required this.orderId,
    required this.orderNo,
    required this.customerName,
    required this.customerPhone,
    required this.total,
    required this.paid,
    required this.createdAt,
  });

  final int orderId;
  final String orderNo;
  final String customerName;
  final String customerPhone;
  final int total;
  final int paid;
  final DateTime createdAt;

  int get remaining => total - paid;
  int get ageInDays => DateTime.now().difference(createdAt).inDays;
}

/// Semua laporan pendapatan dihitung dari tabel `payments`.
///
/// Memakai nilai order akan memasukkan piutang sebagai pendapatan, dan itu
/// membuat pemilik mengira punya uang yang sebenarnya belum diterima.
class ReportRepository {
  ReportRepository(this._db);

  final AppDatabase _db;

  Future<RevenueSummary> summary(DateTime from, DateTime to) async {
    final db = await _db.database;
    final a = _startOfDay(from).toIso8601String();
    final b = _endOfDay(to).toIso8601String();

    final cashRows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS net, '
      'COALESCE(SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END), 0) AS refund '
      'FROM payments WHERE paid_at BETWEEN ? AND ?',
      [a, b],
    );

    final orderRows = await db.rawQuery(
      'SELECT COUNT(*) AS c, COALESCE(SUM(total), 0) AS gross, '
      'COALESCE(SUM(discount), 0) AS disc '
      "FROM orders WHERE laundry_status != 'dibatalkan' "
      'AND created_at BETWEEN ? AND ?',
      [a, b],
    );

    final receivableRows = await db.rawQuery(
      'SELECT COALESCE(SUM(o.total - COALESCE('
      '(SELECT SUM(p.amount) FROM payments p WHERE p.order_id = o.id), 0)), 0) AS sisa '
      "FROM orders o WHERE o.laundry_status != 'dibatalkan' "
      'AND o.created_at BETWEEN ? AND ?',
      [a, b],
    );

    return RevenueSummary(
      orderCount: (orderRows.first['c'] as num).toInt(),
      grossOrderValue: (orderRows.first['gross'] as num).toInt(),
      discountTotal: (orderRows.first['disc'] as num).toInt(),
      cashIn: (cashRows.first['net'] as num).toInt(),
      refundTotal: (cashRows.first['refund'] as num).toInt(),
      newReceivable: (receivableRows.first['sisa'] as num).toInt(),
    );
  }

  /// Pendapatan per hari untuk grafik tren (FR-102).
  /// Hari tanpa transaksi tetap muncul dengan nilai nol, supaya garis
  /// grafik tidak melompat dan menyembunyikan hari sepi.
  Future<List<DailyRevenue>> dailyRevenue(DateTime from, DateTime to) async {
    final db = await _db.database;

    final rows = await db.rawQuery(
      "SELECT substr(paid_at, 1, 10) AS day, COALESCE(SUM(amount), 0) AS total "
      'FROM payments WHERE paid_at BETWEEN ? AND ? '
      'GROUP BY day ORDER BY day',
      [_startOfDay(from).toIso8601String(), _endOfDay(to).toIso8601String()],
    );

    final byDay = {
      for (final row in rows)
        row['day'] as String: (row['total'] as num).toInt(),
    };

    final result = <DailyRevenue>[];
    var cursor = _startOfDay(from);
    final last = _startOfDay(to);

    while (!cursor.isAfter(last)) {
      final key = cursor.toIso8601String().substring(0, 10);
      result.add(DailyRevenue(date: cursor, amount: byDay[key] ?? 0));
      cursor = cursor.add(const Duration(days: 1));
    }

    return result;
  }

  /// Pendapatan per layanan.
  ///
  /// Nilai order dibagi proporsional ke pembayaran yang sudah masuk, supaya
  /// order yang baru dibayar separuh tidak dihitung penuh.
  Future<List<NamedAmount>> byService(DateTime from, DateTime to) async {
    final db = await _db.database;

    final rows = await db.rawQuery('''
      SELECT i.service_name AS name,
             COUNT(DISTINCT i.order_id) AS c,
             COALESCE(SUM(i.qty), 0) AS qty,
             COALESCE(SUM(i.subtotal), 0) AS amount
      FROM order_items i
      JOIN orders o ON o.id = i.order_id
      WHERE o.laundry_status != 'dibatalkan'
        AND o.created_at BETWEEN ? AND ?
      GROUP BY i.service_name
      ORDER BY amount DESC
    ''', [_startOfDay(from).toIso8601String(), _endOfDay(to).toIso8601String()]);

    return rows
        .map((r) => NamedAmount(
              name: r['name'] as String,
              amount: (r['amount'] as num).toInt(),
              count: (r['c'] as num).toInt(),
              qty: (r['qty'] as num).toDouble(),
            ))
        .toList();
  }

  Future<List<NamedAmount>> byMethod(DateTime from, DateTime to) async {
    final db = await _db.database;

    final rows = await db.rawQuery(
      'SELECT method AS name, COUNT(*) AS c, COALESCE(SUM(amount), 0) AS amount '
      'FROM payments WHERE paid_at BETWEEN ? AND ? '
      'GROUP BY method ORDER BY amount DESC',
      [_startOfDay(from).toIso8601String(), _endOfDay(to).toIso8601String()],
    );

    return rows
        .map((r) => NamedAmount(
              name: r['name'] as String,
              amount: (r['amount'] as num).toInt(),
              count: (r['c'] as num).toInt(),
            ))
        .toList();
  }

  Future<List<NamedAmount>> byCashier(DateTime from, DateTime to) async {
    final db = await _db.database;

    final rows = await db.rawQuery(
      'SELECT u.name AS name, COUNT(*) AS c, COALESCE(SUM(p.amount), 0) AS amount '
      'FROM payments p JOIN users u ON u.id = p.received_by '
      'WHERE p.paid_at BETWEEN ? AND ? '
      'GROUP BY u.name ORDER BY amount DESC',
      [_startOfDay(from).toIso8601String(), _endOfDay(to).toIso8601String()],
    );

    return rows
        .map((r) => NamedAmount(
              name: r['name'] as String,
              amount: (r['amount'] as num).toInt(),
              count: (r['c'] as num).toInt(),
            ))
        .toList();
  }

  /// Seluruh piutang yang masih terbuka, bukan hanya periode tertentu.
  Future<List<ReceivableRow>> receivables() async {
    final db = await _db.database;

    final rows = await db.rawQuery('''
      SELECT o.id, o.order_no, o.total, o.created_at,
             c.name AS customer_name, c.phone AS customer_phone,
             COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.order_id = o.id), 0) AS paid
      FROM orders o
      JOIN customers c ON c.id = o.customer_id
      WHERE o.laundry_status != 'dibatalkan'
        AND o.payment_status != 'lunas'
      ORDER BY o.created_at ASC
    ''');

    return rows
        .map((r) => ReceivableRow(
              orderId: r['id'] as int,
              orderNo: r['order_no'] as String,
              customerName: r['customer_name'] as String,
              customerPhone: r['customer_phone'] as String,
              total: (r['total'] as num).toInt(),
              paid: (r['paid'] as num).toInt(),
              createdAt: DateTime.parse(r['created_at'] as String),
            ))
        .where((row) => row.remaining > 0)
        .toList();
  }

  Future<List<NamedAmount>> topCustomers(DateTime from, DateTime to,
      {int limit = 10}) async {
    final db = await _db.database;

    final rows = await db.rawQuery('''
      SELECT c.name AS name, COUNT(o.id) AS c, COALESCE(SUM(o.total), 0) AS amount
      FROM orders o
      JOIN customers c ON c.id = o.customer_id
      WHERE o.laundry_status != 'dibatalkan' AND o.created_at BETWEEN ? AND ?
      GROUP BY c.id ORDER BY amount DESC LIMIT ?
    ''', [
      _startOfDay(from).toIso8601String(),
      _endOfDay(to).toIso8601String(),
      limit,
    ]);

    return rows
        .map((r) => NamedAmount(
              name: r['name'] as String,
              amount: (r['amount'] as num).toInt(),
              count: (r['c'] as num).toInt(),
            ))
        .toList();
  }

  /// Uang tunai yang seharusnya ada di laci untuk satu shift.
  Future<int> expectedCashFor(int shiftId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS c FROM payments "
      "WHERE shift_id = ? AND method = 'Tunai'",
      [shiftId],
    );
    return (result.first['c'] as num).toInt();
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}
