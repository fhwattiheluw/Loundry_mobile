import 'package:sqflite/sqflite.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/price_calculator.dart';
import '../db/app_database.dart';

/// Kueri yang menempelkan nama pelanggan dan total pembayaran ke setiap order.
///
/// `paid` dihitung dari tabel payments, bukan disimpan sebagai kolom. Kolom
/// turunan selalu bisa melenceng dari sumbernya; subquery tidak pernah bisa.
const _orderSelect = '''
  SELECT o.*,
         c.name  AS customer_name,
         c.phone AS customer_phone,
         COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.order_id = o.id), 0) AS paid
  FROM orders o
  JOIN customers c ON c.id = o.customer_id
''';

class OrderFilter {
  const OrderFilter({
    this.statuses = const [],
    this.unpaidOnly = false,
    this.from,
    this.to,
    this.query = '',
  });

  final List<LaundryStatus> statuses;
  final bool unpaidOnly;
  final DateTime? from;
  final DateTime? to;
  final String query;

  OrderFilter copyWith({
    List<LaundryStatus>? statuses,
    bool? unpaidOnly,
    DateTime? from,
    DateTime? to,
    String? query,
    bool clearDates = false,
  }) =>
      OrderFilter(
        statuses: statuses ?? this.statuses,
        unpaidOnly: unpaidOnly ?? this.unpaidOnly,
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        query: query ?? this.query,
      );
}

class OrderRepository {
  OrderRepository(this._db, {PriceCalculator? calculator})
      : _calc = calculator ?? const PriceCalculator();

  final AppDatabase _db;
  final PriceCalculator _calc;

  // ---------------------------------------------------------------- membaca

  Future<List<LaundryOrder>> find(OrderFilter filter, {int limit = 200}) async {
    final db = await _db.database;

    final where = <String>[];
    final args = <Object?>[];

    if (filter.statuses.isNotEmpty) {
      final marks = List.filled(filter.statuses.length, '?').join(', ');
      where.add('o.laundry_status IN ($marks)');
      args.addAll(filter.statuses.map((s) => s.name));
    }

    if (filter.from != null) {
      where.add('o.created_at >= ?');
      args.add(_startOfDay(filter.from!).toIso8601String());
    }

    if (filter.to != null) {
      where.add('o.created_at <= ?');
      args.add(_endOfDay(filter.to!).toIso8601String());
    }

    if (filter.query.trim().isNotEmpty) {
      where.add('(o.order_no LIKE ? OR c.name LIKE ? OR c.phone LIKE ?)');
      final term = '%${filter.query.trim()}%';
      args.addAll([term, term, term]);
    }

    if (filter.unpaidOnly) {
      where.add("o.payment_status != 'lunas'");
      where.add("o.laundry_status != 'dibatalkan'");
    }

    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery(
      '$_orderSelect $clause ORDER BY o.created_at DESC LIMIT ?',
      [...args, limit],
    );

    return rows.map(LaundryOrder.fromMap).toList();
  }

  Future<LaundryOrder?> byId(int id) async {
    final db = await _db.database;
    final rows = await db.rawQuery('$_orderSelect WHERE o.id = ?', [id]);
    if (rows.isEmpty) return null;

    final order = LaundryOrder.fromMap(rows.first);
    final items = await _itemsOf(db, id);
    return order.copyWith(items: items);
  }

  /// Mencari order dari nomor nota, dipakai hasil pindai QR (FR-33).
  /// Nomor dibandingkan tanpa peduli spasi di ujung, karena hasil pindai
  /// kadang membawa karakter tambahan.
  Future<LaundryOrder?> byOrderNo(String orderNo) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '$_orderSelect WHERE o.order_no = ?',
      [orderNo.trim()],
    );

    if (rows.isEmpty) return null;

    final order = LaundryOrder.fromMap(rows.first);
    final items = await _itemsOf(db, order.id!);
    return order.copyWith(items: items);
  }

  Future<List<OrderItem>> _itemsOf(Database db, int orderId) async {
    final rows = await db.query('order_items',
        where: 'order_id = ?', whereArgs: [orderId], orderBy: 'id');
    return rows.map(OrderItem.fromMap).toList();
  }

  /// Order selesai yang belum diambil melewati batas hari (FR-31, FR-62).
  Future<List<LaundryOrder>> staleOrders(int reminderDays) async {
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(Duration(days: reminderDays));

    final rows = await db.rawQuery(
      "$_orderSelect WHERE o.laundry_status = 'selesai' AND o.estimated_at <= ? "
      'ORDER BY o.estimated_at ASC',
      [cutoff.toIso8601String()],
    );

    return rows.map(LaundryOrder.fromMap).toList();
  }

  // -------------------------------------------------------------- menyimpan

  /// Nomor nota: YYYYMMDD-NNN, urut per hari.
  ///
  /// Dibuat di dalam transaksi yang sama dengan penyimpanan order supaya dua
  /// kasir yang menekan Simpan bersamaan tidak mendapat nomor kembar.
  Future<String> _nextOrderNo(DatabaseExecutor txn, DateTime date) async {
    final prefix = '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';

    final result = await txn.rawQuery(
      'SELECT COUNT(*) AS c FROM orders WHERE order_no LIKE ?',
      ['$prefix-%'],
    );

    final seq = (Sqflite.firstIntValue(result) ?? 0) + 1;
    return '$prefix-${seq.toString().padLeft(3, '0')}';
  }

  Future<LaundryOrder> create({
    required Customer customer,
    required List<OrderItem> items,
    required List<LaundryService> services,
    required AppUser user,
    int discount = 0,
    int extraFee = 0,
    String? extraFeeNote,
    String? perfume,
    String? note,
    DateTime? estimatedAt,
    int initialPayment = 0,
    String paymentMethod = 'Tunai',
    int? shiftId,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Order harus punya minimal satu baris layanan.');
    }
    if (customer.id == null) {
      throw ArgumentError('Pelanggan harus disimpan lebih dulu.');
    }

    final db = await _db.database;
    final now = DateTime.now();

    final subtotal = _calc.subtotalOf(items);
    final safeDiscount = discount.clamp(0, subtotal);
    final safeExtra = extraFee < 0 ? 0 : extraFee;
    final total = _calc.totalOf(items, discount: safeDiscount, extraFee: safeExtra);
    final paid = initialPayment.clamp(0, total);

    final estimate =
        estimatedAt ?? _calc.estimatedFinish(services, items, from: now);

    late int orderId;

    await db.transaction((txn) async {
      final orderNo = await _nextOrderNo(txn, now);

      orderId = await txn.insert('orders', {
        'order_no': orderNo,
        'customer_id': customer.id,
        'created_by': user.id,
        'created_at': now.toIso8601String(),
        'estimated_at': estimate.toIso8601String(),
        'laundry_status': LaundryStatus.diterima.name,
        'payment_status':
            _calc.paymentStatusFor(total: total, paid: paid).name,
        'subtotal': subtotal,
        'discount': safeDiscount,
        'extra_fee': safeExtra,
        'extra_fee_note': extraFeeNote,
        'perfume': perfume,
        'total': total,
        'note': note,
      });

      for (final item in items) {
        await txn.insert('order_items', item.copyWith(orderId: orderId).toMap());
      }

      await txn.insert('status_logs', {
        'order_id': orderId,
        'status': LaundryStatus.diterima.name,
        'changed_at': now.toIso8601String(),
        'user_id': user.id,
      });

      if (paid > 0) {
        await txn.insert('payments', {
          'order_id': orderId,
          'shift_id': shiftId,
          'paid_at': now.toIso8601String(),
          'amount': paid,
          'method': paymentMethod,
          'received_by': user.id,
        });
      }
    });

    final saved = await byId(orderId);
    return saved!;
  }

  // ----------------------------------------------------------------- status

  Future<void> changeStatus(
    int orderId,
    LaundryStatus status, {
    required AppUser user,
    String? pickedUpBy,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();

    await db.transaction((txn) async {
      await txn.update(
        'orders',
        {
          'laundry_status': status.name,
          if (status == LaundryStatus.diambil) ...{
            'picked_up_at': now.toIso8601String(),
            'picked_up_by': pickedUpBy,
          },
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      await txn.insert('status_logs', {
        'order_id': orderId,
        'status': status.name,
        'changed_at': now.toIso8601String(),
        'user_id': user.id,
      });
    });
  }

  /// Menyimpan lokasi rak. Kosong berarti rak dihapus, bukan diisi
  /// dengan tanda hubung yang nanti ikut tercetak di nota.
  Future<void> setRack(int orderId, String rack) async {
    final db = await _db.database;
    final trimmed = rack.trim();

    await db.update(
      'orders',
      {'rack': trimmed.isEmpty ? null : trimmed},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<void> changeStatusBulk(
    List<int> orderIds,
    LaundryStatus status, {
    required AppUser user,
  }) async {
    for (final id in orderIds) {
      await changeStatus(id, status, user: user);
    }
  }

  /// Pembatalan tidak menghapus data (FR-50). Order tetap bisa dibuka,
  /// lengkap dengan alasannya.
  Future<void> cancel(
    int orderId, {
    required AppUser user,
    required String reason,
  }) async {
    if (!user.isOwner) {
      final order = await byId(orderId);
      if (order != null && order.paid > 0) {
        throw StateError(
          'Order yang sudah dibayar hanya bisa dibatalkan oleh Owner.',
        );
      }
    }

    final db = await _db.database;
    final now = DateTime.now();

    await db.transaction((txn) async {
      await txn.update(
        'orders',
        {
          'laundry_status': LaundryStatus.dibatalkan.name,
          'cancelled_at': now.toIso8601String(),
          'cancel_reason': reason,
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      await txn.insert('status_logs', {
        'order_id': orderId,
        'status': LaundryStatus.dibatalkan.name,
        'changed_at': now.toIso8601String(),
        'user_id': user.id,
      });
    });
  }

  // ------------------------------------------------------------- pembayaran

  Future<void> addPayment({
    required int orderId,
    required int amount,
    required String method,
    required AppUser user,
    int? shiftId,
    String? note,
  }) async {
    if (amount == 0) return;

    final db = await _db.database;
    final now = DateTime.now();

    await db.transaction((txn) async {
      await txn.insert('payments', {
        'order_id': orderId,
        'shift_id': shiftId,
        'paid_at': now.toIso8601String(),
        'amount': amount,
        'method': method,
        'received_by': user.id,
        'note': note,
      });

      await _refreshPaymentStatus(txn, orderId);
    });
  }

  /// Refund dicatat sebagai pembayaran bernilai negatif, bukan dengan
  /// menghapus baris pembayaran asli.
  Future<void> refund({
    required int orderId,
    required int amount,
    required AppUser user,
    required String reason,
    int? shiftId,
  }) async {
    if (!user.isOwner) {
      throw StateError('Refund hanya bisa dilakukan oleh Owner.');
    }
    await addPayment(
      orderId: orderId,
      amount: -amount.abs(),
      method: 'Refund',
      user: user,
      shiftId: shiftId,
      note: reason,
    );
  }

  Future<void> _refreshPaymentStatus(DatabaseExecutor txn, int orderId) async {
    final rows = await txn.rawQuery(
      'SELECT o.total, '
      'COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.order_id = o.id), 0) AS paid '
      'FROM orders o WHERE o.id = ?',
      [orderId],
    );

    if (rows.isEmpty) return;

    final total = rows.first['total'] as int;
    final paid = (rows.first['paid'] as num).toInt();

    await txn.update(
      'orders',
      {'payment_status': _calc.paymentStatusFor(total: total, paid: paid).name},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<List<Payment>> paymentsOf(int orderId) async {
    final db = await _db.database;
    final rows = await db.query('payments',
        where: 'order_id = ?', whereArgs: [orderId], orderBy: 'paid_at');
    return rows.map(Payment.fromMap).toList();
  }

  // ------------------------------------------------------------- log status

  Future<List<Map<String, Object?>>> statusHistory(int orderId) async {
    final db = await _db.database;
    return db.rawQuery(
      'SELECT s.*, u.name AS user_name FROM status_logs s '
      'JOIN users u ON u.id = s.user_id '
      'WHERE s.order_id = ? ORDER BY s.changed_at',
      [orderId],
    );
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}
