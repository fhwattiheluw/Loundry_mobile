import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:laundry_pos/core/formatters.dart';
import 'package:laundry_pos/data/db/app_database.dart';
import 'package:laundry_pos/data/db/default_templates.dart';
import 'package:laundry_pos/data/db/settings_keys.dart';
import 'package:laundry_pos/data/repositories/settings_repository.dart';
import 'package:laundry_pos/domain/models/enums.dart';
import 'package:laundry_pos/domain/models/models.dart';
import 'package:laundry_pos/services/notification/message_template.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LaundryOrder _order({
  int paid = 0,
  int discount = 0,
  int extraFee = 0,
  String customer = 'Budi',
  String? rack,
}) {
  const items = [
    OrderItem(
      serviceId: 1,
      serviceName: 'Cuci Kiloan',
      unit: ServiceUnit.kg,
      qty: 3.5,
      unitPrice: 7000,
      subtotal: 24500,
      itemDetails: '3 kemeja, 2 celana',
    ),
    OrderItem(
      serviceId: 2,
      serviceName: 'Sepatu',
      unit: ServiceUnit.pcs,
      qty: 2,
      unitPrice: 25000,
      subtotal: 50000,
      express: true,
      note: 'Sol kiri lepas',
    ),
  ];

  return LaundryOrder(
    orderNo: 'LD-20261122-0007',
    customerId: 1,
    createdBy: 1,
    createdAt: DateTime(2026, 11, 22, 9),
    estimatedAt: DateTime(2026, 11, 24, 17),
    laundryStatus: LaundryStatus.diproses,
    paymentStatus:
        paid > 0 ? PaymentStatus.dp : PaymentStatus.belumBayar,
    subtotal: 74500,
    discount: discount,
    extraFee: extraFee,
    extraFeeNote: extraFee > 0 ? 'Antar' : null,
    total: 74500 - discount + extraFee,
    paid: paid,
    rack: rack,
    items: items,
    customerName: customer,
    customerPhone: '6281234567890',
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  group('rincian item', () {
    test('memuat nama, jumlah, satuan, harga, dan subtotal tiap item', () {
      final text = MessageTemplate.itemLines(_order());

      expect(text, contains('1. Cuci Kiloan'));
      expect(
        text,
        contains('3,5 kg × ${formatRupiah(7000)} = ${formatRupiah(24500)}'),
      );
      expect(text, contains('Isi: 3 kemeja, 2 celana'));

      expect(text, contains('2. Sepatu (Express)'));
      expect(
        text,
        contains('2 pcs × ${formatRupiah(25000)} = ${formatRupiah(50000)}'),
      );
      expect(text, contains('Catatan: Sol kiri lepas'));
    });

    test('order tanpa item menghasilkan strip, bukan teks kosong', () {
      final empty = LaundryOrder(
        orderNo: 'X',
        customerId: 1,
        createdBy: 1,
        createdAt: DateTime(2026),
        estimatedAt: DateTime(2026),
        laundryStatus: LaundryStatus.diterima,
        paymentStatus: PaymentStatus.belumBayar,
        subtotal: 0,
        discount: 0,
        total: 0,
      );

      expect(MessageTemplate.itemLines(empty), '-');
    });
  });

  group('ringkasan', () {
    test('belum dibayar: sisa sama dengan total', () {
      final text = MessageTemplate.summaryLines(_order());

      expect(text, contains('Subtotal: ${formatRupiah(74500)}'));
      expect(text, contains('*Total: ${formatRupiah(74500)}*'));
      expect(text, contains('Sudah dibayar: ${formatRupiah(0)}'));
      expect(text, contains('*Sisa tagihan: ${formatRupiah(74500)}*'));
      expect(text, isNot(contains('Diskon')));
      expect(text, isNot(contains('Antar')));
    });

    test('diskon, biaya lain, dan dibayar sebagian muncul semuanya', () {
      final text = MessageTemplate.summaryLines(
        _order(paid: 30000, discount: 4500, extraFee: 5000),
      );

      expect(text, contains('Diskon: - ${formatRupiah(4500)}'));
      expect(text, contains('Antar: ${formatRupiah(5000)}'));
      expect(text, contains('*Total: ${formatRupiah(75000)}*'));
      expect(text, contains('Sudah dibayar: ${formatRupiah(30000)}'));
      expect(text, contains('*Sisa tagihan: ${formatRupiah(45000)}*'));
    });

    test('lunas ditulis LUNAS', () {
      final text = MessageTemplate.summaryLines(_order(paid: 74500));

      expect(text, contains('*Sisa tagihan: LUNAS*'));
    });
  });

  group('render', () {
    late AppDatabase db;
    late SettingsRepository settings;
    late MessageTemplate template;

    setUp(() async {
      db = AppDatabase.instance;
      await db.close();
      await db.openInMemory();
      settings = SettingsRepository(db);
      await settings.loadAll(force: true);
      template = MessageTemplate(settings);
    });

    tearDown(() async => db.close());

    test('semua template bawaan memuat rincian dan ringkasan', () {
      for (final trigger in NotificationTrigger.values) {
        final text = template.forTrigger(
          trigger,
          _order(paid: 30000, rack: 'A3'),
        );

        expect(text, contains('Cuci Kiloan'), reason: trigger.name);
        expect(text, contains('Sepatu'), reason: trigger.name);
        expect(text, contains('Sudah dibayar'), reason: trigger.name);
        expect(text, contains('Sisa tagihan'), reason: trigger.name);
        expect(text, contains('Total'), reason: trigger.name);
        expect(text, isNot(contains('{')), reason: trigger.name);
      }
    });

    test('lokasi rak ikut dikirim saat cucian selesai', () {
      final text = template.forTrigger(
        NotificationTrigger.cucianSelesai,
        _order(rack: 'A3'),
      );

      expect(text, contains('Lokasi rak:* A3'));
    });

    test('nama pelanggan berisi kurung kurawal tidak diganti ulang', () {
      final text = template.render(
        'Halo {nama}. Total {total}',
        _order(customer: '{total}'),
      );

      expect(text, startsWith('Halo {total}. Total '));
    });

    test('baris kosong berlapis dirapatkan', () async {
      await settings.set(SettingsKeys.openHours, '');
      final text = template.forTrigger(
        NotificationTrigger.cucianSelesai,
        _order(),
      );

      expect(text, isNot(contains('\n\n\n')));
    });

    test('template buatan pemilik tetap dihormati', () {
      final text = template.render('Nota {no_order}: {sisa}', _order());

      expect(text, 'Nota LD-20261122-0007: ${formatRupiah(74500)}');
    });
  });

  test('template lama dan baru berbeda, supaya migrasi bisa membedakan', () {
    expect(DefaultTemplates.legacyOrderCreated,
        isNot(DefaultTemplates.orderCreated));
    expect(
        DefaultTemplates.legacyOrderDone, isNot(DefaultTemplates.orderDone));
    expect(
        DefaultTemplates.legacyReminder, isNot(DefaultTemplates.reminder));
    expect(
        DefaultTemplates.legacyPayment, isNot(DefaultTemplates.payment));
  });
}
