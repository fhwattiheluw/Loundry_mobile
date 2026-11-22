import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';

class PrinterDevice {
  const PrinterDevice({required this.name, required this.address});

  final String name;
  final String address;
}

/// Hasil percetakan. Kegagalan printer TIDAK boleh membatalkan order
/// yang sudah tersimpan (FR-87), jadi kelas ini mengembalikan status,
/// bukan melempar galat ke layar transaksi.
class PrintResult {
  const PrintResult.ok()
      : success = true,
        message = '';
  const PrintResult.failed(this.message) : success = false;

  final bool success;
  final String message;
}

/// Pembungkus tunggal untuk printer thermal.
///
/// Seluruh aplikasi mencetak lewat kelas ini. Mengganti merek atau pustaka
/// printer cukup mengubah file ini, tanpa menyentuh layar transaksi.
class ReceiptPrinter {
  ReceiptPrinter(this._settings);

  final SettingsRepository _settings;

  /// Izin runtime Android 12 ke atas memakai BLUETOOTH_CONNECT dan
  /// BLUETOOTH_SCAN, bukan lagi izin lokasi.
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;

    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<bool> get isBluetoothOn async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  Future<List<PrinterDevice>> pairedDevices() async {
    if (!await ensurePermissions()) return const [];

    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      return devices
          .map((d) => PrinterDevice(name: d.name, address: d.macAdress))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> get isConnected async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveDefault(PrinterDevice device) async {
    await _settings.setAll({
      SettingsKeys.printerAddress: device.address,
      SettingsKeys.printerName: device.name,
    });
  }

  String get defaultPrinterName => _settings.get(SettingsKeys.printerName);

  /// Menyambung ke printer tersimpan. Tidak melakukan apa-apa bila
  /// sambungan sudah terbuka.
  Future<PrintResult> connect({String? address}) async {
    final mac = address ?? _settings.get(SettingsKeys.printerAddress);

    if (mac.isEmpty) {
      return const PrintResult.failed(
          'Printer belum dipilih. Buka Pengaturan lalu pilih printer.');
    }

    if (!await ensurePermissions()) {
      return const PrintResult.failed(
          'Izin Bluetooth ditolak. Aktifkan izin di pengaturan Android.');
    }

    if (!await isBluetoothOn) {
      return const PrintResult.failed('Bluetooth mati. Nyalakan Bluetooth.');
    }

    if (await isConnected) return const PrintResult.ok();

    try {
      final connected =
          await PrintBluetoothThermal.connect(macPrinterAddress: mac);

      return connected
          ? const PrintResult.ok()
          : const PrintResult.failed(
              'Printer tidak merespons. Pastikan printer menyala dan dalam jangkauan.');
    } catch (e) {
      return PrintResult.failed('Gagal menyambung ke printer: $e');
    }
  }

  /// Mencetak byte ESC/POS sebanyak jumlah salinan yang diatur pemilik.
  Future<PrintResult> printBytes(List<int> bytes, {int? copies}) async {
    final connection = await connect();
    if (!connection.success) return connection;

    final count =
        copies ?? _settings.getInt(SettingsKeys.receiptCopies, fallback: 2);

    try {
      for (var i = 0; i < count.clamp(1, 5); i++) {
        final ok = await PrintBluetoothThermal.writeBytes(bytes);
        if (!ok) {
          return const PrintResult.failed(
              'Data gagal dikirim ke printer. Coba cetak ulang dari detail order.');
        }
      }
      return const PrintResult.ok();
    } catch (e) {
      return PrintResult.failed('Gagal mencetak: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {
      // Tidak penting. Sambungan akan tertutup sendiri saat printer mati.
    }
  }
}
