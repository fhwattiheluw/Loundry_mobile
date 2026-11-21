import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/data/db/app_database.dart';
import 'package:laundry_pos/data/repositories/master_repository.dart';
import 'package:laundry_pos/data/repositories/order_repository.dart';
import 'package:laundry_pos/data/repositories/shift_repository.dart';
import 'package:laundry_pos/domain/models/enums.dart';
import 'package:laundry_pos/domain/models/models.dart';
import 'package:laundry_pos/domain/price_calculator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Shift menentukan apakah selisih kas bisa dilacak. Kalau hitungannya salah,
/// pemilik akan menuduh kasir atau sebaliknya tanpa dasar.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late ShiftRepository shifts;
  late OrderRepository orders;

  const calc = PriceCalculator();

  late AppUser owner;
  late Customer budi;
  late LaundryService kiloan;

  setUp(() async {
    db = AppDatabase.instance;
    await db.close();
    await db.openInMemory();

    shifts = ShiftRepository(db);
    orders = OrderRepository(db);

    owner = (await UserRepository(db).all()).first;
    kiloan = (await ServiceRepository(db).all())
        .firstWhere((s) => s.unit == ServiceUnit.kg);
    budi = await CustomerRepository(db)
        .saveOrGet(const Customer(name: 'Budi', phone: '6281234567890'));
  });

  tearDown(() async => db.close());

  Future<LaundryOrder> order({
    int bayar = 0,
    String metode = 'Tunai',
    int? shiftId,
  }) {
    return orders.create(
      customer: budi,
      items: [calc.buildItem(kiloan, 4.0)], // 28.000
      services: [kiloan],
      user: owner,
      initialPayment: bayar,
      paymentMethod: metode,
      shiftId: shiftId,
    );
  }

  group('membuka shift', () {
    test('shift baru tersimpan dengan kas awalnya', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);

      expect(shift.id, isNotNull);
      expect(shift.openingCash, 100000);
      expect(shift.isOpen, isTrue);
    });

    test('membuka dua kali mengembalikan shift yang sama', () async {
      final a = await shifts.open(userId: owner.id!, openingCash: 100000);
      final b = await shifts.open(userId: owner.id!, openingCash: 999999);

      expect(b.id, a.id, reason: 'tidak boleh ada dua shift berjalan');
      expect(b.openingCash, 100000);
    });

    test('tanpa shift terbuka hasilnya null', () async {
      expect(await shifts.openShiftOf(owner.id!), isNull);
    });
  });

  group('kas seharusnya', () {
    test('kas awal saja bila belum ada pembayaran', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);

      expect(await shifts.expectedCash(shift), 100000);
    });

    test('pembayaran tunai menambah kas laci', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);
      await order(bayar: 28000, shiftId: shift.id);

      expect(await shifts.expectedCash(shift), 128000);
    });

    test('transfer dan QRIS tidak menambah kas laci', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);
      await order(bayar: 28000, metode: 'QRIS', shiftId: shift.id);
      await order(bayar: 28000, metode: 'Transfer', shiftId: shift.id);

      expect(await shifts.expectedCash(shift), 100000,
          reason: 'uangnya tidak masuk laci');
    });

    test('refund tunai mengurangi kas laci', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);
      final dibayar = await order(bayar: 28000, shiftId: shift.id);

      await orders.refund(
        orderId: dibayar.id!,
        amount: 8000,
        user: owner,
        reason: 'Baju rusak',
        shiftId: shift.id,
      );

      // Refund tercatat dengan metode "Refund", bukan "Tunai", sehingga
      // tidak ikut mengurangi kas laci secara otomatis.
      expect(await shifts.expectedCash(shift), 128000);
    });

    test('pembayaran di luar shift tidak ikut terhitung', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);
      await order(bayar: 28000); // tanpa shiftId

      expect(await shifts.expectedCash(shift), 100000);
    });
  });

  group('ringkasan shift', () {
    test('menghitung uang masuk, jumlah bayar, dan per metode', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 50000);

      await order(bayar: 28000, shiftId: shift.id);
      await order(bayar: 28000, metode: 'QRIS', shiftId: shift.id);
      await order(bayar: 10000, shiftId: shift.id);

      final totals = await shifts.totalsOf(shift);

      expect(totals.cashIn, 66000);
      expect(totals.paymentCount, 3);
      expect(totals.byMethod['Tunai'], 38000);
      expect(totals.byMethod['QRIS'], 28000);
      expect(totals.cashOnly, 38000);
    });

    test('shift kosong menghasilkan angka nol, bukan galat', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 0);
      final totals = await shifts.totalsOf(shift);

      expect(totals.cashIn, 0);
      expect(totals.paymentCount, 0);
      expect(totals.byMethod, isEmpty);
    });
  });

  group('menutup shift', () {
    test('kas fisik sama dengan seharusnya berarti tidak ada selisih',
        () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);
      await order(bayar: 28000, shiftId: shift.id);

      final closed = await shifts.close(shift: shift, closingCash: 128000);

      expect(closed.expectedCash, 128000);
      expect(closed.difference, 0);
      expect(closed.isOpen, isFalse);
    });

    test('kas kurang menghasilkan selisih negatif', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);
      await order(bayar: 28000, shiftId: shift.id);

      final closed = await shifts.close(shift: shift, closingCash: 123000);

      expect(closed.difference, -5000);
    });

    test('kas lebih menghasilkan selisih positif', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);

      final closed = await shifts.close(shift: shift, closingCash: 110000);

      expect(closed.difference, 10000);
    });

    test('setelah ditutup, shift terbuka kembali kosong', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);
      await shifts.close(shift: shift, closingCash: 100000);

      expect(await shifts.openShiftOf(owner.id!), isNull);
    });

    test('shift tertutup muncul di riwayat', () async {
      final shift = await shifts.open(userId: owner.id!, openingCash: 100000);
      await shifts.close(shift: shift, closingCash: 95000);

      final history = await shifts.history();

      expect(history.length, 1);
      expect(history.first['user_name'], owner.name);
      expect(history.first['closing_cash'], 95000);
      expect(history.first['expected_cash'], 100000);
    });

    test('shift yang masih berjalan tidak muncul di riwayat', () async {
      await shifts.open(userId: owner.id!, openingCash: 100000);

      expect(await shifts.history(), isEmpty);
    });
  });
}
