import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/core/app_identity.dart';

void main() {
  group('receiptLines', () {
    test('muat di kertas 58 mm tanpa melipat', () {
      final lines = AppIdentity.receiptLines(cols: 32);
      final limit = AppIdentity.smallFontCols(32);

      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(limit), reason: line);
      }
    });

    test('muat di kertas 80 mm tanpa melipat', () {
      final lines = AppIdentity.receiptLines(cols: 48);
      final limit = AppIdentity.smallFontCols(48);

      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(limit), reason: line);
      }
    });

    test('hanya huruf ASCII, karena printer murah mengacak sisanya', () {
      for (final line in AppIdentity.receiptLines(cols: 32)) {
        expect(RegExp(r'^[\x20-\x7E]+$').hasMatch(line), isTrue, reason: line);
      }
    });

    test('menyebut nama aplikasi', () {
      expect(
        AppIdentity.receiptLines(cols: 32).join(' '),
        contains(AppIdentity.name),
      );
    });
  });

  group('shareMessage', () {
    test('memuat tautan Play Store', () {
      expect(AppIdentity.shareMessage(), contains(AppIdentity.playStoreUrl));
      expect(AppIdentity.playStoreUrl, contains(AppIdentity.packageId));
    });

    test('menyebut nama toko bila ada', () {
      final text = AppIdentity.shareMessage(businessName: 'Laundry Ambon');
      expect(text, contains('Laundry Ambon'));
    });

    test('nama toko kosong tidak meninggalkan kalimat menggantung', () {
      final text = AppIdentity.shareMessage(businessName: '   ');
      expect(text, startsWith('Saya pakai ${AppIdentity.name}'));
    });
  });

  test('baris WhatsApp memuat nama dan tautan', () {
    expect(AppIdentity.whatsappLine, contains(AppIdentity.name));
    expect(AppIdentity.whatsappLine, contains(AppIdentity.playStoreUrl));
  });
}
