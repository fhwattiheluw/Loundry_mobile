import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/data/db/app_database.dart';
import 'package:laundry_pos/data/repositories/master_repository.dart';
import 'package:laundry_pos/data/repositories/order_repository.dart';
import 'package:laundry_pos/data/repositories/report_repository.dart';
import 'package:laundry_pos/domain/models/enums.dart';
import 'package:laundry_pos/domain/models/models.dart';
import 'package:laundry_pos/domain/price_calculator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Aturan paling penting di aplikasi ini: pendapatan dihitung dari uang yang
/// benar-benar diterima, bukan dari nilai order. Berkas ini yang menjaganya.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late OrderRepository orders;
  late ReportRepository reports;
  late ServiceRepository services;
  late CustomerRepository customers;
  late UserRepository users;

  const calc = PriceCalculator();

  late AppUser owner;
  late Customer budi;
  late LaundryService kiloan;

  setUp(() async {
    db = AppDatabase.instance;
    await db.close();
    await db.openInMemory();

    orders = OrderRepository(db);
    reports = ReportRepository(db);
    services = ServiceRepository(db);
    customers = CustomerRepository(db);
    users = UserRepository(db);

    owner = (await users.all()).first;
    kiloan = (await services.all()).firstWhere((s) => s.unit == ServiceUnit.kg);
    budi = await customers.saveOrGet(
      const Customer(name: 'Budi', phone: '6281234567890'),
    );
  });

  tearDown(() async => db.close());

  Future<LaundryOrder> buatOrder({
    double berat = 4.0,
    int bayar = 0,
    int diskon = 0,
  }) async {
    return orders.create(
      customer: budi,
      items: [calc.buildItem(kiloan, berat)],
      services: [kiloan],
      user: owner,
      discount: diskon,
      initialPayment: bayar,
    );
  }

  group('nomor order', () {
    test('urut per hari dan unik', () async {
      final a = await buatOrder();
      final b = await buatOrder();

      expect(a.orderNo, endsWith('-001'));
      expect(b.orderNo, endsWith('-002'));
      expect(a.orderNo, isNot(b.orderNo));
    });
  });

  group('status bayar', () {
    test('order tanpa pembayaran berstatus belum bayar', () async {
      final order = await buatOrder();

      expect(order.paymentStatus, PaymentStatus.belumBayar);
      expect(order.paid, 0);
      expect(order.remaining, order.total);
    });

    test('DP mengubah status menjadi dp', () async {
      final order = await buatOrder(bayar: 10000);

      expect(order.paymentStatus, PaymentStatus.dp);
      expect(order.paid, 10000);
    });

    test('pelunasan mengubah status menjadi lunas', () async {
      final order = await buatOrder(bayar: 10000);

      await orders.addPayment(
        orderId: order.id!,
        amount: order.remaining,
        method: 'Tunai',
        user: owner,
      );

      final fresh = await orders.byId(order.id!);
      expect(fresh!.paymentStatus, PaymentStatus.lunas);
      expect(fresh.remaining, 0);
    });
  });

  group('laporan pendapatan', () {
    test('order belum dibayar tidak menambah pendapatan', () async {
      await buatOrder(bayar: 0);

      final summary = await reports.summary(DateTime.now(), DateTime.now());

      expect(summary.orderCount, 1);
      expect(summary.cashIn, 0, reason: 'piutang bukan pendapatan');
      expect(summary.grossOrderValue, 28000);
      expect(summary.newReceivable, 28000);
    });

    test('pendapatan sama dengan uang yang diterima', () async {
      await buatOrder(bayar: 10000);
      await buatOrder(bayar: 28000);

      final summary = await reports.summary(DateTime.now(), DateTime.now());

      expect(summary.cashIn, 38000);
      expect(summary.orderCount, 2);
    });

    test('refund mengurangi pendapatan dan tidak menghapus data', () async {
      final order = await buatOrder(bayar: 28000);

      await orders.refund(
        orderId: order.id!,
        amount: 8000,
        user: owner,
        reason: 'Baju rusak',
      );

      final summary = await reports.summary(DateTime.now(), DateTime.now());

      expect(summary.cashIn, 20000);
      expect(summary.refundTotal, 8000);

      final payments = await orders.paymentsOf(order.id!);
      expect(payments.length, 2, reason: 'pembayaran asli tetap tersimpan');
      expect(payments.last.amount, -8000);
    });

    test('refund memunculkan sisa tagihan yang sama di ringkasan dan daftar',
        () async {
      final order = await buatOrder(bayar: 28000);

      await orders.refund(
        orderId: order.id!,
        amount: 8000,
        user: owner,
        reason: 'Salah hitung',
      );

      final summary = await reports.summary(DateTime.now(), DateTime.now());
      final rows = await reports.receivables();
      final totalDaftar = rows.fold(0, (sum, r) => sum + r.remaining);

      expect(summary.newReceivable, 8000);
      expect(totalDaftar, summary.newReceivable,
          reason: 'ringkasan dan daftar piutang harus sepakat');
    });

    test('kelebihan bayar satu order tidak mengurangi piutang order lain',
        () async {
      await buatOrder(bayar: 0);

      final lebih = await buatOrder(bayar: 28000);
      await orders.addPayment(
        orderId: lebih.id!,
        amount: 5000,
        method: 'Tunai',
        user: owner,
      );

      final summary = await reports.summary(DateTime.now(), DateTime.now());

      expect(summary.newReceivable, 28000);
    });

    test('order dibatalkan keluar dari hitungan order', () async {
      final order = await buatOrder();
      await orders.cancel(order.id!, user: owner, reason: 'Pelanggan batal');

      final summary = await reports.summary(DateTime.now(), DateTime.now());

      expect(summary.orderCount, 0);

      final fresh = await orders.byId(order.id!);
      expect(fresh, isNotNull, reason: 'data tidak dihapus');
      expect(fresh!.laundryStatus, LaundryStatus.dibatalkan);
      expect(fresh.cancelReason, 'Pelanggan batal');
    });

    test('diskon dilaporkan terpisah', () async {
      await buatOrder(diskon: 3000, bayar: 25000);

      final summary = await reports.summary(DateTime.now(), DateTime.now());

      expect(summary.discountTotal, 3000);
      expect(summary.grossOrderValue, 25000);
      expect(summary.cashIn, 25000);
    });

    test('pendapatan per metode bayar dipisah', () async {
      await buatOrder(bayar: 28000);
      final kedua = await buatOrder();

      await orders.addPayment(
        orderId: kedua.id!,
        amount: 28000,
        method: 'QRIS',
        user: owner,
      );

      final rows = await reports.byMethod(DateTime.now(), DateTime.now());
      final byName = {for (final r in rows) r.name: r.amount};

      expect(byName['Tunai'], 28000);
      expect(byName['QRIS'], 28000);
    });

    test('grafik harian mengisi hari kosong dengan nol', () async {
      await buatOrder(bayar: 28000);

      final now = DateTime.now();
      final days = await reports.dailyRevenue(
        now.subtract(const Duration(days: 4)),
        now,
      );

      expect(days.length, 5);
      expect(days.last.amount, 28000);
      expect(days.first.amount, 0);
    });
  });

  group('piutang', () {
    test('hanya memuat order yang benar-benar masih bersisa', () async {
      await buatOrder(bayar: 0);
      await buatOrder(bayar: 10000);
      await buatOrder(bayar: 28000);

      final rows = await reports.receivables();

      expect(rows.length, 2);
      expect(rows.map((r) => r.remaining), containsAll([28000, 18000]));
    });

    test('order batal tidak muncul sebagai piutang', () async {
      final order = await buatOrder(bayar: 0);
      await orders.cancel(order.id!, user: owner, reason: 'Salah input');

      final rows = await reports.receivables();
      expect(rows, isEmpty);
    });
  });

  group('status cucian', () {
    test('perubahan status tercatat dengan penggunanya', () async {
      final order = await buatOrder();

      await orders.changeStatus(order.id!, LaundryStatus.diproses,
          user: owner);
      await orders.changeStatus(order.id!, LaundryStatus.selesai, user: owner);

      final history = await orders.statusHistory(order.id!);

      expect(history.length, 3, reason: 'termasuk status awal diterima');
      expect(history.last['status'], 'selesai');
      expect(history.last['user_name'], owner.name);
    });

    test('pengambilan mencatat waktu dan nama pengambil', () async {
      final order = await buatOrder(bayar: 28000);

      await orders.changeStatus(
        order.id!,
        LaundryStatus.diambil,
        user: owner,
        pickedUpBy: 'Adik Budi',
      );

      final fresh = await orders.byId(order.id!);
      expect(fresh!.pickedUpAt, isNotNull);
      expect(fresh.pickedUpBy, 'Adik Budi');
    });
  });

  group('pelanggan', () {
    test('nomor yang sama tidak membuat pelanggan ganda', () async {
      final a = await customers.saveOrGet(
        const Customer(name: 'Budi Lagi', phone: '081234567890'),
      );

      expect(a.id, budi.id);
    });

    test('nomor dinormalisasi ke format 62', () async {
      final baru = await customers.saveOrGet(
        const Customer(name: 'Siti', phone: '0857-1111-2222'),
      );

      expect(baru.phone, '6285711112222');
    });
  });
}
