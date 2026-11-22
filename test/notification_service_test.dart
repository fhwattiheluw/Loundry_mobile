import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:laundry_pos/core/formatters.dart';
import 'package:laundry_pos/data/db/app_database.dart';
import 'package:laundry_pos/data/db/settings_keys.dart';
import 'package:laundry_pos/data/repositories/master_repository.dart';
import 'package:laundry_pos/data/repositories/order_repository.dart';
import 'package:laundry_pos/data/repositories/settings_repository.dart';
import 'package:laundry_pos/domain/models/enums.dart';
import 'package:laundry_pos/domain/models/models.dart';
import 'package:laundry_pos/domain/price_calculator.dart';
import 'package:laundry_pos/services/notification/message_template.dart';
import 'package:laundry_pos/services/notification/notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pengirim palsu, supaya pengujian tidak pernah membuka WhatsApp
/// maupun menghubungi server Meta.
class FakeSender implements NotificationSender {
  FakeSender({this.succeed = true});

  bool succeed;
  final sent = <({String phone, String message})>[];

  @override
  Future<NotificationResult> send({
    required String phone,
    required String message,
  }) async {
    sent.add((phone: phone, message: message));
    return succeed
        ? const NotificationResult.sent()
        : const NotificationResult.failed('Jaringan putus');
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Template WhatsApp memformat tanggal, dan DateFormat dengan locale
  // id_ID menolak bekerja sebelum data locale dimuat. main() aplikasi
  // sudah melakukannya, tapi pengujian tidak menjalankan main().
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  late AppDatabase db;
  late SettingsRepository settings;
  late OrderRepository orders;
  late NotificationService service;
  late FakeSender manual;
  late FakeSender api;

  const calc = PriceCalculator();
  late AppUser owner;
  late LaundryOrder order;

  Future<void> build() async {
    manual = FakeSender();
    api = FakeSender();

    service = NotificationService(
      db: db,
      template: MessageTemplate(settings),
      settings: settings,
      manualSender: manual,
      apiSender: api,
    );
  }

  setUp(() async {
    db = AppDatabase.instance;
    await db.close();
    await db.openInMemory();

    settings = SettingsRepository(db);
    await settings.loadAll(force: true);

    orders = OrderRepository(db);
    owner = (await UserRepository(db).all()).first;

    final kiloan = (await ServiceRepository(db).all())
        .firstWhere((s) => s.unit == ServiceUnit.kg);
    final budi = await CustomerRepository(db)
        .saveOrGet(const Customer(name: 'Budi', phone: '6281234567890'));

    order = await orders.create(
      customer: budi,
      items: [calc.buildItem(kiloan, 4.0)],
      services: [kiloan],
      user: owner,
    );

    await build();
  });

  tearDown(() async => db.close());

  group('pemilihan mode', () {
    test('bawaan memakai mode manual', () async {
      await service.notify(order, NotificationTrigger.orderDiterima);

      expect(manual.sent.length, 1);
      expect(api.sent, isEmpty);
    });

    test('mode api memakai pengirim api', () async {
      await settings.set(SettingsKeys.whatsappMode, 'api');
      await build();

      await service.notify(order, NotificationTrigger.orderDiterima);

      expect(api.sent.length, 1);
      expect(manual.sent, isEmpty);
    });
  });

  group('isi pesan', () {
    test('order tanpa item (dari daftar) tetap memuat rincian lengkap',
        () async {
      // Daftar order dimuat tanpa item; pesan harus tetap lengkap.
      final fromList = order.copyWith(items: const []);

      await service.notify(
        fromList,
        NotificationTrigger.pengingatAmbil,
        force: true,
      );

      final message = manual.sent.single.message;
      expect(message, contains(order.items.first.serviceName));
      expect(message, contains('${formatQty(order.items.first.qty)} '
          '${order.items.first.unit.label}'));
      expect(message, contains('Sudah dibayar'));
      expect(message, contains('Sisa tagihan'));
    });

    test('jumlah dibayar mengikuti database, bukan objek yang usang', () async {
      await orders.addPayment(
        orderId: order.id!,
        amount: 10000,
        method: 'Tunai',
        user: owner,
      );

      // `order` dibuat sebelum pembayaran: paid = 0.
      await service.notify(
        order,
        NotificationTrigger.pembayaranDiterima,
        force: true,
      );

      expect(manual.sent.single.message, contains(formatRupiah(10000)));
    });
  });

  group('anti kirim ganda', () {
    test('pemicu yang sama tidak terkirim dua kali', () async {
      final pertama =
          await service.notify(order, NotificationTrigger.orderDiterima);
      final kedua =
          await service.notify(order, NotificationTrigger.orderDiterima);

      expect(pertama.sent, isTrue);
      expect(kedua.skipped, isTrue);
      expect(manual.sent.length, 1);
    });

    test('force menembus aturan itu, untuk pengingat berulang', () async {
      await service.notify(order, NotificationTrigger.pengingatAmbil);
      await service.notify(order, NotificationTrigger.pengingatAmbil,
          force: true);

      expect(manual.sent.length, 2);
    });

    test('pemicu berbeda tetap boleh terkirim', () async {
      await service.notify(order, NotificationTrigger.orderDiterima);
      await service.notify(order, NotificationTrigger.cucianSelesai);

      expect(manual.sent.length, 2);
    });
  });

  group('pemicu yang dimatikan', () {
    test('tidak mengirim apa pun', () async {
      await settings.set(SettingsKeys.notifyOrderCreated, '0');
      await build();

      final result =
          await service.notify(order, NotificationTrigger.orderDiterima);

      expect(result.skipped, isTrue);
      expect(manual.sent, isEmpty);
    });

    test('pembayaran diterima mati secara bawaan', () async {
      final result =
          await service.notify(order, NotificationTrigger.pembayaranDiterima);

      expect(result.skipped, isTrue);
    });
  });

  group('jam tenang', () {
    test('mati berarti pesan langsung dikirim', () async {
      await service.notify(order, NotificationTrigger.orderDiterima);
      expect(manual.sent.length, 1);
    });

    test('rentang yang mencakup seluruh hari menunda pesan', () async {
      // 00:00 sampai 23:59 memastikan pengujian tidak bergantung jam berapa
      // berkas ini dijalankan.
      await settings.setAll({
        SettingsKeys.quietHoursEnabled: '1',
        SettingsKeys.quietHoursStart: '00:00',
        SettingsKeys.quietHoursEnd: '23:59',
      });
      await build();

      final result =
          await service.notify(order, NotificationTrigger.orderDiterima);

      expect(result.skipped, isTrue);
      expect(manual.sent, isEmpty);
      expect(await service.pendingCount(), 1);
    });

    test('rentang kosong sepanjang hari tetap mengirim', () async {
      await settings.setAll({
        SettingsKeys.quietHoursEnabled: '1',
        SettingsKeys.quietHoursStart: '00:00',
        SettingsKeys.quietHoursEnd: '00:00',
      });
      await build();

      final result =
          await service.notify(order, NotificationTrigger.orderDiterima);

      expect(result.sent, isTrue);
    });

    test('format jam yang salah diabaikan, pesan tetap terkirim', () async {
      await settings.setAll({
        SettingsKeys.quietHoursEnabled: '1',
        SettingsKeys.quietHoursStart: 'pagi',
        SettingsKeys.quietHoursEnd: 'malam',
      });
      await build();

      expect(
        (await service.notify(order, NotificationTrigger.orderDiterima)).sent,
        isTrue,
      );
    });
  });

  group('antrean kirim ulang', () {
    test('gagal di mode manual tidak dijadwalkan ulang otomatis', () async {
      manual.succeed = false;

      await service.notify(order, NotificationTrigger.orderDiterima);

      // Tercatat sebagai gagal supaya pemilik bisa kirim ulang sendiri,
      // tapi tidak punya jadwal percobaan berikutnya.
      expect(await service.pendingCount(), 1);
      expect(await service.processQueue(), 0);
    });

    test('gagal di mode api dicoba ulang dan berhasil', () async {
      await settings.set(SettingsKeys.whatsappMode, 'api');
      await build();
      api.succeed = false;

      await service.notify(order, NotificationTrigger.orderDiterima);
      expect(await service.pendingCount(), 1);

      // Majukan waktu percobaan supaya tidak perlu menunggu dua menit.
      final raw = await db.database;
      await raw.update('notification_logs', {
        'next_attempt_at':
            DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
      });

      api.succeed = true;
      final delivered = await service.processQueue();

      expect(delivered, 1);
      expect(await service.pendingCount(), 0);
    });

    test('menyerah setelah tiga percobaan', () async {
      await settings.set(SettingsKeys.whatsappMode, 'api');
      await build();
      api.succeed = false;

      await service.notify(order, NotificationTrigger.orderDiterima);

      final raw = await db.database;
      for (var i = 0; i < 5; i++) {
        // Hanya majukan jadwal baris yang MASIH menunggu. Baris yang sudah
        // menyerah punya next_attempt_at null, dan null itu harus tetap null.
        await raw.update(
          'notification_logs',
          {
            'next_attempt_at': DateTime.now()
                .subtract(const Duration(minutes: 1))
                .toIso8601String(),
          },
          where: 'next_attempt_at IS NOT NULL',
        );
        await service.processQueue();
      }

      final rows = await raw.query('notification_logs');
      expect(rows.first['attempts'], 3);
      expect(rows.first['next_attempt_at'], isNull);
      expect(await service.pendingCount(), 0,
          reason: 'sudah menyerah, bukan lagi menunggu');
    });

    test('isi pesan disimpan supaya kirim ulang tidak memakai template baru',
        () async {
      manual.succeed = false;
      await service.notify(order, NotificationTrigger.orderDiterima);

      final raw = await db.database;
      final rows = await raw.query('notification_logs');

      expect(rows.first['message'], isNotNull);
      expect(rows.first['message'] as String, contains(order.orderNo));
    });
  });

  group('kirim ulang manual', () {
    test('mengubah status menjadi terkirim', () async {
      manual.succeed = false;
      await service.notify(order, NotificationTrigger.orderDiterima);

      final raw = await db.database;
      final id = (await raw.query('notification_logs')).first['id'] as int;

      manual.succeed = true;
      final result = await service.resend(id);

      expect(result.sent, isTrue);
      expect(await service.pendingCount(), 0);
    });
  });

  group('pelanggan tanpa nomor', () {
    test('dilewati tanpa mencatat kegagalan', () async {
      final tanpaNomor = await CustomerRepository(db)
          .saveOrGet(const Customer(name: 'Tanpa HP', phone: ''));

      final kiloan = (await ServiceRepository(db).all())
          .firstWhere((s) => s.unit == ServiceUnit.kg);

      final lain = await orders.create(
        customer: tanpaNomor,
        items: [calc.buildItem(kiloan, 4.0)],
        services: [kiloan],
        user: owner,
      );

      final result =
          await service.notify(lain, NotificationTrigger.orderDiterima);

      expect(result.skipped, isTrue);
      expect(await service.pendingCount(), 0);
    });
  });
}
