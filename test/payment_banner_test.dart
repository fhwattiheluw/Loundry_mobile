import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/domain/models/enums.dart';
import 'package:laundry_pos/domain/models/models.dart';
import 'package:laundry_pos/domain/payment_banner.dart';

LaundryOrder _order({
  required int total,
  required int paid,
  LaundryStatus status = LaundryStatus.diproses,
}) {
  return LaundryOrder(
    orderNo: 'LD-20261123-0001',
    customerId: 1,
    createdBy: 1,
    createdAt: DateTime(2026, 11, 23, 9),
    estimatedAt: DateTime(2026, 11, 25),
    laundryStatus: status,
    paymentStatus: PaymentStatus.belumBayar,
    subtotal: total,
    discount: 0,
    total: total,
    paid: paid,
    items: const [],
    customerName: 'Budi',
    customerPhone: '',
  );
}

void main() {
  group('paymentBannerOf', () {
    test('dibayar penuh adalah LUNAS', () {
      final banner = paymentBannerOf(_order(total: 50000, paid: 50000));
      expect(banner, PaymentBanner.lunas);
      expect(banner.text, 'LUNAS');
    });

    test('dibayar lebih dari total tetap LUNAS', () {
      expect(paymentBannerOf(_order(total: 50000, paid: 60000)),
          PaymentBanner.lunas);
    });

    test('DP dan bayar nanti sama-sama BELUM LUNAS', () {
      expect(paymentBannerOf(_order(total: 50000, paid: 20000)),
          PaymentBanner.belumLunas);
      expect(paymentBannerOf(_order(total: 50000, paid: 0)),
          PaymentBanner.belumLunas);
      expect(PaymentBanner.belumLunas.text, 'BELUM LUNAS');
    });

    test('kurang satu rupiah belum boleh disebut LUNAS', () {
      expect(paymentBannerOf(_order(total: 50000, paid: 49999)),
          PaymentBanner.belumLunas);
    });

    test('order batal tidak pernah dicap LUNAS', () {
      expect(
        paymentBannerOf(_order(
            total: 50000, paid: 50000, status: LaundryStatus.dibatalkan)),
        PaymentBanner.dibatalkan,
      );
    });
  });
}
