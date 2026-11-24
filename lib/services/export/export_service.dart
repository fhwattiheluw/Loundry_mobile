import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../data/repositories/report_repository.dart';

/// Laporan yang sudah jadi tapi belum dikirim ke mana pun.
///
/// Membuat dan mengirim sengaja dipisah. Dulu keduanya satu langkah dan
/// satu-satunya jalan keluar adalah lembar Bagikan; bila pemilik menutup
/// lembar itu, berkasnya tertinggal di folder sementara yang tidak bisa
/// dibuka. Sekarang layar yang memutuskan: simpan ke HP atau bagikan.
class ReportFile {
  const ReportFile({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;

  /// "12,4 KB" untuk ditampilkan sebelum pemilik memilih.
  String get sizeLabel {
    final kb = bytes.length / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1).replaceAll('.', ',')} KB';
    return '${(kb / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
}

/// Laporan yang bisa dibawa keluar aplikasi: CSV untuk diolah di Excel,
/// PDF untuk dicetak atau dikirim ke pihak lain.
class ExportService {
  const ExportService();

  /// Nama berkas laporan, misalnya laporan-20261124.pdf atau
  /// laporan-20261101-20261130.csv untuk satu bulan.
  String fileNameFor(DateTime from, DateTime to, String extension) =>
      'laporan-${_stamp(from, to)}.$extension';

  /// Menyimpan ke HP lewat dialog "Simpan sebagai" bawaan Android. Pemilik
  /// memilih foldernya sendiri, biasanya Download. Tidak butuh izin
  /// penyimpanan karena Android yang menulis ke folder pilihan itu.
  ///
  /// Mengembalikan false bila pemilik membatalkan dialog.
  Future<bool> saveToDevice(ReportFile file) async {
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: 'Simpan laporan',
      fileName: file.fileName,
      bytes: file.bytes,
    );
    return saved != null;
  }

  /// Membuka lembar Bagikan (WhatsApp, email, Drive, dan lainnya).
  Future<void> share(ReportFile file, {required String subject}) async {
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, file.fileName);
    await File(path).writeAsBytes(file.bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: file.mimeType)],
        subject: subject,
      ),
    );
  }

  String _stamp(DateTime from, DateTime to) {
    String d(DateTime x) =>
        '${x.year}${x.month.toString().padLeft(2, '0')}${x.day.toString().padLeft(2, '0')}';
    return d(from) == d(to) ? d(from) : '${d(from)}-${d(to)}';
  }

  // -------------------------------------------------------------------- CSV

  Future<ReportFile> buildCsv({
    required DateTime from,
    required DateTime to,
    required String businessName,
    required RevenueSummary summary,
    required List<DailyRevenue> daily,
    required List<NamedAmount> byService,
    required List<NamedAmount> byMethod,
  }) async {
    final rows = <List<Object?>>[
      ['Laporan Pendapatan', businessName],
      ['Periode', '${formatDate(from)} sampai ${formatDate(to)}'],
      ['Dibuat', formatDateTime(DateTime.now())],
      [],
      ['RINGKASAN'],
      ['Pendapatan (uang diterima)', summary.cashIn],
      ['Jumlah order', summary.orderCount],
      ['Nilai order', summary.grossOrderValue],
      ['Diskon diberikan', summary.discountTotal],
      ['Refund', summary.refundTotal],
      ['Piutang dari periode ini', summary.newReceivable],
      ['Order lunas', summary.paidOrderCount],
      ['Order belum lunas', summary.unpaidOrderCount],
      ['Rata-rata nilai nota', summary.averageOrderValue],
      [],
      ['PENDAPATAN HARIAN'],
      ['Tanggal', 'Uang diterima'],
      ...daily.map((d) => [formatDate(d.date), d.amount]),
      [],
      // Nilai per layanan adalah jumlah harga baris order sebelum diskon,
      // BUKAN uang yang diterima, jadi totalnya tidak sama dengan
      // "Pendapatan" di atas. Kuantitas ditulis dengan koma desimal supaya
      // Excel versi Indonesia membacanya sebagai angka, bukan teks.
      ['NILAI ORDER PER LAYANAN (sebelum diskon, bukan uang diterima)'],
      ['Layanan', 'Jumlah order', 'Kuantitas', 'Nilai order'],
      ...byService.map((s) => [s.name, s.count, formatQty(s.qty), s.amount]),
      [],
      ['PER METODE BAYAR'],
      ['Metode', 'Jumlah transaksi', 'Nilai'],
      ...byMethod.map((m) => [m.name, m.count, m.amount]),
    ];

    // Excel versi Indonesia memakai titik koma sebagai pemisah kolom.
    // Dengan koma, seluruh baris akan masuk ke satu sel.
    final csv = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);

    // BOM supaya Excel membaca huruf beraksen dengan benar.
    return ReportFile(
      fileName: fileNameFor(from, to, 'csv'),
      bytes: Uint8List.fromList(utf8.encode('\uFEFF$csv')),
      mimeType: 'text/csv',
    );
  }

  // -------------------------------------------------------------------- PDF

  Future<ReportFile> buildPdf({
    required DateTime from,
    required DateTime to,
    required String businessName,
    required String businessAddress,
    required RevenueSummary summary,
    required List<NamedAmount> byService,
    required List<NamedAmount> byMethod,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _pdfHeader(businessName, businessAddress, from, to),
          pw.SizedBox(height: 20),
          _pdfSummary(summary),
          pw.SizedBox(height: 20),
          if (byService.isNotEmpty) ...[
            _pdfSectionTitle('Nilai order per layanan'),
            _pdfTable(
              ['Layanan', 'Order', 'Kuantitas', 'Nilai order'],
              byService
                  .map((s) => [
                        s.name,
                        '${s.count}',
                        formatQty(s.qty),
                        formatRupiah(s.amount),
                      ])
                  .toList(),
            ),
            pw.SizedBox(height: 20),
          ],
          if (byMethod.isNotEmpty) ...[
            _pdfSectionTitle('Per metode bayar'),
            _pdfTable(
              ['Metode', 'Transaksi', 'Nilai'],
              byMethod
                  .map((m) => [m.name, '${m.count}', formatRupiah(m.amount)])
                  .toList(),
            ),
          ],
          pw.SizedBox(height: 28),
          pw.Text(
            'Pendapatan dihitung dari pembayaran yang benar-benar diterima '
            'pada periode ini, bukan dari nilai order. Order dengan DP di '
            'satu periode dan pelunasan di periode lain terbagi ke dua '
            'periode tersebut. Nilai order per layanan adalah harga baris '
            'order sebelum diskon, sehingga jumlahnya tidak harus sama '
            'dengan pendapatan.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Halaman ${context.pageNumber} dari ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );

    return ReportFile(
      fileName: fileNameFor(from, to, 'pdf'),
      bytes: await doc.save(),
      mimeType: 'application/pdf',
    );
  }

  pw.Widget _pdfHeader(
    String name,
    String address,
    DateTime from,
    DateTime to,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          name.isEmpty ? 'Laporan Pendapatan' : name,
          style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        if (address.isNotEmpty)
          pw.Text(address, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 10),
        pw.Text(
          'Laporan Pendapatan',
          style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Periode ${formatDate(from)} sampai ${formatDate(to)}',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.Text(
          'Dibuat ${formatDateTime(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.Divider(),
      ],
    );
  }

  pw.Widget _pdfSummary(RevenueSummary s) {
    pw.Widget row(String label, String value, {bool bold = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                  fontSize: bold ? 12 : 10,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                )),
            pw.Text(value,
                style: pw.TextStyle(
                  fontSize: bold ? 12 : 10,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                )),
          ],
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          row('Pendapatan (uang diterima)', formatRupiah(s.cashIn), bold: true),
          pw.Divider(color: PdfColors.grey300),
          row('Jumlah order', '${s.orderCount}'),
          row('Nilai order periode ini', formatRupiah(s.grossOrderValue)),
          row('Rata-rata nilai nota', formatRupiah(s.averageOrderValue)),
          row('Diskon diberikan', formatRupiah(s.discountTotal)),
          row('Refund', formatRupiah(s.refundTotal)),
          row('Piutang dari periode ini', formatRupiah(s.newReceivable)),
          row('Order lunas', '${s.paidOrderCount}'),
          row('Order belum lunas', '${s.unpaidOrderCount}'),
        ],
      ),
    );
  }

  pw.Widget _pdfSectionTitle(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(
          text,
          style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      );

  pw.Widget _pdfTable(List<String> headers, List<List<String>> rows) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerStyle: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        for (var i = 1; i < headers.length; i++) i: pw.Alignment.centerRight,
      },
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    );
  }
}
