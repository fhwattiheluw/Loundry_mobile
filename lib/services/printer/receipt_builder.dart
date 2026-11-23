import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

import '../../core/formatters.dart';
import '../../core/security.dart';
import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/report_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/payment_banner.dart';

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

    bytes.addAll(await _logo(g));
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
    // Dicetak tebal: nota ini yang dipegang pelanggan saat mengambil, dan
    // raknya yang dicari petugas.
    if (order.rack != null && order.rack!.isNotEmpty) {
      bytes.addAll(g.text(
        'RAK: ${_ascii(order.rack!)}',
        styles: const PosStyles(bold: true),
      ));
    }
    bytes.addAll(g.text(_line()));

    for (final item in order.items) {
      bytes.addAll(g.text(_ascii(item.serviceName),
          styles: const PosStyles(bold: true)));

      final qtyLabel =
          '${formatQty(item.qty)} ${item.unit.label} x ${formatPlain(item.unitPrice)}';
      bytes.addAll(_row(g, qtyLabel, formatPlain(item.subtotal)));

      // Rincian isi cucian dicetak di nota, bukan hanya disimpan, karena
      // inilah bukti yang dipegang kedua pihak saat ada klaim (FR-32).
      if (item.itemDetails != null && item.itemDetails!.trim().isNotEmpty) {
        bytes.addAll(g.text('  Isi: ${_ascii(item.itemDetails!)}',
            styles: const PosStyles(fontType: PosFontType.fontB)));
      }

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

    if (order.extraFee > 0) {
      final label = order.extraFeeNote?.trim().isNotEmpty == true
          ? _ascii(order.extraFeeNote!)
          : _settings.get(SettingsKeys.extraFeeLabel, fallback: 'Biaya lain');
      bytes.addAll(_row(g, label, formatPlain(order.extraFee)));
    }

    bytes.addAll(_row(g, 'TOTAL', formatPlain(order.total), bold: true));
    bytes.addAll(_row(g, 'Dibayar', formatPlain(order.paid)));

    if (order.remaining > 0) {
      bytes.addAll(
          _row(g, 'SISA TAGIHAN', formatPlain(order.remaining), bold: true));
    }

    bytes.addAll(_paymentStamp(g, order));

    if (order.perfume != null && order.perfume!.trim().isNotEmpty) {
      bytes.addAll(g.text(_line()));
      bytes.addAll(_kv(g, 'Parfum', _ascii(order.perfume!)));
    }

    if (order.note != null && order.note!.trim().isNotEmpty) {
      bytes.addAll(g.text(_line()));
      bytes.addAll(g.text('Catatan: ${_ascii(order.note!)}'));
    }

    bytes.addAll(g.text(_line()));
    bytes.addAll(g.text('Kasir: ${_ascii(cashierName)}',
        styles: const PosStyles(fontType: PosFontType.fontB)));

    // QR berisi nomor nota, untuk dipindai saat pengambilan (FR-89).
    // Tidak semua printer murah mendukung perintah QR, jadi kegagalannya
    // tidak boleh membatalkan sisa nota yang sudah tersusun.
    if (_settings.getBool(SettingsKeys.receiptQrEnabled)) {
      try {
        bytes.addAll(g.feed(1));
        bytes.addAll(g.qrcode(order.orderNo, size: QRSize.size4));
        bytes.addAll(g.text(order.orderNo,
            styles: const PosStyles(
                align: PosAlign.center, fontType: PosFontType.fontB)));
      } catch (_) {
        bytes.addAll(g.text(order.orderNo,
            styles: const PosStyles(align: PosAlign.center)));
      }
    }

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

    bytes.addAll(await _logo(g));
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
    bytes.addAll(_paymentStamp(g, order));

    bytes.addAll(g.text(_line()));
    bytes.addAll(g.text('Kasir: ${_ascii(cashierName)}',
        styles: const PosStyles(fontType: PosFontType.fontB)));

    bytes.addAll(_footer(g));
    return bytes;
  }

  Future<List<int>> buildShiftReport(
    Shift shift, {
    required String cashierName,
    required ShiftTotals totals,
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

    bytes.addAll(_row(g, 'Jumlah order', totals.orderCount.toString()));
    bytes.addAll(
        _row(g, 'Jumlah pembayaran', totals.paymentCount.toString()));
    bytes.addAll(_row(g, 'Uang masuk', formatPlain(totals.cashIn)));

    if (totals.refundTotal > 0) {
      bytes.addAll(_row(g, 'Refund', '-${formatPlain(totals.refundTotal)}'));
    }

    bytes.addAll(g.text(_line()));
    for (final entry in totals.byMethod.entries) {
      bytes.addAll(_row(g, _ascii(entry.key), formatPlain(entry.value)));
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

  /// Laporan pendapatan untuk satu rentang tanggal, dicetak di printer
  /// struk 58 atau 80 mm.
  ///
  /// Pemilik laundry yang menutup toko malam hari lebih sering memegang
  /// kertas daripada membuka PDF. Isinya sengaja sama persis dengan yang
  /// ada di layar Laporan, supaya tidak ada dua versi kebenaran.
  Future<List<int>> buildRevenueReport({
    required String rangeLabel,
    required DateTime from,
    required DateTime to,
    required RevenueSummary summary,
    List<NamedAmount> byService = const [],
    List<NamedAmount> byMethod = const [],
    String? printedBy,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(_paperSize, profile);
    final bytes = <int>[];

    bytes.addAll(_header(g));
    bytes.addAll(g.text('LAPORAN PENDAPATAN',
        styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(g.text(
      _ascii(rangeLabel),
      styles: const PosStyles(align: PosAlign.center),
    ));
    bytes.addAll(g.text(
      '${formatDate(from)} - ${formatDate(to)}',
      styles: const PosStyles(
          align: PosAlign.center, fontType: PosFontType.fontB),
    ));
    bytes.addAll(g.text(_line()));

    bytes.addAll(_row(g, 'Jumlah order', summary.orderCount.toString()));
    bytes.addAll(
        _row(g, 'Nilai transaksi', formatPlain(summary.grossOrderValue)));

    if (summary.discountTotal > 0) {
      bytes.addAll(
          _row(g, 'Diskon diberikan', formatPlain(summary.discountTotal)));
    }
    if (summary.refundTotal > 0) {
      bytes.addAll(_row(g, 'Refund', '-${formatPlain(summary.refundTotal)}'));
    }

    bytes.addAll(g.text(_line()));
    // Pendapatan dicetak tebal karena inilah satu-satunya angka yang berarti
    // uang sungguhan. Nilai transaksi di atasnya termasuk yang belum dibayar.
    bytes.addAll(
        _row(g, 'PENDAPATAN', formatPlain(summary.cashIn), bold: true));
    bytes.addAll(_row(g, 'Piutang baru', formatPlain(summary.newReceivable)));

    if (byMethod.isNotEmpty) {
      bytes.addAll(g.text(_line()));
      bytes.addAll(g.text('Per metode bayar',
          styles: const PosStyles(fontType: PosFontType.fontB)));
      for (final item in byMethod) {
        bytes.addAll(_row(g, _ascii(item.name), formatPlain(item.amount)));
      }
    }

    if (byService.isNotEmpty) {
      bytes.addAll(g.text(_line()));
      bytes.addAll(g.text('Per layanan',
          styles: const PosStyles(fontType: PosFontType.fontB)));
      for (final item in byService) {
        bytes.addAll(_row(g, _ascii(item.name), formatPlain(item.amount)));
      }
    }

    bytes.addAll(g.text(_line()));
    bytes.addAll(g.text('Dicetak ${formatDateTime(DateTime.now())}',
        styles: const PosStyles(fontType: PosFontType.fontB)));
    if (printedBy != null && printedBy.isNotEmpty) {
      bytes.addAll(g.text('Oleh: ${_ascii(printedBy)}',
          styles: const PosStyles(fontType: PosFontType.fontB)));
    }

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

  /// Logo usaha di kepala nota (FR-88).
  ///
  /// Printer thermal hanya bisa mencetak hitam putih, jadi logo diubah ke
  /// hitam putih dan dikecilkan agar muat selebar kertas. Logo yang terlalu
  /// besar membuat sebagian printer menggantung, dan kegagalannya tidak
  /// boleh membatalkan nota, jadi seluruhnya dibungkus try.
  Future<List<int>> _logo(Generator g) async {
    final path = _settings.get(SettingsKeys.receiptLogoPath);
    if (path.isEmpty) return const [];

    try {
      final file = File(path);
      if (!await file.exists()) return const [];

      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded == null) return const [];

      final maxWidth = _paperWidth == 80 ? 400 : 300;
      final resized = img.copyResize(
        decoded,
        width: decoded.width > maxWidth ? maxWidth : decoded.width,
      );

      return g.image(img.grayscale(resized));
    } catch (_) {
      return const [];
    }
  }

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
  /// Status bayar yang tidak mungkin terlewat. LUNAS dicetak dobel ukuran
  /// dan dibingkai garis, karena nota ini yang ditunjukkan pelanggan saat
  /// mengambil cucian. Order yang masih punya tagihan dicetak BELUM LUNAS
  /// supaya tidak ada yang mengira sudah beres.
  List<int> _paymentStamp(Generator g, LaundryOrder order) {
    final banner = paymentBannerOf(order);
    final bytes = <int>[];

    switch (banner) {
      case PaymentBanner.lunas:
        bytes.addAll(g.text(_line()));
        bytes.addAll(g.text(
          banner.text,
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ));
        bytes.addAll(g.text(_line()));
      case PaymentBanner.belumLunas:
        bytes.addAll(g.text(_line()));
        bytes.addAll(g.text(
          banner.text,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ));
      case PaymentBanner.dibatalkan:
        bytes.addAll(g.text(_line()));
        bytes.addAll(g.text(
          banner.text,
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ));
    }

    return bytes;
  }

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
