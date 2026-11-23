import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/core/friendly_error.dart';

void main() {
  group('friendlyError', () {
    test('StateError tampil tanpa awalan Bad state', () {
      final text = friendlyError(StateError('Order sudah dibatalkan.'));
      expect(text, 'Order sudah dibatalkan.');
    });

    test('galat jaringan menyuruh periksa koneksi', () {
      expect(friendlyError(const SocketException('Failed host lookup')),
          contains('koneksi internet'));
    });

    test('timeout dijelaskan sebagai terlalu lama menunggu', () {
      expect(friendlyError(TimeoutException('x')), contains('Terlalu lama'));
    });

    test('pelanggaran UNIQUE dijelaskan sebagai data kembar', () {
      final text = friendlyError(Exception(
          'DatabaseException(UNIQUE constraint failed: customers.phone)'));
      expect(text, contains('sudah ada'));
      expect(text, isNot(contains('constraint')));
    });

    test('galat database umum menyuruh buka ulang aplikasi', () {
      expect(friendlyError(Exception('SqliteException(5): database is locked')),
          contains('Tutup aplikasi'));
    });

    test('FormatException tidak membocorkan teks teknis', () {
      final text = friendlyError(const FormatException('Invalid number'));
      expect(text, isNot(contains('Invalid number')));
      expect(text, contains('format'));
    });

    test('penyimpanan penuh dikenali', () {
      final error = FileSystemException(
          'write failed', '/x', const OSError('No space left on device', 28));
      expect(friendlyError(error), contains('penuh'));
    });

    test('galat tak dikenal tetap memberi langkah berikutnya', () {
      final text = friendlyError(Exception('xyz'));
      expect(text, contains('Coba lagi'));
      expect(text, isNot(contains('xyz')));
    });
  });
}
