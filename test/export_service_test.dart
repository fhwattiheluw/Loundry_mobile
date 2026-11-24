import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:laundry_pos/data/repositories/report_repository.dart';
import 'package:laundry_pos/services/export/export_service.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  const exporter = ExportService();
  final from = DateTime(2026, 11, 1);
  final to = DateTime(2026, 11, 30);

  const summary = RevenueSummary(
    orderCount: 3,
    grossOrderValue: 84000,
    discountTotal: 0,
    cashIn: 38000,
    refundTotal: 0,
    newReceivable: 46000,
    paidOrderCount: 1,
    paidOrderValue: 28000,
    unpaidOrderCount: 2,
  );

  const byService = [
    NamedAmount(name: 'Cuci lipat', amount: 84000, count: 3, qty: 12, unit: 'kg'),
  ];
  const byMethod = [NamedAmount(name: 'Tunai', amount: 38000, count: 2)];

  group('nama berkas', () {
    test('satu hari memakai satu tanggal', () {
      final day = DateTime(2026, 11, 24);
      expect(exporter.fileNameFor(day, day, 'pdf'), 'laporan-20261124.pdf');
    });

    test('rentang memakai tanggal awal dan akhir', () {
      expect(exporter.fileNameFor(from, to, 'csv'),
          'laporan-20261101-20261130.csv');
    });
  });

  group('buildCsv', () {
    late ReportFile file;
    late String text;

    setUp(() async {
      file = await exporter.buildCsv(
        from: from,
        to: to,
        businessName: 'Laundry Ambon',
        summary: summary,
        daily: [DailyRevenue(date: DateTime(2026, 11, 3), amount: 38000)],
        byService: byService,
        byMethod: byMethod,
      );
      text = utf8.decode(file.bytes);
    });

    test('berkas berjenis CSV dengan nama sesuai periode', () {
      expect(file.fileName, 'laporan-20261101-20261130.csv');
      expect(file.mimeType, 'text/csv');
    });

    test('diawali BOM supaya Excel membaca huruf dengan benar', () {
      expect(text.codeUnitAt(0), 0xFEFF);
    });

    test('memakai titik koma, pemisah kolom Excel versi Indonesia', () {
      expect(text, contains('Laporan Pendapatan;Laundry Ambon'));
    });

    test('memuat pembagian lunas dan belum lunas', () {
      expect(text, contains('Order lunas;1'));
      expect(text, contains('Order belum lunas;2'));
    });
  });

  group('buildPdf', () {
    test('menghasilkan PDF yang sah', () async {
      final file = await exporter.buildPdf(
        from: from,
        to: to,
        businessName: 'Laundry Ambon',
        businessAddress: 'Jl. Pattimura, Ambon',
        summary: summary,
        byService: byService,
        byMethod: byMethod,
      );

      expect(file.fileName, 'laporan-20261101-20261130.pdf');
      expect(file.mimeType, 'application/pdf');
      expect(ascii.decode(file.bytes.sublist(0, 5)), '%PDF-');
      expect(file.sizeLabel, endsWith('KB'));
    });

    test('laporan kosong tetap bisa dibuat', () async {
      final file = await exporter.buildPdf(
        from: from,
        to: to,
        businessName: '',
        businessAddress: '',
        summary: RevenueSummary.empty,
        byService: const [],
        byMethod: const [],
      );

      expect(ascii.decode(file.bytes.sublist(0, 5)), '%PDF-');
    });
  });
}
