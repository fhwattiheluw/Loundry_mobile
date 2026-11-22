// Status cucian dan status bayar sengaja dipisah.
// Cucian bisa Selesai sementara pembayaran masih nol.

enum LaundryStatus {
  diterima,
  diproses,
  selesai,
  diambil,
  dibatalkan;

  static LaundryStatus fromDb(String value) => LaundryStatus.values.firstWhere(
        (e) => e.name == value,
        orElse: () => LaundryStatus.diterima,
      );

  String get label => switch (this) {
        LaundryStatus.diterima => 'Diterima',
        LaundryStatus.diproses => 'Diproses',
        LaundryStatus.selesai => 'Selesai',
        LaundryStatus.diambil => 'Diambil',
        LaundryStatus.dibatalkan => 'Dibatalkan',
      };

  /// Status berikutnya dalam alur normal. Null bila sudah di ujung.
  LaundryStatus? get next => switch (this) {
        LaundryStatus.diterima => LaundryStatus.diproses,
        LaundryStatus.diproses => LaundryStatus.selesai,
        LaundryStatus.selesai => LaundryStatus.diambil,
        _ => null,
      };

  bool get isOpen =>
      this != LaundryStatus.diambil && this != LaundryStatus.dibatalkan;
}

enum PaymentStatus {
  belumBayar,
  dp,
  lunas;

  static PaymentStatus fromDb(String value) => PaymentStatus.values.firstWhere(
        (e) => e.name == value,
        orElse: () => PaymentStatus.belumBayar,
      );

  String get label => switch (this) {
        PaymentStatus.belumBayar => 'Belum bayar',
        PaymentStatus.dp => 'DP',
        PaymentStatus.lunas => 'Lunas',
      };
}

enum ServiceUnit {
  kg,
  pcs,
  meter,
  paket;

  static ServiceUnit fromDb(String value) => ServiceUnit.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ServiceUnit.kg,
      );

  String get label => switch (this) {
        ServiceUnit.kg => 'kg',
        ServiceUnit.pcs => 'pcs',
        ServiceUnit.meter => 'm2',
        ServiceUnit.paket => 'paket',
      };

  /// Satuan kiloan dan meter boleh pecahan, satuan lain harus bulat.
  bool get allowsFraction => this == ServiceUnit.kg || this == ServiceUnit.meter;
}

enum UserRole {
  owner,
  kasir;

  static UserRole fromDb(String value) => UserRole.values.firstWhere(
        (e) => e.name == value,
        orElse: () => UserRole.kasir,
      );

  String get label => this == UserRole.owner ? 'Owner' : 'Kasir';
}

/// Pemicu notifikasi. Dipakai juga sebagai kunci anti-kirim-ganda
/// pada tabel notification_logs.
enum NotificationTrigger {
  orderDiterima,
  cucianSelesai,
  pengingatAmbil,
  pembayaranDiterima;

  static NotificationTrigger fromDb(String value) =>
      NotificationTrigger.values.firstWhere(
        (e) => e.name == value,
        orElse: () => NotificationTrigger.orderDiterima,
      );

  String get label => switch (this) {
        NotificationTrigger.orderDiterima => 'Order diterima',
        NotificationTrigger.cucianSelesai => 'Cucian selesai',
        NotificationTrigger.pengingatAmbil => 'Pengingat pengambilan',
        NotificationTrigger.pembayaranDiterima => 'Pembayaran diterima',
      };
}

enum NotificationState { terkirim, gagal, tertunda }
