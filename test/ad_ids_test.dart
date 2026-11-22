import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_pos/services/ads/ad_service.dart';

void main() {
  // `flutter test` berjalan dalam mode debug. Di mode debug, ID produksi
  // TIDAK BOLEH dipakai: klik pengujian sendiri menutup akun AdMob.
  test('mode debug selalu memakai ID uji Google', () {
    for (final id in [
      AdIds.banner,
      AdIds.native,
      AdIds.interstitial,
      AdIds.appOpen,
      AdIds.rewarded,
    ]) {
      expect(id, startsWith('ca-app-pub-3940256099942544/'));
    }

    expect(AdIds.allTest, isTrue);
    expect(AdIds.allProduction, isFalse);
  });

  test('laporan unit memuat kelima jenis iklan', () {
    expect(
      AdIds.realByFormat.keys,
      containsAll(['Banner', 'Native', 'Interstitial', 'App open', 'Rewarded']),
    );
  });
}
