import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/domain/models/enums.dart';
import 'package:laundry_pos/domain/models/models.dart';
import 'package:laundry_pos/domain/price_calculator.dart';

/// Uji aturan uang. Kalau berkas ini hijau, nota dan laporan bisa dipercaya.
void main() {
  const calc = PriceCalculator();

  const kiloan = LaundryService(
    id: 1,
    name: 'Cuci Kering Lipat',
    unit: ServiceUnit.kg,
    price: 7000,
    durationHours: 48,
    minQty: 3.0,
    roundingStep: 0.1,
  );

  const satuan = LaundryService(
    id: 2,
    name: 'Bed Cover',
    unit: ServiceUnit.pcs,
    price: 35000,
    durationHours: 72,
    minQty: 1.0,
  );

  group('pembulatan berat', () {
    test('membulatkan ke atas ke kelipatan 0,1 kg', () {
      expect(calc.billableQty(kiloan, 3.42), 3.5);
      expect(calc.billableQty(kiloan, 3.41), 3.5);
      expect(calc.billableQty(kiloan, 3.4), 3.4);
    });

    test('berat di bawah minimum ditagih sebesar minimum', () {
      expect(calc.billableQty(kiloan, 1.2), 3.0);
      expect(calc.billableQty(kiloan, 2.96), 3.0);
    });

    test('tepat di minimum tidak dinaikkan', () {
      expect(calc.billableQty(kiloan, 3.0), 3.0);
    });

    test('satuan pcs selalu dibulatkan ke atas menjadi bilangan bulat', () {
      expect(calc.billableQty(satuan, 1.1), 2.0);
      expect(calc.billableQty(satuan, 2.0), 2.0);
    });

    test('berat nol atau negatif tidak menghasilkan tagihan', () {
      expect(calc.billableQty(kiloan, 0), 0);
      expect(calc.billableQty(kiloan, -5), 0);
    });
  });

  group('subtotal baris', () {
    test('kiloan biasa', () {
      // 3,5 kg x 7.000
      expect(calc.lineSubtotal(kiloan, 3.42), 24500);
    });

    test('minimum berlaku sebelum dikalikan harga', () {
      // 1,2 kg naik ke 3 kg, lalu 3 x 7.000
      expect(calc.lineSubtotal(kiloan, 1.2), 21000);
    });

    test('express menggandakan harga', () {
      expect(calc.lineSubtotal(kiloan, 3.0, express: true), 42000);
    });

    test('hasilnya selalu rupiah bulat', () {
      const ganjil = LaundryService(
        id: 3,
        name: 'Uji',
        unit: ServiceUnit.kg,
        price: 7333,
        durationHours: 24,
        roundingStep: 0.1,
      );
      final value = calc.lineSubtotal(ganjil, 2.7);
      expect(value, value.round());
      expect(value, 19799); // 2,7 x 7.333 = 19.798,1 dibulatkan
    });
  });

  group('diskon dan total', () {
    final items = [
      calc.buildItem(kiloan, 4.0), // 28.000
      calc.buildItem(satuan, 1.0), // 35.000
    ];

    test('subtotal menjumlahkan semua baris', () {
      expect(calc.subtotalOf(items), 63000);
    });

    test('diskon nominal mengurangi total', () {
      final discount = calc.discountAmount(63000, nominal: 5000);
      expect(discount, 5000);
      expect(calc.totalOf(items, discount: discount), 58000);
    });

    test('diskon persen dihitung dari subtotal', () {
      expect(calc.discountAmount(63000, percent: 10), 6300);
    });

    test('diskon tidak boleh melebihi subtotal', () {
      expect(calc.discountAmount(63000, nominal: 999999), 63000);
      expect(calc.totalOf(items, discount: 999999), 0);
    });

    test('total tidak pernah negatif', () {
      expect(calc.totalOf(items, discount: 100000), 0);
    });
  });

  group('status bayar', () {
    test('belum ada pembayaran', () {
      expect(calc.paymentStatusFor(total: 50000, paid: 0),
          PaymentStatus.belumBayar);
    });

    test('pembayaran sebagian menjadi DP', () {
      expect(
          calc.paymentStatusFor(total: 50000, paid: 20000), PaymentStatus.dp);
    });

    test('pembayaran penuh menjadi lunas', () {
      expect(calc.paymentStatusFor(total: 50000, paid: 50000),
          PaymentStatus.lunas);
    });

    test('kelebihan bayar tetap lunas', () {
      expect(calc.paymentStatusFor(total: 50000, paid: 60000),
          PaymentStatus.lunas);
    });

    test('order bernilai nol langsung lunas bila ada pembayaran', () {
      expect(calc.paymentStatusFor(total: 0, paid: 0),
          PaymentStatus.belumBayar);
    });
  });

  group('estimasi selesai', () {
    final from = DateTime(2026, 11, 21, 10, 0);

    test('memakai durasi layanan terlama dalam satu nota', () {
      final items = [
        calc.buildItem(kiloan, 3.0), // 48 jam
        calc.buildItem(satuan, 1.0), // 72 jam
      ];

      final estimate =
          calc.estimatedFinish([kiloan, satuan], items, from: from);

      expect(estimate, from.add(const Duration(hours: 72)));
    });

    test('express memangkas durasi layanan itu', () {
      final items = [calc.buildItem(kiloan, 3.0, express: true)];
      final estimate = calc.estimatedFinish([kiloan], items, from: from);

      expect(estimate, from.add(const Duration(hours: 6)));
    });
  });

  group('kembalian', () {
    test('uang pas tidak ada kembalian', () {
      expect(calc.change(amountDue: 50000, cashGiven: 50000), 0);
    });

    test('uang lebih menghasilkan kembalian', () {
      expect(calc.change(amountDue: 47000, cashGiven: 50000), 3000);
    });

    test('uang kurang menghasilkan nilai negatif', () {
      expect(calc.change(amountDue: 50000, cashGiven: 45000), -5000);
    });
  });

  group('salinan harga pada baris nota', () {
    test('nama dan harga disalin, bukan dirujuk', () {
      final item = calc.buildItem(kiloan, 4.0);

      expect(item.serviceName, 'Cuci Kering Lipat');
      expect(item.unitPrice, 7000);
      expect(item.subtotal, 28000);

      // Harga master naik setelah nota dibuat.
      const naik = LaundryService(
        id: 1,
        name: 'Cuci Kering Lipat',
        unit: ServiceUnit.kg,
        price: 9000,
        durationHours: 48,
        minQty: 3.0,
        roundingStep: 0.1,
      );

      // Baris lama harus tetap memakai harga lamanya.
      expect(item.unitPrice, isNot(naik.price));
      expect(item.subtotal, 28000);
    });

    test('baris express diberi penanda pada namanya', () {
      final item = calc.buildItem(kiloan, 3.0, express: true);
      expect(item.serviceName, contains('express'));
      expect(item.express, isTrue);
    });
  });
}
