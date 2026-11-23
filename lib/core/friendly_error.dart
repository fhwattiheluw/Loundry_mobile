import 'dart:async';
import 'dart:io';

/// Mengubah galat teknis menjadi kalimat yang bisa dipahami kasir.
///
/// Teks seperti "DatabaseException(SqliteException(5))" atau "FormatException:
/// Invalid number" tidak memberi tahu apa yang harus dilakukan, dan membuat
/// pemilik warung laundry mengira aplikasinya rusak. Di sini tiap jenis
/// masalah diberi satu penjelasan dan satu langkah berikutnya.
///
/// Dipakai dengan menambahkan kalimat tindakan di depannya:
/// `'Order belum tersimpan. ${friendlyError(e)}'`.
String friendlyError(Object error) {
  // Pesan StateError di aplikasi ini sudah ditulis untuk manusia, misalnya
  // "Order yang dibatalkan tidak bisa menerima pembayaran." Tampilkan apa
  // adanya, tanpa awalan "Bad state:".
  if (error is StateError) return error.message;

  final text = error.toString();
  final lower = text.toLowerCase();

  if (error is SocketException ||
      lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('clientexception')) {
    return 'Tidak ada koneksi internet. Periksa sinyal atau Wi-Fi, lalu coba '
        'lagi.';
  }

  if (error is TimeoutException || lower.contains('timeout')) {
    return 'Terlalu lama menunggu. Coba lagi sebentar lagi.';
  }

  if (lower.contains('unique constraint')) {
    return 'Data yang sama sudah ada, misalnya nomor HP yang sudah dipakai '
        'pelanggan lain.';
  }

  if (lower.contains('database is locked') ||
      lower.contains('databaseexception') ||
      lower.contains('sqliteexception') ||
      lower.contains('sqlite')) {
    return 'Penyimpanan data sedang bermasalah. Tutup aplikasi lalu buka '
        'lagi. Bila terus terjadi, buat backup dan hubungi pengembang.';
  }

  if (error is FileSystemException || lower.contains('filesystemexception')) {
    if (lower.contains('no space') || lower.contains('enospc')) {
      return 'Penyimpanan HP penuh. Hapus foto atau berkas yang tidak '
          'dipakai, lalu coba lagi.';
    }
    return 'Berkas tidak bisa dibaca atau ditulis. Periksa ruang penyimpanan '
        'HP, lalu coba lagi.';
  }

  if (error is FormatException || lower.contains('formatexception')) {
    return 'Isi atau format data tidak sesuai. Periksa lagi lalu coba lagi.';
  }

  if (lower.contains('permission') || lower.contains('denied')) {
    return 'Izin belum diberikan. Buka Pengaturan HP, pilih Aplikasi, lalu '
        'Laundry Manise, dan izinkan akses yang diminta.';
  }

  return 'Terjadi kesalahan yang tidak terduga. Coba lagi. Bila terus '
      'berulang, buat backup lalu buka ulang aplikasi.';
}
