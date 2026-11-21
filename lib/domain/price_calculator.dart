import 'dart:math' as math;

import 'models/enums.dart';
import 'models/models.dart';

/// Seluruh aturan harga, pembulatan berat, diskon, dan estimasi selesai
/// berada di satu tempat ini. Widget tidak boleh menghitung uang sendiri,
/// supaya aturan bisa diuji tanpa membuka layar.
class PriceCalculator {
  const PriceCalculator();

  /// Kuantitas yang benar-benar ditagih.
  ///
  /// Urutannya: bulatkan dulu ke kelipatan [LaundryService.roundingStep],
  /// baru terapkan minimum. Membalik urutannya membuat 2,96 kg dengan
  /// minimum 3 kg ditagih 3,0 kg, bukan 3,0 kg setelah dibulatkan jadi 3,0.
  double billableQty(LaundryService service, double rawQty) {
    if (rawQty <= 0) return 0;

    var qty = rawQty;

    if (!service.unit.allowsFraction) {
      qty = qty.ceilToDouble();
    } else if (service.roundingStep > 0) {
      final steps = (qty / service.roundingStep).ceil();
      qty = steps * service.roundingStep;
    }

    if (qty < service.minQty) qty = service.minQty;

    // Buang galat biner, misalnya 3.3000000000000003 menjadi 3.3.
    return double.parse(qty.toStringAsFixed(3));
  }

  /// Subtotal satu baris layanan, sudah dibulatkan ke rupiah penuh.
  int lineSubtotal(
    LaundryService service,
    double rawQty, {
    bool express = false,
  }) {
    final qty = billableQty(service, rawQty);
    if (qty <= 0) return 0;

    final multiplier = express ? service.expressMultiplier : 1.0;
    final raw = service.price * qty * multiplier;

    // Pembulatan ke rupiah terdekat. Tanpa ini, 2,7 kg x 7.000 jadi 18.900,000001.
    return raw.round();
  }

  /// Membuat baris nota dari master layanan. Harga dan nama disalin di sini.
  OrderItem buildItem(
    LaundryService service,
    double rawQty, {
    bool express = false,
    String? note,
  }) {
    return OrderItem(
      serviceId: service.id!,
      serviceName: express ? '${service.name} (express)' : service.name,
      unit: service.unit,
      qty: billableQty(service, rawQty),
      unitPrice: service.price,
      subtotal: lineSubtotal(service, rawQty, express: express),
      express: express,
      note: note,
    );
  }

  int subtotalOf(List<OrderItem> items) =>
      items.fold(0, (sum, item) => sum + item.subtotal);

  /// Diskon persen dihitung dari subtotal lalu dibulatkan ke rupiah penuh.
  /// Hasilnya tidak pernah melebihi subtotal.
  int discountAmount(
    int subtotal, {
    int nominal = 0,
    double percent = 0,
  }) {
    final fromPercent = percent > 0 ? (subtotal * percent / 100).round() : 0;
    final total = nominal + fromPercent;
    return total.clamp(0, subtotal);
  }

  int totalOf(List<OrderItem> items, {int discount = 0}) {
    final subtotal = subtotalOf(items);
    return math.max(0, subtotal - discount.clamp(0, subtotal));
  }

  /// Estimasi selesai diambil dari layanan dengan durasi terpanjang.
  /// Satu nota berisi cuci biasa dan setrika express tetap selesai
  /// mengikuti yang paling lama.
  DateTime estimatedFinish(
    List<LaundryService> services,
    List<OrderItem> items, {
    required DateTime from,
  }) {
    var longest = 0;

    for (final item in items) {
      final service = services.where((s) => s.id == item.serviceId).firstOrNull;
      if (service == null) continue;
      final hours =
          item.express ? service.expressDurationHours : service.durationHours;
      if (hours > longest) longest = hours;
    }

    if (longest == 0) longest = 24;
    return from.add(Duration(hours: longest));
  }

  /// Status bayar diturunkan dari total yang sudah diterima,
  /// bukan ditulis manual oleh layar pembayaran.
  PaymentStatus paymentStatusFor({required int total, required int paid}) {
    if (paid <= 0) return PaymentStatus.belumBayar;
    if (paid >= total) return PaymentStatus.lunas;
    return PaymentStatus.dp;
  }

  /// Kembalian uang tunai. Negatif berarti uang pelanggan masih kurang.
  int change({required int amountDue, required int cashGiven}) =>
      cashGiven - amountDue;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
