import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/core/formatters.dart';
import 'package:laundry_pos/core/security.dart';

void main() {
  group('normalisasi nomor HP', () {
    test('awalan nol menjadi 62', () {
      expect(normalizePhone('081234567890'), '6281234567890');
    });

    test('tanda plus dan spasi dibuang', () {
      expect(normalizePhone('+62 812 3456 7890'), '6281234567890');
    });

    test('tanda hubung dibuang', () {
      expect(normalizePhone('0812-3456-7890'), '6281234567890');
    });

    test('nomor yang sudah benar tidak berubah', () {
      expect(normalizePhone('6281234567890'), '6281234567890');
    });

    test('nomor tanpa awalan diperlakukan sebagai nomor lokal', () {
      expect(normalizePhone('81234567890'), '6281234567890');
    });

    test('nol sesudah +62 dibuang, salah ketik yang sangat umum', () {
      expect(normalizePhone('+62 0812 3456 7890'), '6281234567890');
      expect(normalizePhone('620812-3456-7890'), '6281234567890');
      expect(isValidPhone('+62 0812 3456 7890'), isTrue);
    });

    test('awalan internasional 00 diperlakukan seperti plus', () {
      expect(normalizePhone('0062 812 3456 7890'), '6281234567890');
    });

    test('semua bentuk nomor yang sama menghasilkan nilai identik', () {
      final bentuk = [
        '081234567890',
        '+6281234567890',
        '0812-3456-7890',
        '62 812 3456 7890',
        '+62 0812 3456 7890',
        '0062 812 3456 7890',
      ];

      final hasil = bentuk.map(normalizePhone).toSet();
      expect(hasil.length, 1, reason: 'mencegah pelanggan ganda');
    });
  });

  group('validasi nomor HP', () {
    test('nomor seluler Indonesia diterima', () {
      expect(isValidPhone('081234567890'), isTrue);
      expect(isValidPhone('+6285711112222'), isTrue);
    });

    test('nomor terlalu pendek ditolak', () {
      expect(isValidPhone('0812345'), isFalse);
    });

    test('nomor telepon rumah ditolak', () {
      expect(isValidPhone('0215551234'), isFalse);
    });

    test('teks bukan angka ditolak', () {
      expect(isValidPhone('tidak punya'), isFalse);
    });
  });

  group('PIN', () {
    test('PIN tidak pernah disimpan sebagai teks asli', () {
      final hash = hashPin('1234');
      expect(hash, isNot('1234'));
      expect(hash.length, 64);
    });

    test('PIN yang benar lolos verifikasi', () {
      expect(verifyPin('1234', hashPin('1234')), isTrue);
    });

    test('PIN yang salah ditolak', () {
      expect(verifyPin('9999', hashPin('1234')), isFalse);
    });

    test('hash bersifat tetap untuk PIN yang sama', () {
      expect(hashPin('4321'), hashPin('4321'));
    });
  });

  group('format angka', () {
    test('rupiah tanpa desimal', () {
      expect(formatRupiah(28000), contains('28.000'));
    });

    test('teks berformat dibaca kembali menjadi angka', () {
      expect(parseRupiah('25.000'), 25000);
      expect(parseRupiah('Rp 25.000'), 25000);
      expect(parseRupiah(''), 0);
    });

    test('berat menerima koma maupun titik', () {
      expect(parseQty('3,4'), 3.4);
      expect(parseQty('3.4'), 3.4);
    });

    test('berat bulat ditulis tanpa nol ekor', () {
      expect(formatQty(3.0), '3');
      expect(formatQty(3.5), '3,5');
      expect(formatQty(100.0), '100');
    });

    test('ekor desimal hasil penjumlahan tidak ikut tampil', () {
      // SUM() di laporan menjumlahkan berat 0,1 kg berkali-kali, dan hasilnya
      // bisa 3.5999999999999996. Pemilik tidak boleh melihat angka itu.
      expect(formatQty(0.1 + 0.2), '0,3');
      expect(formatQty(3.5999999999999996), '3,6');
      expect(formatQty(0.1 * 3), '0,3');
    });

    test('tiga angka desimal tetap tampil utuh', () {
      expect(formatQty(0.125), '0,125');
      expect(formatQty(12.25), '12,25');
    });
  });
}
