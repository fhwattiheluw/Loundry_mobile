import 'package:sqflite/sqflite.dart';

import '../../core/security.dart';
import 'settings_keys.dart';

/// Data awal supaya aplikasi langsung bisa dipakai setelah dipasang.
/// Pemilik mengubah semuanya lewat layar Pengaturan.
Future<void> seedInitialData(Database db) async {
  final now = DateTime.now().toIso8601String();

  await db.insert('users', {
    'name': 'Owner',
    'pin_hash': hashPin('1234'),
    'role': 'owner',
    'active': 1,
  });

  const services = [
    {
      'name': 'Cuci Kering Lipat',
      'unit': 'kg',
      'price': 7000,
      'duration_hours': 48,
      'min_qty': 3.0,
      'rounding_step': 0.1,
    },
    {
      'name': 'Cuci Setrika',
      'unit': 'kg',
      'price': 10000,
      'duration_hours': 72,
      'min_qty': 3.0,
      'rounding_step': 0.1,
    },
    {
      'name': 'Setrika Saja',
      'unit': 'kg',
      'price': 6000,
      'duration_hours': 24,
      'min_qty': 2.0,
      'rounding_step': 0.1,
    },
    {
      'name': 'Bed Cover',
      'unit': 'pcs',
      'price': 35000,
      'duration_hours': 72,
      'min_qty': 1.0,
      'rounding_step': 0.0,
    },
    {
      'name': 'Selimut',
      'unit': 'pcs',
      'price': 25000,
      'duration_hours': 72,
      'min_qty': 1.0,
      'rounding_step': 0.0,
    },
    {
      'name': 'Karpet',
      'unit': 'meter',
      'price': 20000,
      'duration_hours': 96,
      'min_qty': 1.0,
      'rounding_step': 0.5,
    },
  ];

  for (final service in services) {
    await db.insert('services', {
      ...service,
      'express_multiplier': 2.0,
      'express_duration_hours': 6,
      'active': 1,
    });
  }

  final defaults = <String, String>{
    SettingsKeys.businessName: 'Laundry Saya',
    SettingsKeys.businessAddress: 'Jl. Contoh No. 1',
    SettingsKeys.businessPhone: '',
    SettingsKeys.receiptFooter:
        'Klaim maksimal 2x24 jam setelah pengambilan.\n'
        'Cucian tidak diambil lebih dari 30 hari di luar tanggung jawab kami.',
    SettingsKeys.paperWidth: '58',
    SettingsKeys.printerAddress: '',
    SettingsKeys.printerName: '',
    SettingsKeys.receiptCopies: '1',
    SettingsKeys.reminderDays: '3',
    SettingsKeys.maxCashierDiscount: '10000',
    SettingsKeys.openHours: 'Buka 08.00 - 20.00',
    SettingsKeys.paymentMethods: 'Tunai,Transfer,QRIS',
    SettingsKeys.adsEnabled: '1',
    SettingsKeys.notifyOrderCreated: '1',
    SettingsKeys.notifyOrderDone: '1',
    SettingsKeys.notifyReminder: '1',
    SettingsKeys.templateOrderCreated:
        'Halo {nama}, pesanan laundry Anda sudah kami terima.\n\n'
        'No. Nota: {no_order}\n'
        'Layanan: {layanan}\n'
        'Total: {total}\n'
        'Status bayar: {status_bayar}\n'
        'Estimasi selesai: {estimasi}\n\n'
        'Terima kasih. {nama_usaha}',
    SettingsKeys.templateOrderDone:
        'Halo {nama}, cucian Anda sudah selesai dan siap diambil.\n\n'
        'No. Nota: {no_order}\n'
        'Sisa tagihan: {sisa}\n'
        '{jam_buka}\n\n'
        'Terima kasih. {nama_usaha}',
    SettingsKeys.templateReminder:
        'Halo {nama}, cucian Anda dengan nota {no_order} sudah selesai '
        'sejak {estimasi} dan belum diambil.\n\n'
        'Sisa tagihan: {sisa}\n'
        'Mohon diambil ya. Terima kasih. {nama_usaha}',
    SettingsKeys.seededAt: now,
  };

  for (final entry in defaults.entries) {
    await db.insert('settings', {'key': entry.key, 'value': entry.value});
  }
}
