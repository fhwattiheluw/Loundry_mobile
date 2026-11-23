import '../../core/formatters.dart';
import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';

/// Mengisi variabel template WhatsApp yang diedit pemilik di Pengaturan.
///
/// Variabel yang dikenali:
/// {nama} {no_order} {layanan} {rincian} {ringkasan} {subtotal} {diskon}
/// {biaya_lain} {total} {dibayar} {sisa} {status_bayar} {rak} {parfum}
/// {catatan} {estimasi} {tanggal} {nama_usaha} {jam_buka}
class MessageTemplate {
  const MessageTemplate(this._settings);

  final SettingsRepository _settings;

  /// Semua variabel yang dikenali [render]. Layar template memakai daftar
  /// yang sama untuk tombol sisip dan untuk memeriksa salah ketik, jadi
  /// menambah variabel cukup di sini dan di [render].
  static const variables = [
    '{nama}',
    '{no_order}',
    '{layanan}',
    '{rincian}',
    '{ringkasan}',
    '{subtotal}',
    '{diskon}',
    '{biaya_lain}',
    '{total}',
    '{dibayar}',
    '{sisa}',
    '{status_bayar}',
    '{rak}',
    '{parfum}',
    '{catatan}',
    '{estimasi}',
    '{tanggal}',
    '{nama_usaha}',
    '{jam_buka}',
  ];

  /// Isian berkurung kurawal di [template] yang BUKAN variabel. Dibiarkan,
  /// ia terkirim ke pelanggan apa adanya ("Halo {nama_pelanggan}"), jadi
  /// layar template menolak simpan selama daftar ini tidak kosong.
  static List<String> unknownVariables(String template) {
    final found = RegExp(r'\{[^{}\n]*\}')
        .allMatches(template)
        .map((m) => m[0]!)
        .where((v) => !variables.contains(v));
    return found.toSet().toList();
  }

  /// Order rekaan untuk pratinjau template, supaya pemilik melihat pesan
  /// seperti yang diterima pelanggan tanpa harus membuat order sungguhan.
  static LaundryOrder sampleOrder() {
    final now = DateTime.now();
    return LaundryOrder(
      orderNo: 'LD-CONTOH-0001',
      customerId: 0,
      createdBy: 0,
      createdAt: now,
      estimatedAt: now.add(const Duration(days: 2)),
      laundryStatus: LaundryStatus.diproses,
      paymentStatus: PaymentStatus.dp,
      subtotal: 74500,
      discount: 0,
      total: 74500,
      paid: 30000,
      rack: 'A3',
      perfume: 'Lavender',
      customerName: 'Budi',
      customerPhone: '6281234567890',
      items: const [
        OrderItem(
          serviceId: 0,
          serviceName: 'Cuci Kiloan',
          unit: ServiceUnit.kg,
          qty: 3.5,
          unitPrice: 7000,
          subtotal: 24500,
          itemDetails: '3 kemeja, 2 celana',
        ),
        OrderItem(
          serviceId: 0,
          serviceName: 'Sepatu',
          unit: ServiceUnit.pcs,
          qty: 2,
          unitPrice: 25000,
          subtotal: 50000,
        ),
      ],
    );
  }

  String forTrigger(NotificationTrigger trigger, LaundryOrder order) {
    final template = switch (trigger) {
      NotificationTrigger.orderDiterima =>
        _settings.get(SettingsKeys.templateOrderCreated),
      NotificationTrigger.cucianSelesai =>
        _settings.get(SettingsKeys.templateOrderDone),
      NotificationTrigger.pengingatAmbil =>
        _settings.get(SettingsKeys.templateReminder),
      NotificationTrigger.pembayaranDiterima =>
        _settings.get(SettingsKeys.templatePayment),
    };

    return render(template, order);
  }

  String render(String template, LaundryOrder order) {
    final services = order.items.map((i) => i.serviceName).join(', ');
    final rack = order.rack;
    final perfume = order.perfume;
    final note = order.note;

    final values = <String, String>{
      '{nama}': order.customerName,
      '{no_order}': order.orderNo,
      '{layanan}': services.isEmpty ? '-' : services,
      '{rincian}': itemLines(order),
      '{ringkasan}': summaryLines(order),
      '{subtotal}': formatRupiah(order.subtotal),
      '{diskon}': order.discount > 0 ? formatRupiah(order.discount) : '-',
      '{biaya_lain}': order.extraFee > 0 ? formatRupiah(order.extraFee) : '-',
      '{total}': formatRupiah(order.total),
      '{dibayar}': formatRupiah(order.paid),
      '{sisa}': order.remaining > 0 ? formatRupiah(order.remaining) : 'LUNAS',
      '{status_bayar}': order.paymentStatus.label,
      '{rak}': rack == null || rack.isEmpty ? '-' : rack,
      '{parfum}': perfume == null || perfume.isEmpty ? '-' : perfume,
      '{catatan}': note == null || note.isEmpty ? '-' : note,
      '{estimasi}': formatDateTime(order.estimatedAt),
      '{tanggal}': formatDate(order.createdAt),
      '{nama_usaha}': _settings.get(SettingsKeys.businessName),
      '{jam_buka}': _settings.get(SettingsKeys.openHours),
    };

    // Satu kali lewat, bukan replaceAll berantai: nama pelanggan atau
    // catatan yang kebetulan berisi "{total}" tidak boleh ikut diganti.
    final filled = template.replaceAllMapped(
      RegExp(r'\{[a-z_]+\}'),
      (m) => values[m[0]!] ?? m[0]!,
    );

    // Variabel yang kosong (misalnya jam buka) meninggalkan baris kosong
    // berlapis. WhatsApp menampilkannya apa adanya.
    return filled.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// Daftar item bernomor: nama layanan, jumlah dengan satuannya, harga
  /// per satuan, dan subtotal tiap item.
  ///
  /// ```
  /// 1. Cuci Kiloan (Express)
  ///    3,5 kg × Rp 7.000 = Rp 24.500
  ///    Isi: 3 kemeja, 2 celana
  /// ```
  static String itemLines(LaundryOrder order) {
    if (order.items.isEmpty) return '-';

    final out = StringBuffer();
    for (var i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      if (i > 0) out.writeln();

      out.writeln('${i + 1}. ${item.serviceName}'
          '${item.express ? ' (Express)' : ''}');
      out.writeln('   ${formatQty(item.qty)} ${item.unit.label}'
          ' × ${formatRupiah(item.unitPrice)}'
          ' = ${formatRupiah(item.subtotal)}');

      final details = item.itemDetails;
      if (details != null && details.isNotEmpty) {
        out.writeln('   Isi: $details');
      }
      final note = item.note;
      if (note != null && note.isNotEmpty) {
        out.writeln('   Catatan: $note');
      }
    }
    return out.toString().trimRight();
  }

  /// Blok angka di akhir pesan: subtotal, diskon, biaya lain, total,
  /// sudah dibayar, dan sisa. Baris diskon dan biaya lain hanya muncul
  /// bila ada nilainya.
  static String summaryLines(LaundryOrder order) {
    final extraLabel = order.extraFeeNote?.isNotEmpty == true
        ? order.extraFeeNote!
        : 'Biaya tambahan';

    final lines = <String>[
      'Subtotal: ${formatRupiah(order.subtotal)}',
      if (order.discount > 0) 'Diskon: - ${formatRupiah(order.discount)}',
      if (order.extraFee > 0) '$extraLabel: ${formatRupiah(order.extraFee)}',
      '*Total: ${formatRupiah(order.total)}*',
      'Sudah dibayar: ${formatRupiah(order.paid)}',
      order.remaining > 0
          ? '*Sisa tagihan: ${formatRupiah(order.remaining)}*'
          : '*Sisa tagihan: LUNAS*',
    ];
    return lines.join('\n');
  }

  /// Apakah pemicu ini diaktifkan pemilik.
  bool isEnabled(NotificationTrigger trigger) => switch (trigger) {
        NotificationTrigger.orderDiterima =>
          _settings.getBool(SettingsKeys.notifyOrderCreated, fallback: true),
        NotificationTrigger.cucianSelesai =>
          _settings.getBool(SettingsKeys.notifyOrderDone, fallback: true),
        NotificationTrigger.pengingatAmbil =>
          _settings.getBool(SettingsKeys.notifyReminder, fallback: true),
        NotificationTrigger.pembayaranDiterima =>
          _settings.getBool(SettingsKeys.notifyPaymentReceived),
      };
}
