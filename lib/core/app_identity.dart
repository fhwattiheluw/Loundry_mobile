/// Identitas aplikasi untuk dipakai di nota, pesan WhatsApp, dan tombol
/// bagikan. Dikumpulkan di satu tempat supaya nama dan tautannya tidak
/// ditulis ulang berbeda-beda di banyak berkas.
abstract final class AppIdentity {
  static const name = 'Laundry Manise';
  static const tagline = 'Aplikasi kasir laundry gratis';
  static const packageId = 'com.manise.laundry';

  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=$packageId';

  /// Baris promosi untuk pesan WhatsApp. Berbeda dari nota: di sini
  /// tautannya bisa diketuk, jadi alamat lengkap lebih berguna daripada
  /// ajakan mencari di Play Store.
  static const whatsappLine =
      'Nota ini dibuat dengan $name, $tagline: $playStoreUrl';

  /// Lebar baris untuk font kecil (fontB) pada printer thermal. Font kecil
  /// memuat kira-kira sepertiga lebih banyak karakter daripada font biasa.
  static int smallFontCols(int cols) => cols * 4 ~/ 3;

  /// Dua baris kecil di kaki nota. Panjangnya dijaga agar muat di kertas
  /// 58 mm maupun 80 mm tanpa terpotong atau melipat ke baris berikutnya,
  /// karena baris yang melipat membuat nota toko terlihat berantakan.
  static List<String> receiptLines({required int cols}) {
    final wide = cols >= 48;

    return [
      'Dicatat dengan $name',
      wide ? '$tagline, cari di Play Store' : 'Kasir laundry gratis-Play Store',
    ];
  }

  /// Teks yang dibagikan pemilik ke sesama pelaku usaha. Ditulis sebagai
  /// pengalaman pemakai, bukan iklan, karena yang membacanya adalah teman
  /// sendiri di grup WhatsApp.
  static String shareMessage({String businessName = ''}) {
    final shop = businessName.trim();
    final opening = shop.isEmpty
        ? 'Saya pakai $name untuk mencatat order laundry.'
        : 'Di $shop saya pakai $name untuk mencatat order laundry.';

    return '$opening\n\n'
        'Bikin nota, cetak struk, kirim info ke pelanggan lewat WhatsApp, '
        'dan lihat laporan harian. Gratis, tanpa biaya bulanan.\n\n'
        'Unduh: $playStoreUrl';
  }
}
