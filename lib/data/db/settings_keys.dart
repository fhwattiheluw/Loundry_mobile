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

  static const adsEnabled = 'ads_enabled';

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
}
