# POS Laundry

Aplikasi kasir Android untuk UMKM laundry. Cetak nota lewat printer thermal
Bluetooth, kirim notifikasi WhatsApp, dan lihat laporan pendapatan yang
dihitung dari uang yang benar-benar diterima.

Dibangun dengan Flutter. Database SQLite tersimpan di perangkat, tanpa server.

---

## Daftar isi

- [Fitur](#fitur)
- [Menjalankan pertama kali](#menjalankan-pertama-kali)
- [Struktur kode](#struktur-kode)
- [Pengujian](#pengujian)
- [Konfigurasi AdMob](#konfigurasi-admob)
- [Deploy ke Google Play](#deploy-ke-google-play)
- [Keputusan desain penting](#keputusan-desain-penting)

---

## Fitur

**Transaksi**
- Order dengan beberapa baris layanan dalam satu nota
- Layanan kiloan, satuan, meter, dan paket, masing-masing dengan harga sendiri
- Minimum berat dan pembulatan yang bisa diatur per layanan
- Express dengan pengali harga dan durasi tersendiri
- Status cucian: Diterima, Diproses, Selesai, Diambil, Dibatalkan
- Status bayar terpisah: Belum bayar, DP, Lunas

**Pembayaran**
- Lunas, DP bertahap, atau bayar saat ambil
- Metode bayar yang bisa ditambah sendiri
- Hitung kembalian otomatis
- Diskon dengan batas untuk kasir, di atas batas butuh PIN Owner
- Refund tercatat sebagai transaksi negatif, data asli tidak dihapus

**Nota**
- Printer thermal Bluetooth ESC/POS 58 mm dan 80 mm
- Cetak otomatis setelah simpan, cetak ulang bertanda "CETAK ULANG"
- Kwitansi pelunasan dan laporan tutup shift
- Uji cetak untuk memastikan lebar kertas benar

**WhatsApp**
- Pemicu: order diterima, cucian selesai, pengingat belum diambil
- Template bisa diedit dengan variabel seperti `{nama}` dan `{no_order}`
- Log kirim lengkap, dan satu pemicu tidak terkirim dua kali

**Shift kasir**
- Buka shift dengan kas awal, tutup dengan kas fisik hitungan tangan
- Kas seharusnya dihitung otomatis: kas awal ditambah pembayaran tunai
- Selisih kas langsung terlihat, dan laporan tutup shift bisa dicetak
- Riwayat shift beserta selisihnya untuk Owner

**Laporan**
- Pendapatan harian, periode bebas, per layanan, per metode bayar, per kasir
- Grafik tren harian
- Daftar piutang dengan umur tagihan
- Ekspor CSV untuk Excel, dan PDF siap cetak

**Backup**
- Backup otomatis harian ke penyimpanan aplikasi, tujuh salinan terakhir
- Bagikan backup ke WhatsApp, email, atau Google Drive
- Restore dari berkas, dengan salinan pengaman sebelum menimpa

**Pengguna**
- Login PIN, dua peran: Owner dan Kasir
- Kasir tidak bisa mengubah harga atau membuka laporan keseluruhan
- Setiap transaksi menyimpan siapa yang membuatnya

---

## Menjalankan pertama kali

Butuh Flutter 3.19 atau lebih baru dan Android SDK.

```bash
git clone https://github.com/fhwattiheluw/Loundry_mobile.git
cd Loundry_mobile
bash tool/bootstrap.sh
flutter run
```

`tool/bootstrap.sh` mengambil Gradle wrapper dan ikon aplikasi yang tidak
ikut masuk git, lalu menjalankan `flutter pub get`.

**PIN awal: `1234`** (peran Owner). Ganti lewat Pengaturan → Pengguna dan PIN
sebelum dipakai di konter.

Data contoh yang ikut terpasang: enam layanan laundry dengan harga umum,
template WhatsApp berbahasa Indonesia, dan catatan kaki nota. Semua bisa
diubah lewat layar Pengaturan.

### Menyambungkan printer

1. Pasangkan printer lewat pengaturan Bluetooth Android lebih dulu.
2. Buka Pengaturan → Printer Bluetooth di aplikasi.
3. Pilih lebar kertas yang sesuai, lalu pilih printer dari daftar.
4. Tekan **Uji cetak** dan periksa apakah ada baris yang terpotong.

---

## Struktur kode

```
lib/
  core/          format angka, PIN, nomor HP, tema
  domain/        model dan PriceCalculator — seluruh aturan uang
  data/
    db/          skema SQLite, migrasi, data awal
    repositories/ akses data per bidang
  services/
    printer/     ESC/POS dan koneksi Bluetooth
    notification/ WhatsApp dan log kirim
    ads/         AdMob
    connectivity/ gerbang koneksi internet
  application/   provider Riverpod
  ui/            layar
test/            pengujian aturan harga, laporan, dan nomor HP
```

Aturan yang dijaga:

- Widget tidak pernah menghitung uang sendiri. Semua lewat `PriceCalculator`.
- Mengganti merek printer cukup menyentuh `ReceiptPrinter`.
- Mengganti cara kirim WhatsApp cukup membuat `NotificationSender` baru.
- Teks nota dan template tersimpan di tabel `settings`, bukan di kode.

---

## Pengujian

```bash
flutter test
```

Yang diuji:

| Berkas | Isi |
| --- | --- |
| `test/price_calculator_test.dart` | Pembulatan berat, minimum, express, diskon, status bayar, estimasi selesai, kembalian |
| `test/report_repository_test.dart` | Nomor order urut, pendapatan dari pembayaran, refund, pembatalan, piutang, grafik harian |
| `test/shift_repository_test.dart` | Buka dan tutup shift, kas seharusnya, selisih kas, pemisahan tunai dan non-tunai |
| `test/security_test.dart` | Normalisasi dan validasi nomor HP, hash PIN, format rupiah |

Uji laporan memakai SQLite sungguhan lewat `sqflite_common_ffi`, bukan tiruan,
sehingga kueri SQL diuji apa adanya.

---

## Konfigurasi AdMob

ID bawaan di kode adalah **ID uji resmi Google**. Jangan memakai ID produksi
selama pengembangan: klik dari pengujian sendiri adalah penyebab paling umum
akun AdMob ditutup permanen.

Ganti ID aplikasi di `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-XXXXXXXX~YYYYYYYY" />
```

ID unit iklan diisi saat build:

```bash
flutter build appbundle --release \
  --dart-define=ADMOB_BANNER_ID=ca-app-pub-XXXX/1111 \
  --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-XXXX/2222 \
  --dart-define=ADMOB_REWARDED_ID=ca-app-pub-XXXX/3333
```

### Di mana iklan muncul

| Layar | Iklan |
| --- | --- |
| Beranda, daftar order, laporan | Banner, berjarak 24 dp dari tombol mana pun |
| Setelah login | Interstitial, maksimal sekali per sesi |
| Ekspor laporan PDF | Rewarded ad opsional, bisa ditolak; ekspor CSV selalu gratis |
| Input order, pembayaran, proses cetak | **Tidak ada iklan** |

Penempatan ini mengikuti kebijakan AdMob, yang melarang interstitial terpicu
setelah setiap aksi pengguna maupun iklan yang menyela alur kerja inti.
Melanggarnya berakibat penutupan akun yang tidak bisa dibuka lagi dengan
akun baru.

Sebelum rilis, Play Console wajib mendeklarasikan penggunaan Advertising ID,
dan aplikasi wajib punya kebijakan privasi yang bisa diakses publik.

---

## Deploy ke Google Play

### 1. Buat kunci penandatanganan

```bash
keytool -genkey -v -keystore ~/laundry-pos.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias laundry
```

Simpan berkas `.jks` dan kata sandinya baik-baik. Kehilangannya berarti
tidak bisa lagi memperbarui aplikasi di Play Store.

### 2. Buat `android/key.properties`

```properties
storePassword=KATA_SANDI_KEYSTORE
keyPassword=KATA_SANDI_KUNCI
keyAlias=laundry
storeFile=/path/lengkap/ke/laundry-pos.jks
```

Berkas ini sudah masuk `.gitignore` dan tidak boleh di-commit.

### 3. Naikkan versi

Ubah `version:` di `pubspec.yaml`, misalnya `0.1.0+1` menjadi `0.2.0+2`.
Angka setelah `+` harus selalu naik di setiap unggahan.

### 4. Build

```bash
flutter build appbundle --release \
  --dart-define=ADMOB_BANNER_ID=... \
  --dart-define=ADMOB_INTERSTITIAL_ID=... \
  --dart-define=ADMOB_REWARDED_ID=...
```

Hasilnya di `build/app/outputs/bundle/release/app-release.aab`.

Untuk dipasang langsung ke perangkat tanpa Play Store:

```bash
flutter build apk --release --split-per-abi
```

### 5. Sebelum mengunggah

- [ ] PIN bawaan `1234` sudah diganti
- [ ] ID AdMob produksi sudah dipasang, bukan ID uji
- [ ] Kebijakan privasi sudah ada dan bisa diakses publik
- [ ] Advertising ID sudah dideklarasikan di Play Console
- [ ] Formulir Data Safety sudah diisi
- [ ] Ikon aplikasi sudah diganti dari ikon bawaan Flutter
- [ ] Uji cetak berhasil di printer yang akan dipakai
- [ ] Uji kirim WhatsApp berhasil di perangkat asli

---

## Keputusan desain penting

**Pendapatan dihitung dari tabel `payments`, bukan nilai order.**
Memakai nilai order akan memasukkan piutang sebagai pendapatan, dan pemilik
akan mengira punya uang yang belum diterima. Order dengan DP bulan ini dan
pelunasan bulan depan terbagi pendapatannya ke dua bulan.

**Harga disalin ke baris nota saat transaksi dibuat.**
Tanpa itu, menaikkan harga layanan akan mengubah nilai nota lama dan merusak
laporan bulan sebelumnya.

**Transaksi tidak pernah dihapus, hanya ditandai batal.**
Pembatalan dan refund meninggalkan jejak lengkap beserta alasan dan
penggunanya.

**Kegagalan printer tidak membatalkan order.**
Order disimpan lebih dulu, baru dicetak. Kalau printer mati, order tetap ada
dan nota bisa dicetak ulang kapan saja.

**Nota memakai huruf ASCII saja.**
Printer thermal murah menampilkan karakter non-ASCII sebagai sampah, dan tiap
merek berbeda. Karena itu nominal dicetak tanpa simbol "Rp".

**Aplikasi mewajibkan koneksi internet.**
Ini keputusan bisnis, bukan keterbatasan teknis: seluruh lapisan data sanggup
berjalan offline. Saat koneksi putus, aplikasi menampilkan layar pemberitahuan
dan memeriksa ulang otomatis setiap 10 detik; data di perangkat tetap aman.
Bila suatu saat konter perlu tetap melayani pelanggan saat jaringan mati,
ubah `requireInternet` menjadi `false` di `lib/app.dart`.
