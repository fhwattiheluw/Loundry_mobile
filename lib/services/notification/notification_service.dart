import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/db/app_database.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import 'message_template.dart';

class NotificationResult {
  const NotificationResult.sent()
      : sent = true,
        skipped = false,
        message = '';
  const NotificationResult.skipped(this.message)
      : sent = false,
        skipped = true;
  const NotificationResult.failed(this.message)
      : sent = false,
        skipped = false;

  final bool sent;
  final bool skipped;
  final String message;
}

/// Antarmuka pengirim notifikasi.
///
/// Mode manual (`wa.me`) dan mode API nantinya dipasang di balik antarmuka
/// yang sama, sehingga alur order tidak perlu berubah saat pemilik berpindah
/// mode (FR-66, FR-67).
abstract interface class NotificationSender {
  Future<NotificationResult> send({
    required String phone,
    required String message,
  });
}

/// Mode manual: membuka WhatsApp dengan pesan sudah terisi, kasir menekan
/// tombol kirim. Gratis, tanpa server, dan tidak berisiko memblokir nomor.
class WhatsAppManualSender implements NotificationSender {
  const WhatsAppManualSender();

  @override
  Future<NotificationResult> send({
    required String phone,
    required String message,
  }) async {
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );

    try {
      final opened =
          await launchUrl(uri, mode: LaunchMode.externalApplication);

      return opened
          ? const NotificationResult.sent()
          : const NotificationResult.failed(
              'WhatsApp tidak bisa dibuka. Pastikan WhatsApp terpasang.');
    } catch (e) {
      return NotificationResult.failed('Gagal membuka WhatsApp: $e');
    }
  }
}

/// Mencatat setiap percobaan kirim, dan mencegah pesan yang sama terkirim
/// dua kali untuk pemicu yang sama (FR-68, FR-71).
class NotificationService {
  NotificationService(this._db, this._template, this._sender);

  final AppDatabase _db;
  final MessageTemplate _template;
  final NotificationSender _sender;

  Future<NotificationResult> notify(
    LaundryOrder order,
    NotificationTrigger trigger, {
    bool force = false,
  }) async {
    if (!_template.isEnabled(trigger) && !force) {
      return const NotificationResult.skipped('Pemicu ini dimatikan pemilik.');
    }

    if (order.customerPhone.isEmpty) {
      return const NotificationResult.skipped(
          'Pelanggan ini tidak punya nomor WhatsApp.');
    }

    if (!force && await alreadySent(order.id!, trigger)) {
      return const NotificationResult.skipped('Pesan ini sudah pernah terkirim.');
    }

    final message = _template.forTrigger(trigger, order);
    final result = await _sender.send(
      phone: order.customerPhone,
      message: message,
    );

    await _log(
      orderId: order.id!,
      trigger: trigger,
      target: order.customerPhone,
      state: result.sent ? NotificationState.terkirim : NotificationState.gagal,
      error: result.sent ? null : result.message,
    );

    return result;
  }

  Future<bool> alreadySent(int orderId, NotificationTrigger trigger) async {
    final db = await _db.database;
    final rows = await db.query(
      'notification_logs',
      where: "order_id = ? AND trigger = ? AND status = 'terkirim'",
      whereArgs: [orderId, trigger.name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _log({
    required int orderId,
    required NotificationTrigger trigger,
    required String target,
    required NotificationState state,
    String? error,
  }) async {
    final db = await _db.database;

    await db.insert(
      'notification_logs',
      {
        'order_id': orderId,
        'trigger': trigger.name,
        'target': target,
        'sent_at': DateTime.now().toIso8601String(),
        'status': state.name,
        'error': error,
      },
      // Indeks unik hanya berlaku untuk status terkirim. Percobaan gagal
      // boleh tercatat berkali-kali supaya pemilik tahu ada masalah.
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Riwayat kirim untuk satu order, dipakai di layar detail.
  Future<List<Map<String, Object?>>> historyOf(int orderId) async {
    final db = await _db.database;
    return db.query('notification_logs',
        where: 'order_id = ?', whereArgs: [orderId], orderBy: 'sent_at DESC');
  }

  /// Semua pesan yang gagal kirim, untuk dikirim ulang manual (FR-69).
  Future<List<Map<String, Object?>>> failures({int limit = 50}) async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT n.*, o.order_no, c.name AS customer_name
      FROM notification_logs n
      JOIN orders o ON o.id = n.order_id
      JOIN customers c ON c.id = o.customer_id
      WHERE n.status = 'gagal'
      ORDER BY n.sent_at DESC
      LIMIT ?
    ''', [limit]);
  }
}
