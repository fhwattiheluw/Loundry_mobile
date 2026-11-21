import '../../core/formatters.dart';
import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';

/// Mengisi variabel template WhatsApp yang diedit pemilik di Pengaturan.
///
/// Variabel yang dikenali:
/// {nama} {no_order} {layanan} {total} {dibayar} {sisa} {status_bayar}
/// {estimasi} {tanggal} {nama_usaha} {jam_buka}
class MessageTemplate {
  const MessageTemplate(this._settings);

  final SettingsRepository _settings;

  String forTrigger(NotificationTrigger trigger, LaundryOrder order) {
    final template = switch (trigger) {
      NotificationTrigger.orderDiterima =>
        _settings.get(SettingsKeys.templateOrderCreated),
      NotificationTrigger.cucianSelesai =>
        _settings.get(SettingsKeys.templateOrderDone),
      NotificationTrigger.pengingatAmbil =>
        _settings.get(SettingsKeys.templateReminder),
      NotificationTrigger.pembayaranDiterima =>
        _settings.get(SettingsKeys.templatePayment),
    };

    return render(template, order);
  }

  String render(String template, LaundryOrder order) {
    final services = order.items.map((i) => i.serviceName).join(', ');

    final values = <String, String>{
      '{nama}': order.customerName,
      '{no_order}': order.orderNo,
      '{layanan}': services.isEmpty ? '-' : services,
      '{total}': formatRupiah(order.total),
      '{dibayar}': formatRupiah(order.paid),
      '{sisa}': order.remaining > 0 ? formatRupiah(order.remaining) : 'LUNAS',
      '{status_bayar}': order.paymentStatus.label,
      '{estimasi}': formatDateTime(order.estimatedAt),
      '{tanggal}': formatDate(order.createdAt),
      '{nama_usaha}': _settings.get(SettingsKeys.businessName),
      '{jam_buka}': _settings.get(SettingsKeys.openHours),
    };

    var result = template;
    values.forEach((key, value) => result = result.replaceAll(key, value));
    return result.trim();
  }

  /// Apakah pemicu ini diaktifkan pemilik.
  bool isEnabled(NotificationTrigger trigger) => switch (trigger) {
        NotificationTrigger.orderDiterima =>
          _settings.getBool(SettingsKeys.notifyOrderCreated, fallback: true),
        NotificationTrigger.cucianSelesai =>
          _settings.getBool(SettingsKeys.notifyOrderDone, fallback: true),
        NotificationTrigger.pengingatAmbil =>
          _settings.getBool(SettingsKeys.notifyReminder, fallback: true),
        NotificationTrigger.pembayaranDiterima =>
          _settings.getBool(SettingsKeys.notifyPaymentReceived),
      };
}
