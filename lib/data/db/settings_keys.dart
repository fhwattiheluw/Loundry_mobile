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

  static const adsEnabled = 'ads_enabled';

  static const notifyOrderCreated = 'notify_order_created';
  static const notifyOrderDone = 'notify_order_done';
  static const notifyReminder = 'notify_reminder';

  static const templateOrderCreated = 'template_order_created';
  static const templateOrderDone = 'template_order_done';
  static const templateReminder = 'template_reminder';

  static const seededAt = 'seeded_at';
}
