import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/services/setup/setup_checklist.dart';

SetupChecklist build({
  String name = SetupChecklist.defaultBusinessName,
  String printer = '',
  bool backedUp = false,
  bool hidden = false,
}) =>
    SetupChecklist.evaluate(
      businessName: name,
      printerName: printer,
      backedUp: backedUp,
      hidden: hidden,
    );

void main() {
  group('SetupChecklist', () {
    test('pemasangan baru: tidak ada langkah selesai dan kartu tampil', () {
      final c = build();
      expect(c.doneCount, 0);
      expect(c.total, 3);
      expect(c.visible, isTrue);
    });

    test('nama bawaan belum dihitung selesai, nama sendiri dihitung', () {
      expect(build().items.first.done, isFalse);
      expect(build(name: '  ').items.first.done, isFalse);
      expect(build(name: 'Laundry Bu Sari').items.first.done, isTrue);
    });

    test('printer dan backup menandai langkahnya masing-masing', () {
      final c = build(printer: 'RPP02N', backedUp: true);
      final byStep = {for (final i in c.items) i.step: i.done};
      expect(byStep[SetupStep.printer], isTrue);
      expect(byStep[SetupStep.backup], isTrue);
      expect(byStep[SetupStep.business], isFalse);
    });

    test('semua selesai: kartu hilang sendiri', () {
      final c = build(name: 'Laundry Bu Sari', printer: 'RPP02N', backedUp: true);
      expect(c.complete, isTrue);
      expect(c.visible, isFalse);
    });

    test('disembunyikan pemilik: kartu tidak tampil walau belum selesai', () {
      final c = build(hidden: true);
      expect(c.complete, isFalse);
      expect(c.visible, isFalse);
    });
  });
}
