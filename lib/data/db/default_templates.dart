/// Isi bawaan template WhatsApp.
///
/// Dipisah dari seed supaya migrasi bisa mengenali template lama yang
/// belum pernah diubah pemilik. Template yang sudah diedit pemilik tidak
/// pernah ditimpa: migrasi hanya mengganti teks yang persis sama dengan
/// bawaan lama.
abstract final class DefaultTemplates {
  static const orderCreated =
      'Halo {nama}, pesanan laundry Anda sudah kami terima.\n\n'
      '*No. Nota:* {no_order}\n'
      '*Tanggal:* {tanggal}\n'
      '*Estimasi selesai:* {estimasi}\n\n'
      '*Rincian pesanan*\n'
      '{rincian}\n\n'
      '{ringkasan}\n\n'
      'Status bayar: {status_bayar}\n\n'
      'Terima kasih. {nama_usaha}';

  static const orderDone =
      'Halo {nama}, cucian Anda sudah selesai dan siap diambil.\n\n'
      '*No. Nota:* {no_order}\n'
      '*Lokasi rak:* {rak}\n\n'
      '*Rincian pesanan*\n'
      '{rincian}\n\n'
      '{ringkasan}\n\n'
      '{jam_buka}\n\n'
      'Terima kasih. {nama_usaha}';

  static const reminder =
      'Halo {nama}, cucian Anda dengan nota {no_order} sudah selesai '
      'sejak {estimasi} dan belum diambil.\n\n'
      '*Lokasi rak:* {rak}\n\n'
      '*Rincian pesanan*\n'
      '{rincian}\n\n'
      '{ringkasan}\n\n'
      'Mohon diambil ya. Terima kasih. {nama_usaha}';

  static const payment =
      'Halo {nama}, pembayaran Anda sudah kami terima.\n\n'
      '*No. Nota:* {no_order}\n\n'
      '*Rincian pesanan*\n'
      '{rincian}\n\n'
      '{ringkasan}\n\n'
      'Terima kasih. {nama_usaha}';

  // ---- Bawaan lama (sampai skema 5), hanya untuk dikenali oleh migrasi ----

  static const legacyOrderCreated =
      'Halo {nama}, pesanan laundry Anda sudah kami terima.\n\n'
      'No. Nota: {no_order}\n'
      'Layanan: {layanan}\n'
      'Total: {total}\n'
      'Status bayar: {status_bayar}\n'
      'Estimasi selesai: {estimasi}\n\n'
      'Terima kasih. {nama_usaha}';

  static const legacyOrderDone =
      'Halo {nama}, cucian Anda sudah selesai dan siap diambil.\n\n'
      'No. Nota: {no_order}\n'
      'Sisa tagihan: {sisa}\n'
      '{jam_buka}\n\n'
      'Terima kasih. {nama_usaha}';

  static const legacyReminder =
      'Halo {nama}, cucian Anda dengan nota {no_order} sudah selesai '
      'sejak {estimasi} dan belum diambil.\n\n'
      'Sisa tagihan: {sisa}\n'
      'Mohon diambil ya. Terima kasih. {nama_usaha}';

  static const legacyPayment =
      'Halo {nama}, pembayaran Anda sudah kami terima.\n\n'
      'No. Nota: {no_order}\n'
      'Dibayar: {dibayar}\n'
      'Sisa tagihan: {sisa}\n\n'
      'Terima kasih. {nama_usaha}';
}
