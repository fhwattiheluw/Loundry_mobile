import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/db/settings_keys.dart';
import '../../data/repositories/settings_repository.dart';
import 'notification_service.dart';

/// Mode otomatis: pesan dikirim lewat WhatsApp Cloud API resmi milik Meta,
/// tanpa membuka aplikasi WhatsApp (FR-67).
///
/// Yang harus dipahami pemilik sebelum mengaktifkan ini:
///
/// 1. Berbayar per percakapan, dan butuh verifikasi bisnis di Meta.
/// 2. Pesan yang dimulai oleh bisnis WAJIB memakai template yang sudah
///    disetujui Meta lebih dulu. Mengirim teks bebas hanya diizinkan dalam
///    24 jam setelah pelanggan membalas.
/// 3. Nomor yang dipakai tidak boleh nomor WhatsApp biasa yang sedang aktif
///    di ponsel; nomor itu harus didaftarkan ke Cloud API.
///
/// Memakai gateway tidak resmi yang membajak sesi WhatsApp pribadi memang
/// lebih murah, tapi melanggar ketentuan layanan WhatsApp dan berisiko
/// nomor usaha diblokir permanen. Kelas ini sengaja hanya mendukung API resmi.
class WhatsAppApiSender implements NotificationSender {
  WhatsAppApiSender(this._settings, {http.Client? client})
      : _client = client ?? http.Client();

  final SettingsRepository _settings;
  final http.Client _client;

  bool get isConfigured =>
      _settings.get(SettingsKeys.whatsappPhoneNumberId).isNotEmpty &&
      _settings.get(SettingsKeys.whatsappToken).isNotEmpty;

  @override
  Future<NotificationResult> send({
    required String phone,
    required String message,
  }) async {
    if (!isConfigured) {
      return const NotificationResult.failed(
        'Mode API belum diatur. Isi Phone Number ID dan token di Pengaturan.',
      );
    }

    final version =
        _settings.get(SettingsKeys.whatsappApiVersion, fallback: 'v21.0');
    final phoneId = _settings.get(SettingsKeys.whatsappPhoneNumberId);
    final token = _settings.get(SettingsKeys.whatsappToken);
    final template = _settings.get(SettingsKeys.whatsappTemplateName);

    final uri =
        Uri.parse('https://graph.facebook.com/$version/$phoneId/messages');

    // Dengan nama template terisi, pesan dikirim sebagai template yang sudah
    // disetujui Meta. Tanpa itu, dikirim sebagai teks biasa, yang hanya
    // berhasil dalam jendela 24 jam setelah pelanggan membalas.
    final body = template.isEmpty
        ? {
            'messaging_product': 'whatsapp',
            'to': phone,
            'type': 'text',
            'text': {'preview_url': false, 'body': message},
          }
        : {
            'messaging_product': 'whatsapp',
            'to': phone,
            'type': 'template',
            'template': {
              'name': template,
              'language': {'code': 'id'},
              'components': [
                {
                  'type': 'body',
                  'parameters': [
                    {'type': 'text', 'text': message},
                  ],
                },
              ],
            },
          };

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const NotificationResult.sent();
      }

      return NotificationResult.failed(_readError(response));
    } catch (e) {
      return NotificationResult.failed('Gagal menghubungi WhatsApp: $e');
    }
  }

  /// Meta mengembalikan pesan galat yang cukup jelas. Menampilkannya apa
  /// adanya jauh lebih menolong daripada "terjadi kesalahan".
  String _readError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        final message = error['message'] ?? 'Tidak diketahui';
        final code = error['code'];
        return 'WhatsApp menolak (${response.statusCode}/$code): $message';
      }
    } catch (_) {
      // Jatuh ke pesan umum di bawah.
    }
    return 'WhatsApp menolak dengan kode ${response.statusCode}.';
  }

  void dispose() => _client.close();
}
