import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../../core/formatters.dart';
import '../../data/db/settings_keys.dart';
import '../../data/repositories/report_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/models.dart';

/// Menyusun perintah ESC/POS untuk nota.
///
/// Semua teks dijaga tetap ASCII. Printer thermal murah menampilkan karakter
/// non-ASCII (Rp, tanda panah, huruf beraksen) sebagai sampah, dan tiap merek
/// berbeda-beda. Karena itu nominal dicetak tanpa simbol mata uang.
class ReceiptBuilder {
  ReceiptBuilder(this._settings);

  final SettingsRepository _settings;

  int get _paperWidth =>
      _settings.getInt(SettingsKeys.paperWidth, fallback: 58);

  PaperSize get _paperSize =>
      _paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;

  /// Jumlah karakter per baris: 32 untuk 58 mm, 48 untuk 80 mm.
  int get _cols => _paperWidth == 80 ? 48 : 32;

  Future<List<int>> buildOrderReceipt(
    LaundryOrder order, {
    required String cashierName,
    bool isReprint = false,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(_paperSize, profile);
    final bytes = <int>[];

    bytes.addAll(_header(g));

    if (isReprint) {
      bytes.addAll(g.text('** CETAK ULANG **',
          styles: const PosStyles(align: PosAlign.center, bold: true)));
      bytes.addAll(g.text(_line()));
    }

    bytes.addAll(_kv(g, 'No. Nota', order.orderNo));
    bytes.addAll(_kv(g, 'Masuk', formatDateTime(order.createdAt)));
    bytes.addAll(_kv(g, 'Estimasi', formatDateTime(order.estimatedAt)));
    bytes.addAll(_kv(g, 'Pelanggan', _ascii(order.customerName)));
    if (order.customerPhone.isNotEmpty) {
      bytes.addAll(_kv(g, 'No. HP', prettyPhone(order.customerPhone)));
    }
    bytes.addAll(g.text(_line()));

    for (final item in order.items) {
      bytes.addAll(g.text(_ascii(item.serviceName),
          styles: const PosStyles(bold: true)));

      final qtyLabel =
          '${formatQty(item.qty)} ${item.unit.label} x ${formatPlain(item.unitPrice)}';
      bytes.addAll(_row(g, qtyLabel, formatPlain(item.subtotal)));

      if (item.note != null && item.note!.trim().isNotEmpty) {
        bytes.addAll(g.text('  ${_ascii(item.note!)}',
            styles: const PosStyles(fontType: PosFontType.fontB)));
      }
    }

    bytes.addAll(g.text(_line()));
    bytes.addAll(_row(g, 'Subtotal', formatPlain(order.subtotal)));

    if (order.discount > 0) {
      bytes.addAll(_row(g, 'Diskon', '-${formatPlain(order.discount)}'));
    }

    bytes.addAll(_row(g, 'TOTAL', formatPlain(order.total), bold: true));
    bytes.addAll(_row(g, 'Dibayar', formatPlain(order.paid)));

    if (order.remaining > 0) {
      bytes.addAll(
          _row(g, 'SISA TAGIHAN', formatPlain(order.remaining), bold: true));
    } else {
      bytes.addAll(g.text('-- LUNAS --',
          styles: const PosStyles(align: PosAlign.center, bold: true)));
    }

    if (order.note != null && order.note!.trim().isNotEmpty) {
      bytes.addAll(g.text(_line()));
      bytes.addAll(g.text('Catatan: ${_ascii(order.note!)}'));
    }

    bytes.addAll(g.text(_line()));
    bytes.addAll(g.text('Kasir: ${_ascii(cashierName)}',
        styles: const PosStyles(fontType: PosFontType.fontB)));

    bytes.addAll(_footer(g));
    return bytes;
  }

  Future<List<int>> buildPaymentReceipt(
    LaundryOrder order,
    Payment payment, {
    required String cashierName,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(_paperSize, profile);
    final bytes = <int>[];

    bytes.addAll(_header(g));
    bytes.addAll(g.text('KWITANSI PEMBAYARAN',
        styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(g.text(_line()));

    bytes.addAll(_kv(g, 'No. Nota', order.orderNo));
    bytes.addAll(_kv(g, 'Tanggal', formatDateTime(payment.paidAt)));
    bytes.addAll(_kv(g, 'Pelanggan', _ascii(order.customerName)));
    bytes.addAll(g.text(_line()));

    bytes.addAll(_row(g, 'Total nota', formatPlain(order.total)));
    bytes.addAll(_row(g, 'Diterima', formatPlain(payment.amount), bold: true));
    bytes.addAll(_kv(g, 'Metode', payment.method));
    bytes.addAll(_row(g, 'Sisa tagihan', formatPlain(order.remaining)));

    bytes.addAll(g.text(_line()));
    bytes.addAll(g.text('Kasir: ${_ascii(cashierName)}',
        styles: const PosStyles(fontType: PosFontType.fontB)));

    bytes.addAll(_footer(g));
    return bytes;
  }

  Future<List<int>> buildShiftReport(
    Shift shift, {
    required String cashierName,
    required RevenueSummary summary,
    required List<NamedAmount> byMethod,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(_paperSize, profile);
    final bytes = <int>[];

    bytes.addAll(_header(g));
    bytes.addAll(g.text('LAPORAN TUTUP SHIFT',
        styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(g.text(_line()));

    bytes.addAll(_kv(g, 'Kasir', _ascii(cashierName)));
    bytes.addAll(_kv(g, 'Buka', formatDateTime(shift.openedAt)));
    bytes.addAll(_kv(g, 'Tutup',
        shift.closedAt == null ? '-' : formatDateTime(shift.closedAt!)));
    bytes.addAll(g.text(_line()));

    bytes.addAll(_row(g, 'Jumlah order', summary.orderCount.toString()));
    bytes.addAll(_row(g, 'Uang masuk', formatPlain(summary.cashIn)));

    if (summary.refundTotal > 0) {
      bytes.addAll(_row(g, 'Refund', '-${formatPlain(summary.refundTotal)}'));
    }

    bytes.addAll(g.text(_line()));
    for (final method in byMethod) {
      bytes.addAll(_row(g, _ascii(method.name), formatPlain(method.amount)));
    }

    bytes.addAll(g.text(_line()));
    bytes.addAll(_row(g, 'Kas awal', formatPlain(shift.openingCash)));
    bytes.addAll(
        _row(g, 'Kas seharusnya', formatPlain(shift.expectedCash ?? 0)));
    bytes.addAll(_row(g, 'Kas fisik', formatPlain(shift.closingCash ?? 0)));

    final diff = shift.difference ?? 0;
    bytes.addAll(_row(
      g,
      diff == 0 ? 'Selisih' : (diff > 0 ? 'Selisih (lebih)' : 'Selisih (kurang)'),
      formatPlain(diff),
      bold: true,
    ));

    bytes.addAll(_footer(g, withPolicy: false));
    return bytes;
  }

  /// Uji cetak untuk memastikan lebar kertas dan karakter sudah benar (FR-90).
  Future<List<int>> buildTestPage() async {
    final profile = await CapabilityProfile.load();
    final g = Generator(_paperSize, profile);
    final bytes = <int>[];

    bytes.addAll(g.text('UJI CETAK',
        styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(g.text('Lebar kertas: $_paperWidth mm ($_cols karakter)',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(g.text(_line()));
    bytes.addAll(g.text('1234567890' * (_cols ~/ 10)));
    bytes.addAll(g.text(_ruler()));
    bytes.addAll(_row(g, 'Kolom kiri', 'Kanan'));
    bytes.addAll(_row(g, 'Angka panjang', formatPlain(12345678)));
    bytes.addAll(g.text(_line()));
    bytes.addAll(g.text(
      'Jika baris di atas terpotong, ubah lebar kertas di Pengaturan.',
      styles: const PosStyles(fontType: PosFontType.fontB),
    ));
    bytes.addAll(g.feed(2));
    return bytes;
  }

  // --------------------------------------------------------------- bantuan

  List<int> _header(Generator g) {
    final bytes = <int>[];
    final name = _settings.get(SettingsKeys.businessName, fallback: 'LAUNDRY');
    final address = _settings.get(SettingsKeys.businessAddress);
    final phone = _settings.get(SettingsKeys.businessPhone);

    bytes.addAll(g.text(
      _ascii(name).toUpperCase(),
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ));

    if (address.isNotEmpty) {
      bytes.addAll(g.text(_ascii(address),
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (phone.isNotEmpty) {
      bytes.addAll(g.text('Telp: ${_ascii(phone)}',
          styles: const PosStyles(align: PosAlign.center)));
    }

    bytes.addAll(g.text(_line()));
    return bytes;
  }

  List<int> _footer(Generator g, {bool withPolicy = true}) {
    final bytes = <int>[];

    if (withPolicy) {
      final footer = _settings.get(SettingsKeys.receiptFooter);
      if (footer.isNotEmpty) {
        bytes.addAll(g.text(_line()));
        for (final line in footer.split('\n')) {
          bytes.addAll(g.text(
            _ascii(line),
            styles: const PosStyles(
                align: PosAlign.center, fontType: PosFontType.fontB),
          ));
        }
      }

      final hours = _settings.get(SettingsKeys.openHours);
      if (hours.isNotEmpty) {
        bytes.addAll(g.text(_ascii(hours),
            styles: const PosStyles(align: PosAlign.center)));
      }
    }

    bytes.addAll(g.text('Terima kasih',
        styles: const PosStyles(align: PosAlign.center, bold: true)));

    // Banyak printer thermal murah tidak punya pemotong kertas.
    // Feed lebih aman daripada memanggil cut dan membuat printer menggantung.
    bytes.addAll(g.feed(3));
    return bytes;
  }

  List<int> _kv(Generator g, String key, String value) =>
      _row(g, key, value);

  /// Dua kolom kiri dan kanan. Lebar kolom diatur dalam satuan 1/12 baris
  /// sesuai aturan esc_pos_utils.
  List<int> _row(Generator g, String left, String right,
      {bool bold = false}) {
    return g.row([
      PosColumn(
        text: left,
        width: 7,
        styles: PosStyles(bold: bold),
      ),
      PosColumn(
        text: right,
        width: 5,
        styles: PosStyles(align: PosAlign.right, bold: bold),
      ),
    ]);
  }

  String _line() => '-' * _cols;

  String _ruler() {
    final buffer = StringBuffer();
    for (var i = 1; i <= _cols; i++) {
      buffer.write(i % 10 == 0 ? '|' : '.');
    }
    return buffer.toString();
  }

  /// Membuang karakter di luar ASCII yang bisa tercetak jadi sampah.
  String _ascii(String input) => input
      .replaceAll(RegExp(r'[^\x20-\x7E\n]'), '')
      .trim();
}
