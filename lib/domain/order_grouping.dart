import '../core/formatters.dart';
import 'models/enums.dart';
import 'models/models.dart';

/// Satu kelompok di daftar order: judul dan isinya.
class OrderGroup {
  const OrderGroup({
    required this.label,
    required this.orders,
    this.needsAttention = false,
  });

  final String label;
  final List<LaundryOrder> orders;

  /// Kelompok cucian yang lewat estimasi. Diberi warna peringatan.
  final bool needsAttention;
}

/// Angka ringkas untuk order yang sedang tampil di daftar.
class OrderListSummary {
  const OrderListSummary({
    required this.count,
    required this.totalValue,
    required this.outstanding,
    required this.lateCount,
  });

  /// Jumlah order, tidak termasuk yang dibatalkan.
  final int count;

  /// Jumlah nilai order. BUKAN pendapatan: pendapatan adalah uang yang
  /// benar-benar diterima, dan itu ada di laporan.
  final int totalValue;

  /// Sisa tagihan dari order-order ini.
  final int outstanding;

  /// Cucian yang lewat estimasi dan belum diambil.
  final int lateCount;

  static const empty = OrderListSummary(
    count: 0,
    totalValue: 0,
    outstanding: 0,
    lateCount: 0,
  );
}

/// Cucian yang lewat estimasi selesai dan belum diambil atau dibatalkan.
bool isOrderLate(LaundryOrder order, DateTime now) =>
    order.laundryStatus.isOpen && now.isAfter(order.estimatedAt);

OrderListSummary summarizeOrders(List<LaundryOrder> orders, DateTime now) {
  var count = 0;
  var total = 0;
  var outstanding = 0;
  var late = 0;

  for (final order in orders) {
    if (order.laundryStatus == LaundryStatus.dibatalkan) continue;

    count++;
    total += order.total;
    outstanding += order.remaining;
    if (isOrderLate(order, now)) late++;
  }

  return OrderListSummary(
    count: count,
    totalValue: total,
    outstanding: outstanding,
    lateCount: late,
  );
}

/// Mengelompokkan order untuk daftar.
///
/// Urutannya sengaja begini: yang lewat estimasi paling atas (yang paling
/// lama telat paling dulu), karena tumpukan yang terlupakan itulah yang
/// harus terlihat pertama di konter. Sisanya per hari, terbaru dulu, dengan
/// judul "Hari ini" dan "Kemarin" supaya mata menemukan hari ini tanpa
/// membaca tanggal.
List<OrderGroup> groupOrders(List<LaundryOrder> orders, DateTime now) {
  final late = <LaundryOrder>[];
  final rest = <LaundryOrder>[];

  for (final order in orders) {
    (isOrderLate(order, now) ? late : rest).add(order);
  }

  late.sort((a, b) => a.estimatedAt.compareTo(b.estimatedAt));
  rest.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final groups = <OrderGroup>[];

  if (late.isNotEmpty) {
    groups.add(OrderGroup(
      label: 'Perlu perhatian',
      orders: late,
      needsAttention: true,
    ));
  }

  final today = _dayOf(now);
  String? currentKey;
  var bucket = <LaundryOrder>[];
  var label = '';

  void flush() {
    if (bucket.isNotEmpty) {
      groups.add(OrderGroup(label: label, orders: bucket));
    }
    bucket = <LaundryOrder>[];
  }

  for (final order in rest) {
    final day = _dayOf(order.createdAt);
    final key = '${day.year}-${day.month}-${day.day}';

    if (key != currentKey) {
      flush();
      currentKey = key;

      final diff = today.difference(day).inDays;
      label = diff == 0
          ? 'Hari ini'
          : diff == 1
              ? 'Kemarin'
              : formatDayLabel(order.createdAt, now: now);
    }
    bucket.add(order);
  }
  flush();

  return groups;
}

/// Tanggal tanpa jam, dalam UTC supaya selisih hari tidak terganggu
/// pergantian jam musim di perangkat mana pun.
DateTime _dayOf(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
