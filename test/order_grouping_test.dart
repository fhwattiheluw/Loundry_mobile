import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:laundry_pos/domain/models/enums.dart';
import 'package:laundry_pos/domain/models/models.dart';
import 'package:laundry_pos/domain/order_grouping.dart';

LaundryOrder _order(
  String no, {
  required DateTime createdAt,
  required DateTime estimatedAt,
  LaundryStatus status = LaundryStatus.diproses,
  int total = 50000,
  int paid = 0,
}) {
  return LaundryOrder(
    orderNo: no,
    customerId: 1,
    createdBy: 1,
    createdAt: createdAt,
    estimatedAt: estimatedAt,
    laundryStatus: status,
    paymentStatus: paid >= total ? PaymentStatus.lunas : PaymentStatus.belumBayar,
    subtotal: total,
    discount: 0,
    extraFee: 0,
    total: total,
    paid: paid,
    items: const [],
    customerName: 'Budi',
    customerPhone: '6281234567890',
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  final now = DateTime(2026, 11, 23, 14);
  final future = DateTime(2026, 11, 30);

  group('groupOrders', () {
    test('kosong menghasilkan tanpa kelompok', () {
      expect(groupOrders(const [], now), isEmpty);
    });

    test('hari ini dan kemarin diberi judul, tanggal lain ditulis', () {
      final groups = groupOrders([
        _order('A', createdAt: DateTime(2026, 11, 23, 9), estimatedAt: future),
        _order('B', createdAt: DateTime(2026, 11, 22, 20), estimatedAt: future),
        _order('C', createdAt: DateTime(2026, 11, 19, 10), estimatedAt: future),
      ], now);

      expect(groups.map((g) => g.label).toList(),
          ['Hari ini', 'Kemarin', 'Kam, 19 Nov']);
      expect(groups.any((g) => g.needsAttention), isFalse);
    });

    test('order di hari yang sama masuk satu kelompok, terbaru dulu', () {
      final groups = groupOrders([
        _order('A', createdAt: DateTime(2026, 11, 23, 8), estimatedAt: future),
        _order('B', createdAt: DateTime(2026, 11, 23, 13), estimatedAt: future),
      ], now);

      expect(groups, hasLength(1));
      expect(groups.single.orders.map((o) => o.orderNo).toList(), ['B', 'A']);
    });

    test('cucian telat dikumpulkan paling atas, yang paling lama dulu', () {
      final groups = groupOrders([
        _order('BARU',
            createdAt: DateTime(2026, 11, 23, 9), estimatedAt: future),
        _order('TELAT2',
            createdAt: DateTime(2026, 11, 20, 9),
            estimatedAt: DateTime(2026, 11, 22)),
        _order('TELAT1',
            createdAt: DateTime(2026, 11, 18, 9),
            estimatedAt: DateTime(2026, 11, 21)),
      ], now);

      expect(groups.first.needsAttention, isTrue);
      expect(groups.first.label, 'Perlu perhatian');
      expect(groups.first.orders.map((o) => o.orderNo).toList(),
          ['TELAT1', 'TELAT2']);
      expect(groups[1].label, 'Hari ini');
    });

    test('yang sudah diambil atau dibatalkan tidak dianggap telat', () {
      final past = DateTime(2026, 11, 20);
      final groups = groupOrders([
        _order('X',
            createdAt: DateTime(2026, 11, 19),
            estimatedAt: past,
            status: LaundryStatus.diambil),
        _order('Y',
            createdAt: DateTime(2026, 11, 19),
            estimatedAt: past,
            status: LaundryStatus.dibatalkan),
      ], now);

      expect(groups.any((g) => g.needsAttention), isFalse);
      expect(groups.single.orders, hasLength(2));
    });

    test('tahun lain ikut ditulis di judul tanggal', () {
      final groups = groupOrders([
        _order('Z',
            createdAt: DateTime(2025, 12, 30, 9),
            estimatedAt: DateTime(2026, 1, 2),
            status: LaundryStatus.diambil),
      ], now);

      expect(groups.single.label, contains('2025'));
    });
  });

  group('summarizeOrders', () {
    test('menjumlah nilai, sisa tagihan, dan jumlah telat', () {
      final summary = summarizeOrders([
        _order('A',
            createdAt: DateTime(2026, 11, 23),
            estimatedAt: future,
            total: 40000,
            paid: 40000),
        _order('B',
            createdAt: DateTime(2026, 11, 22),
            estimatedAt: DateTime(2026, 11, 21),
            total: 60000,
            paid: 10000),
      ], now);

      expect(summary.count, 2);
      expect(summary.totalValue, 100000);
      expect(summary.outstanding, 50000);
      expect(summary.lateCount, 1);
    });

    test('order batal tidak ikut dihitung', () {
      final summary = summarizeOrders([
        _order('A',
            createdAt: DateTime(2026, 11, 23),
            estimatedAt: future,
            status: LaundryStatus.dibatalkan,
            total: 99000),
      ], now);

      expect(summary.count, 0);
      expect(summary.totalValue, 0);
      expect(summary.outstanding, 0);
    });
  });
}
