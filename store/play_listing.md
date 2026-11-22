# Materi halaman Play Store

Berkas ini sumber kebenaran untuk teks yang dipasang di Play Console.
Kalau diubah di Play Console, ubah juga di sini.

## Nama

| Dipakai di | Nilai | Alasan |
| --- | --- | --- |
| Layar HP (`android:label`) | `Laundry Manise` | Peluncur memotong sekitar 11–12 huruf. Nama pendek dan khas lebih mudah diingat daripada nama panjang yang terpotong |
| Judul Play Store (maks 30) | `Kasir Laundry Manise: Nota WA` | Pencarian Play mencocokkan judul lebih kuat daripada bagian lain. "Kasir" dan "Laundry" adalah kata yang benar-benar diketik orang |
| Nama paket | `com.manise.laundry` | Tidak bisa diubah setelah terbit |

Judulnya 29 huruf, masih di bawah batas.

## Deskripsi singkat (maks 80)

```
Kasir laundry: nota Bluetooth, notifikasi WhatsApp, laporan, tanpa internet.
```

76 huruf. Baris ini yang muncul di bawah judul pada hasil pencarian, jadi
isinya empat fitur utama, bukan ajakan.

## Deskripsi panjang

Tiga baris pertama dipotong Play sebelum tombol "Selengkapnya". Semua yang
menentukan keputusan harus sudah lewat sebelum titik itu.

```
Catat cucian, cetak nota lewat printer Bluetooth, dan kabari pelanggan lewat
WhatsApp — semuanya dari satu HP, tanpa perlu internet.

Hitung berat otomatis dengan minimum dan pembulatan, lacak piutang, tutup
shift kasir, dan lihat pendapatan harian.

FITUR
• Nota cetak ke printer thermal Bluetooth 58 mm dan 80 mm
• Notifikasi WhatsApp otomatis: cucian diterima, selesai, dan pengingat
• Hitung harga per kg, per meter, atau per potong
• Minimum berat, pembulatan, dan tarif express per layanan
• Lokasi rak penyimpanan, tercetak di nota
• Foto cucian saat diterima, sebagai bukti bila ada sengketa
• Laporan pendapatan harian, mingguan, bulanan, bisa dicetak
• Shift kasir dengan pencocokan uang laci
• Piutang pelanggan yang belum membayar
• Data tersimpan di HP dan terenkripsi, jalan penuh tanpa internet
• Backup dan pemulihan data

GRATIS
Aplikasi ini gratis dan didukung iklan. Iklan tidak pernah muncul saat Anda
membuat nota, menerima pembayaran, atau mencetak.
```

## Tangkapan layar

Urutan ini disengaja. Orang menggeser, bukan membaca, jadi dua gambar
pertama harus menjelaskan seluruh aplikasi.

1. Nota keluar dari printer Bluetooth, dengan tulisan besar "Cetak nota
   langsung dari HP"
2. Pesan WhatsApp terkirim ke pelanggan, "Pelanggan dikabari otomatis"
3. Layar Order Baru dengan timbangan
4. Laporan pendapatan
5. Tutup shift dengan selisih kas

## Kata kunci yang dikejar

`kasir laundry`, `aplikasi laundry`, `nota laundry`, `pos laundry`,
`laundry kiloan`, `cetak nota bluetooth`

Play tidak punya kolom kata kunci sendiri; semua kata di atas harus muncul
wajar di judul, deskripsi singkat, dan deskripsi panjang.

## Build rilis

ID iklan dan langganan tidak ditulis di kode. Semuanya diberikan saat build:

```bash
flutter build appbundle --release \
  --dart-define=ADMOB_BANNER_ID=ca-app-pub-xxx/111 \
  --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-xxx/222 \
  --dart-define=ADMOB_REWARDED_ID=ca-app-pub-xxx/333 \
  --dart-define=ADMOB_APP_OPEN_ID=ca-app-pub-xxx/444 \
  --dart-define=ADMOB_NATIVE_ID=ca-app-pub-xxx/555
```

Tanpa flag ini aplikasi memakai ID uji Google. Itu disengaja: memakai ID
produksi selama pengembangan adalah penyebab paling umum akun AdMob
ditutup permanen.

App ID AdMob tetap dipasang di `android/app/src/main/AndroidManifest.xml`,
dan nilainya sekarang masih ID uji.
