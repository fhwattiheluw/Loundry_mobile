import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/data/db/app_database.dart';
import 'package:laundry_pos/data/repositories/master_repository.dart';
import 'package:laundry_pos/data/repositories/order_repository.dart';
import 'package:laundry_pos/domain/models/enums.dart';
import 'package:laundry_pos/domain/models/models.dart';
import 'package:laundry_pos/domain/price_calculator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Perbaikan dari audit fitur. Tiap tes di sini lahir dari bug yang nyata:
/// salah catat pelanggan, pencarian yang tidak menyaring, status order batal
/// yang bisa diubah, dan cucian "menumpuk" yang dihitung dari estimasi.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late OrderRepository orders;
  late CustomerRepository customers;

  const calc = PriceCalculator();

  late AppUser owner;
  late LaundryService kiloan;

  setUp(() async {
    db = AppDatabase.instance;
    await db.close();
    await db.openInMemory();

    orders = OrderRepository(db);
    customers = CustomerRepository(db);

    owner = (await UserRepository(db).all()).first;
    kiloan = (await ServiceRepository(db).all())
        .firstWhere((s) => s.unit == ServiceUnit.kg);
  });

  tearDown(() async => db.close());

  Future<LaundryOrder> buatOrder(Customer customer, {int bayar = 0}) {
    return orders.create(
      customer: customer,
      items: [calc.buildItem(kiloan, 4.0)],
      services: [kiloan],
      user: owner,
      initialPayment: bayar,
    );
  }

  group('pencarian pelanggan', () {
    setUp(() async {
      await customers.saveOrGet(
        const Customer(name: 'Budi Santoso', phone: '081234567890'),
      );
      await customers.saveOrGet(
        const Customer(name: 'Ani Wijaya', phone: '085711112222'),
      );
      await customers.saveOrGet(const Customer(name: 'Citra', phone: ''));
    });

    test('mencari nama hanya mengembalikan nama yang cocok', () async {
      final hasil = await customers.search('Budi');

      expect(hasil.map((c) => c.name), ['Budi Santoso']);
    });

    test('mencari nama tidak peduli huruf besar kecil', () async {
      final hasil = await customers.search('ani');

      expect(hasil.map((c) => c.name), ['Ani Wijaya']);
    });

    test('mencari nomor, dengan awalan 0, menemukan pemiliknya', () async {
      final hasil = await customers.search('0857');

      expect(hasil.map((c) => c.name), ['Ani Wijaya']);
    });

    test('kata kunci kosong mengembalikan semua', () async {
      expect((await customers.search('')).length, 3);
    });

    test('nama yang tidak ada mengembalikan daftar kosong', () async {
      expect(await customers.search('Zainal'), isEmpty);
    });
  });

  group('pelanggan tanpa nomor HP', () {
    test('dua nama berbeda menjadi dua pelanggan', () async {
      final ani = await customers.saveOrGet(
        const Customer(name: 'Ani', phone: ''),
      );
      final budi = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: ''),
      );

      expect(budi.id, isNot(ani.id));
      expect(await customers.count(), 2);
    });

    test('order tercatat atas nama yang benar', () async {
      final ani = await customers.saveOrGet(
        const Customer(name: 'Ani', phone: ''),
      );
      final budi = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: ''),
      );

      final orderBudi = await buatOrder(budi);
      final orderAni = await buatOrder(ani);

      expect(orderBudi.customerName, 'Budi');
      expect(orderAni.customerName, 'Ani');
    });

    test('nama yang sama dipakai ulang, huruf besar kecil tidak dibedakan',
        () async {
      final pertama = await customers.saveOrGet(
        const Customer(name: 'Ani', phone: ''),
      );
      final kedua = await customers.saveOrGet(
        const Customer(name: '  ani ', phone: ''),
      );

      expect(kedua.id, pertama.id);
      expect(await customers.count(), 1);
    });

    test('pelanggan tanpa nomor tidak ditemukan lewat nomor kosong', () async {
      await customers.saveOrGet(const Customer(name: 'Ani', phone: ''));

      expect(await customers.findByPhone(''), isNull);
    });

    test('nomor yang terisi tetap unik di tingkat database', () async {
      await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );

      final raw = await db.database;
      await expectLater(
        raw.insert('customers', {
          'name': 'Palsu',
          'phone': '6281234567890',
          'created_at': DateTime.now().toIso8601String(),
        }),
        throwsA(anything),
      );
    });

    test('nomor yang sama tidak membuat pelanggan ganda', () async {
      final a = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final b = await customers.saveOrGet(
        const Customer(name: 'Budi Lagi', phone: '+62 812-3456-7890'),
      );

      expect(b.id, a.id);
    });
  });

  group('status order', () {
    test('order batal tidak bisa diubah statusnya', () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final order = await buatOrder(pelanggan);
      await orders.cancel(order.id!, user: owner, reason: 'Salah input');

      await expectLater(
        orders.changeStatus(order.id!, LaundryStatus.diproses, user: owner),
        throwsStateError,
      );

      final fresh = await orders.byId(order.id!);
      expect(fresh!.laundryStatus, LaundryStatus.dibatalkan);
    });

    test('pembatalan lewat ubah status ditolak, harus lewat cancel', () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final order = await buatOrder(pelanggan);

      await expectLater(
        orders.changeStatus(order.id!, LaundryStatus.dibatalkan, user: owner),
        throwsStateError,
      );
    });

    test('status yang sama dua kali hanya menulis satu log', () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final order = await buatOrder(pelanggan);

      await orders.changeStatus(order.id!, LaundryStatus.diproses, user: owner);
      await orders.changeStatus(order.id!, LaundryStatus.diproses, user: owner);

      final history = await orders.statusHistory(order.id!);
      expect(history.length, 2, reason: 'diterima dan diproses, tanpa ganda');
    });

    test('membatalkan dua kali tidak menimpa alasan pertama', () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final order = await buatOrder(pelanggan);

      await orders.cancel(order.id!, user: owner, reason: 'Alasan pertama');
      await orders.cancel(order.id!, user: owner, reason: 'Alasan kedua');

      final fresh = await orders.byId(order.id!);
      expect(fresh!.cancelReason, 'Alasan pertama');

      final history = await orders.statusHistory(order.id!);
      expect(history.where((h) => h['status'] == 'dibatalkan').length, 1);
    });

    test('changeStatusBulk melewati order batal dan lanjut ke sisanya',
        () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final batal = await buatOrder(pelanggan);
      final aktif = await buatOrder(pelanggan);
      await orders.cancel(batal.id!, user: owner, reason: 'Batal');

      await orders.changeStatusBulk(
        [batal.id!, aktif.id!],
        LaundryStatus.diproses,
        user: owner,
      );

      final fresh = await orders.byId(aktif.id!);
      expect(fresh!.laundryStatus, LaundryStatus.diproses);
    });
  });

  group('pembayaran order batal', () {
    test('pembayaran baru ke order batal ditolak', () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final order = await buatOrder(pelanggan);
      await orders.cancel(order.id!, user: owner, reason: 'Batal');

      await expectLater(
        orders.addPayment(
          orderId: order.id!,
          amount: 5000,
          method: 'Tunai',
          user: owner,
        ),
        throwsStateError,
      );
    });

    test('refund ke order batal yang sudah dibayar tetap boleh', () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final order = await buatOrder(pelanggan, bayar: 10000);
      await orders.cancel(order.id!, user: owner, reason: 'Batal');

      await orders.refund(
        orderId: order.id!,
        amount: 10000,
        user: owner,
        reason: 'Order dibatalkan',
      );

      final fresh = await orders.byId(order.id!);
      expect(fresh!.paid, 0);
    });
  });

  group('cucian menumpuk', () {
    Future<void> setLog(int orderId, String status, DateTime at) async {
      final raw = await db.database;
      await raw.update(
        'status_logs',
        {'changed_at': at.toIso8601String()},
        where: 'order_id = ? AND status = ?',
        whereArgs: [orderId, status],
      );
    }

    Future<void> setEstimate(int orderId, DateTime at) async {
      final raw = await db.database;
      await raw.update(
        'orders',
        {'estimated_at': at.toIso8601String()},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    }

    test('dihitung dari saat selesai, bukan dari estimasi', () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final order = await buatOrder(pelanggan);

      // Diperkirakan jadi 5 hari lalu, tapi baru ditandai selesai sekarang.
      await setEstimate(order.id!, DateTime.now().subtract(const Duration(days: 5)));
      await orders.changeStatus(order.id!, LaundryStatus.selesai, user: owner);

      final stale = await orders.staleOrders(3);

      expect(stale, isEmpty,
          reason: 'baru selesai hari ini, belum menumpuk');
    });

    test('menumpuk bila sudah selesai lebih lama dari batas hari', () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final order = await buatOrder(pelanggan);

      await orders.changeStatus(order.id!, LaundryStatus.selesai, user: owner);
      final selesaiSejak = DateTime.now().subtract(const Duration(days: 4));
      await setLog(order.id!, 'selesai', selesaiSejak);

      final stale = await orders.staleOrders(3);

      expect(stale.length, 1);
      expect(stale.first.id, order.id);
      expect(stale.first.finishedAt, isNotNull);
      expect(
        stale.first.finishedAt!.difference(selesaiSejak).inSeconds.abs(),
        lessThan(2),
      );
    });

    test('order yang sudah diambil tidak ikut', () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final order = await buatOrder(pelanggan, bayar: 99999);

      await orders.changeStatus(order.id!, LaundryStatus.selesai, user: owner);
      await setLog(
          order.id!, 'selesai', DateTime.now().subtract(const Duration(days: 9)));
      await orders.changeStatus(order.id!, LaundryStatus.diambil, user: owner);

      expect(await orders.staleOrders(3), isEmpty);
    });

    test('yang paling lama selesai tampil paling atas', () async {
      final pelanggan = await customers.saveOrGet(
        const Customer(name: 'Budi', phone: '081234567890'),
      );
      final baru = await buatOrder(pelanggan);
      final lama = await buatOrder(pelanggan);

      for (final o in [baru, lama]) {
        await orders.changeStatus(o.id!, LaundryStatus.selesai, user: owner);
      }
      await setLog(
          baru.id!, 'selesai', DateTime.now().subtract(const Duration(days: 4)));
      await setLog(
          lama.id!, 'selesai', DateTime.now().subtract(const Duration(days: 8)));

      final stale = await orders.staleOrders(3);

      expect(stale.map((o) => o.id), [lama.id, baru.id]);
    });
  });
}
