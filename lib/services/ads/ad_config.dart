/// ID unit iklan PRODUKSI, diisi sekali setelah unit dibuat di AdMob.
///
/// Cara mengisi: AdMob -> Aplikasi -> Unit iklan. Salin ID yang berbentuk
/// `ca-app-pub-1234567890123456/1234567890` ke baris yang sesuai di bawah.
///
/// ID iklan BUKAN rahasia: ia memang terkirim ke semua perangkat. Berbeda
/// dengan kunci penandatangan, ID ini aman ditaruh di repositori.
///
/// Selama kosong, build rilis memakai ID UJI Google. Iklan uji tampil
/// normal tetapi TIDAK menghasilkan uang, dan layar Pengaturan -> Status
/// iklan memberi tahu bila itu yang sedang terjadi.
///
/// Bagian ini juga bisa ditimpa saat build dengan --dart-define, misalnya
/// `--dart-define=ADMOB_BANNER_ID=ca-app-pub-xxx/111`. Nilai --dart-define
/// menang atas nilai di berkas ini.
abstract final class AdConfig {
  static const banner = '';
  static const interstitial = '';
  static const rewarded = '';
  static const appOpen = '';
  static const native = '';
}
