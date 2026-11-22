/// Kunci tabel `settings`. Dipakai sebagai konstanta supaya salah ketik
/// ketahuan saat kompilasi, bukan saat aplikasi sudah di tangan pemilik.
abstract final class SettingsKeys {
  static const businessName = 'business_name';
  static const businessAddress = 'business_address';
  static const businessPhone = 'business_phone';
  static const receiptFooter = 'receipt_footer';
  static const openHours = 'open_hours';

  static const paperWidth = 'paper_width'; // 58 atau 80
  static const printerAddress = 'printer_address';
  static const printerName = 'printer_name';
  static const receiptCopies = 'receipt_copies';

  static const reminderDays = 'reminder_days';
  static const maxCashierDiscount = 'max_cashier_discount';
  static const paymentMethods = 'payment_methods';
  static const perfumes = 'perfumes';
  static const extraFeeLabel = 'extra_fee_label';
  static const receiptQrEnabled = 'receipt_qr_enabled';
  static const receiptLogoPath = 'receipt_logo_path';


  /// Berapa kali aplikasi pernah dibuka. Dipakai menahan iklan pembuka
  /// sampai pengguna sempat mengenal aplikasinya lebih dulu.
  static const appOpenCount = 'app_open_count';

  /// Menandai wizard pengaturan awal sudah dilewati, supaya ia hanya
  /// muncul sekali di pemasangan baru.
  static const setupDone = 'setup_done';

  /// Pemulihan PIN pemilik. Yang disimpan hanya hasil pengacakan kodenya,
  /// sama seperti PIN: kode yang bisa dibaca kembali dari database sama
  /// saja dengan tidak punya kunci sama sekali.
  static const recoveryCodeHash = 'recovery_code_hash';
  static const pinResetCodeHash = 'pin_reset_code_hash';
  static const pinResetExpiresAt = 'pin_reset_expires_at';

  /// 'system', 'light', atau 'dark'.
  static const themeMode = 'theme_mode';

  static const notifyOrderCreated = 'notify_order_created';
  static const notifyOrderDone = 'notify_order_done';
  static const notifyReminder = 'notify_reminder';
  static const notifyPaymentReceived = 'notify_payment_received';

  /// 'manual' memakai deep link wa.me, 'api' memakai WhatsApp Cloud API.
  static const whatsappMode = 'whatsapp_mode';
  static const whatsappPhoneNumberId = 'whatsapp_phone_number_id';
  static const whatsappToken = 'whatsapp_token';
  static const whatsappTemplateName = 'whatsapp_template_name';
  static const whatsappApiVersion = 'whatsapp_api_version';

  /// Jam tenang: notifikasi di luar jam ini ditunda (FR-72).
  static const quietHoursEnabled = 'quiet_hours_enabled';
  static const quietHoursStart = 'quiet_hours_start';
  static const quietHoursEnd = 'quiet_hours_end';

  static const templateOrderCreated = 'template_order_created';
  static const templateOrderDone = 'template_order_done';
  static const templateReminder = 'template_reminder';
  static const templatePayment = 'template_payment';

  static const seededAt = 'seeded_at';

  /// Kapan pemilik terakhir membuat backup SENDIRI lewat wizard atau tombol
  /// di Pengaturan (waktu ISO 8601). Backup harian otomatis sengaja tidak
  /// dihitung: ia ada di dalam HP yang sama dan tidak melindungi dari HP
  /// hilang, jadi tidak boleh membungkam pengingat.
  static const backupLastAt = 'backup_last_at';

  /// 'share' (dibagikan ke luar HP) atau 'device' (disimpan di HP).
  static const backupLastMethod = 'backup_last_method';

  /// Terakhir kali dialog pengingat backup ditampilkan, supaya tidak muncul
  /// berkali-kali dalam sehari.
  static const backupPromptedAt = 'backup_prompted_at';
}
