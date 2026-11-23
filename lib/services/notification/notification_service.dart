import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/db/app_database.dart';
import '../../data/db/settings_keys.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/settings_repository.dart';
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
/// Mode manual (`wa.me`) dan mode API berada di balik antarmuka yang sama,
/// sehingga alur order tidak berubah saat pemilik berpindah mode.
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

/// Mencatat setiap percobaan kirim, mencegah pesan yang sama terkirim dua
/// kali, menunda pesan di luar jam operasional, dan mengirim ulang otomatis
/// pesan yang gagal (FR-68, FR-69, FR-71, FR-72).
class NotificationService {
  NotificationService({
    required AppDatabase db,
    required MessageTemplate template,
    required SettingsRepository settings,
    required NotificationSender manualSender,
    required NotificationSender apiSender,
  })  : _db = db,
        _template = template,
        _settings = settings,
        _manual = manualSender,
        _api = apiSender;

  final AppDatabase _db;
  final MessageTemplate _template;
  final SettingsRepository _settings;
  final NotificationSender _manual;
  final NotificationSender _api;

  /// Jeda yang membesar setiap percobaan, supaya gangguan jaringan singkat
  /// tidak langsung menghabiskan jatah tiga percobaan.
  static const _backoff = [
    Duration(minutes: 2),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];

  static const _maxAttempts = 3;

  bool get isApiMode =>
      _settings.get(SettingsKeys.whatsappMode, fallback: 'manual') == 'api';

  NotificationSender get _sender => isApiMode ? _api : _manual;

  // ---------------------------------------------------------------- kirim

  Future<NotificationResult> notify(
    LaundryOrder given,
    NotificationTrigger trigger, {
    bool force = false,
  }) async {
    // Order dari daftar (beranda, filter, pengingat) dimuat TANPA item,
    // dan jumlah dibayarnya bisa sudah berubah sejak daftar dimuat. Pesan
    // wajib memuat rincian lengkap, jadi order dibaca ulang dari database
    // setiap kali, apa pun asal objeknya.
    final order = given.id == null
        ? given
        : await OrderRepository(_db).byId(given.id!) ?? given;

    if (!_template.isEnabled(trigger) && !force) {
      return const NotificationResult.skipped('Pemicu ini dimatikan pemilik.');
    }

    if (order.customerPhone.isEmpty) {
      return const NotificationResult.skipped(
          'Pelanggan ini tidak punya nomor WhatsApp.');
    }

    if (!force && await alreadySent(order.id!, trigger)) {
      return const NotificationResult.skipped(
          'Pesan ini sudah pernah terkirim.');
    }

    final message = _template.forTrigger(trigger, order);

    // Jam tenang: pesan tidak dikirim tengah malam, tapi juga tidak dibuang.
    // Pesan masuk antrean dan dikirim saat jam buka berikutnya.
    //
    // Hanya untuk mode API. Di mode manual yang mengirim adalah kasir yang
    // sedang memegang HP, dan antrean tidak pernah diproses sendiri, jadi
    // pesan yang "ditunda" di sana tidak akan pernah terkirim.
    final quietUntil = isApiMode ? _quietUntil() : null;
    if (quietUntil != null && !force) {
      await _record(
        orderId: order.id!,
        trigger: trigger,
        target: order.customerPhone,
        state: NotificationState.tertunda,
        message: message,
        attempts: 0,
        nextAttemptAt: quietUntil,
      );

      return const NotificationResult.skipped(
        'Di luar jam operasional. Pesan masuk antrean dan dikirim otomatis '
        'saat jam buka.',
      );
    }

    final result = await _sender.send(
      phone: order.customerPhone,
      message: message,
    );

    await _record(
      orderId: order.id!,
      trigger: trigger,
      target: order.customerPhone,
      state: result.sent ? NotificationState.terkirim : NotificationState.gagal,
      message: message,
      attempts: result.sent ? 0 : 1,
      error: result.sent ? null : result.message,
      // Kirim ulang otomatis hanya untuk mode API. Mode manual membuka layar
      // WhatsApp, jadi mencobanya sendiri di latar akan merebut layar kasir
      // di tengah melayani pelanggan.
      nextAttemptAt: result.sent || !isApiMode
          ? null
          : DateTime.now().add(_backoff.first),
    );

    return result;
  }

  // -------------------------------------------------------------- antrean

  /// Mengirim ulang pesan yang gagal atau tertunda dan sudah waktunya dicoba.
  ///
  /// Dipanggil saat aplikasi dibuka. Mengembalikan jumlah pesan yang
  /// akhirnya berhasil terkirim.
  Future<int> processQueue() async {
    if (!isApiMode) return 0;
    if (_quietUntil() != null) return 0;

    final db = await _db.database;
    final now = DateTime.now().toIso8601String();

    final due = await db.rawQuery('''
      SELECT n.id, n.order_id, n.trigger_name, n.attempts, n.message,
             c.phone AS customer_phone, o.laundry_status
      FROM notification_logs n
      JOIN orders o ON o.id = n.order_id
      JOIN customers c ON c.id = o.customer_id
      WHERE n.status IN ('gagal', 'tertunda')
        AND n.attempts < ?
        AND n.next_attempt_at IS NOT NULL
        AND n.next_attempt_at <= ?
        AND n.message IS NOT NULL
      ORDER BY n.next_attempt_at
      LIMIT 20
    ''', [_maxAttempts, now]);

    var delivered = 0;

    for (final row in due) {
      final id = row['id'] as int;
      final orderId = row['order_id'] as int;
      final trigger = row['trigger_name'] as String;
      final attempts = (row['attempts'] as num?)?.toInt() ?? 0;
      final phone = row['customer_phone'] as String? ?? '';
      final message = row['message'] as String? ?? '';

      // Pesan yang sama sudah sampai lewat jalur lain, misalnya kasir
      // mengirim ulang sendiri atau percobaan berikutnya berhasil. Baris ini
      // tinggal sisa; mengirimnya lagi membuat pelanggan menerima dua pesan
      // yang sama, dan menandainya terkirim melanggar indeks unik.
      if (await _alreadySentByName(orderId, trigger)) {
        await db.delete('notification_logs', where: 'id = ?', whereArgs: [id]);
        continue;
      }

      if (row['laundry_status'] == 'dibatalkan') {
        await _abandon(id, 'Order sudah dibatalkan.');
        continue;
      }

      if (phone.isEmpty || message.isEmpty) {
        await _abandon(id, 'Nomor atau isi pesan tidak lengkap.');
        continue;
      }

      final result = await _api.send(phone: phone, message: message);
      final nextAttempts = attempts + 1;

      if (result.sent) {
        delivered++;
        await _markDelivered(id, orderId, trigger, attempts: nextAttempts);
        continue;
      }

      if (nextAttempts >= _maxAttempts) {
        await _abandon(id, result.message);
        continue;
      }

      await db.update(
        'notification_logs',
        {
          'status': NotificationState.gagal.name,
          'attempts': nextAttempts,
          'next_attempt_at': DateTime.now()
              .add(_backoff[nextAttempts.clamp(0, _backoff.length - 1)])
              .toIso8601String(),
          'error': result.message,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    return delivered;
  }

  /// Menyerah setelah percobaan terakhir. Barisnya tetap ada supaya pemilik
  /// bisa melihat pesan mana yang tidak pernah sampai.
  Future<void> _abandon(int id, String error) async {
    final db = await _db.database;
    await db.update(
      'notification_logs',
      {
        'status': NotificationState.gagal.name,
        'attempts': _maxAttempts,
        'next_attempt_at': null,
        'error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Berapa banyak pesan yang masih menunggu giliran dikirim.
  Future<int> pendingCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM notification_logs '
      "WHERE status IN ('gagal', 'tertunda') AND attempts < ?",
      [_maxAttempts],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ------------------------------------------------------------ jam tenang

  /// Waktu jam buka berikutnya bila sekarang sedang jam tenang,
  /// atau null bila sekarang boleh mengirim.
  DateTime? _quietUntil() {
    if (!_settings.getBool(SettingsKeys.quietHoursEnabled)) return null;

    final start = _parseTime(_settings.get(SettingsKeys.quietHoursStart));
    final end = _parseTime(_settings.get(SettingsKeys.quietHoursEnd));
    if (start == null || end == null) return null;

    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;

    // Jam tenang biasanya melewati tengah malam, misalnya 21:00 sampai 08:00.
    final crossesMidnight = start > end;
    final quiet = crossesMidnight
        ? (minutes >= start || minutes < end)
        : (minutes >= start && minutes < end);

    if (!quiet) return null;

    final openToday =
        DateTime(now.year, now.month, now.day, end ~/ 60, end % 60);

    return openToday.isAfter(now)
        ? openToday
        : openToday.add(const Duration(days: 1));
  }

  /// "21:00" menjadi 1260 menit. Null bila formatnya tidak dikenali.
  int? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return hour * 60 + minute;
  }

  // ------------------------------------------------------------------ log

  Future<bool> alreadySent(int orderId, NotificationTrigger trigger) =>
      _alreadySentByName(orderId, trigger.name);

  Future<bool> _alreadySentByName(int orderId, String triggerName) async {
    final db = await _db.database;
    final rows = await db.query(
      'notification_logs',
      where: "order_id = ? AND trigger_name = ? AND status = 'terkirim'",
      whereArgs: [orderId, triggerName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Menandai satu baris antrean sebagai terkirim tanpa melanggar indeks
  /// unik, dan membersihkan baris sisa untuk pemicu yang sama.
  ///
  /// Indeks unik hanya mengizinkan SATU baris terkirim per order dan pemicu.
  /// Kalau sudah ada, baris ini cukup dihapus: pesannya memang sudah sampai.
  Future<void> _markDelivered(
    int id,
    int orderId,
    String trigger, {
    required int attempts,
  }) async {
    final db = await _db.database;

    await db.transaction((txn) async {
      await txn.delete(
        'notification_logs',
        where: "order_id = ? AND trigger_name = ? AND id != ? "
            "AND status IN ('gagal', 'tertunda')",
        whereArgs: [orderId, trigger, id],
      );

      final already = Sqflite.firstIntValue(await txn.rawQuery(
            "SELECT COUNT(*) FROM notification_logs "
            "WHERE order_id = ? AND trigger_name = ? AND status = 'terkirim'",
            [orderId, trigger],
          )) ??
          0;

      if (already > 0) {
        await txn.delete('notification_logs', where: 'id = ?', whereArgs: [id]);
        return;
      }

      await txn.update(
        'notification_logs',
        {
          'status': NotificationState.terkirim.name,
          'sent_at': DateTime.now().toIso8601String(),
          'attempts': attempts,
          'next_attempt_at': null,
          'error': null,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> _record({
    required int orderId,
    required NotificationTrigger trigger,
    required String target,
    required NotificationState state,
    required String message,
    required int attempts,
    DateTime? nextAttemptAt,
    String? error,
  }) async {
    final db = await _db.database;

    final values = {
      'order_id': orderId,
      'trigger_name': trigger.name,
      'target': target,
      'sent_at': DateTime.now().toIso8601String(),
      'status': state.name,
      'error': error,
      'message': message,
      'attempts': attempts,
      'next_attempt_at': nextAttemptAt?.toIso8601String(),
    };

    if (state == NotificationState.terkirim) {
      await db.insert(
        'notification_logs',
        values,
        // Indeks unik: hanya satu baris terkirim per order dan pemicu. Kirim
        // ulang paksa (pengingat berulang) tidak menambah baris.
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      // Pesan sudah sampai, jadi baris gagal atau tertunda yang lebih lama
      // untuk pemicu yang sama tidak lagi perlu dicoba atau ditampilkan.
      await db.delete(
        'notification_logs',
        where: "order_id = ? AND trigger_name = ? "
            "AND status IN ('gagal', 'tertunda')",
        whereArgs: [orderId, trigger.name],
      );
      return;
    }

    // Satu pemicu per order hanya punya SATU baris yang masih menunggu.
    // Tanpa ini, mengetuk kirim tiga kali di luar jam buka membuat tiga baris
    // antrean, dan pelanggan menerima tiga pesan yang sama saat jam buka.
    final pending = await db.query(
      'notification_logs',
      columns: ['id'],
      where: "order_id = ? AND trigger_name = ? "
          "AND status IN ('gagal', 'tertunda')",
      whereArgs: [orderId, trigger.name],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (pending.isNotEmpty) {
      await db.update(
        'notification_logs',
        values,
        where: 'id = ?',
        whereArgs: [pending.first['id']],
      );
      return;
    }

    await db.insert('notification_logs', values);
  }

  /// Riwayat kirim untuk satu order, dipakai di layar detail.
  Future<List<Map<String, Object?>>> historyOf(int orderId) async {
    final db = await _db.database;
    return db.query('notification_logs',
        where: 'order_id = ?', whereArgs: [orderId], orderBy: 'sent_at DESC');
  }

  /// Semua pesan yang belum sampai, untuk dilihat dan dikirim ulang pemilik.
  Future<List<Map<String, Object?>>> failures({int limit = 50}) async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT n.*, o.order_no, c.name AS customer_name, c.phone AS customer_phone
      FROM notification_logs n
      JOIN orders o ON o.id = n.order_id
      JOIN customers c ON c.id = o.customer_id
      WHERE n.status IN ('gagal', 'tertunda')
      ORDER BY n.sent_at DESC
      LIMIT ?
    ''', [limit]);
  }

  /// Kirim ulang satu pesan, dipicu pemilik dari layar log.
  Future<NotificationResult> resend(int logId) async {
    final db = await _db.database;

    final rows = await db.rawQuery('''
      SELECT n.order_id, n.trigger_name, n.attempts, n.message,
             c.phone AS customer_phone
      FROM notification_logs n
      JOIN orders o ON o.id = n.order_id
      JOIN customers c ON c.id = o.customer_id
      WHERE n.id = ?
    ''', [logId]);

    if (rows.isEmpty) {
      return const NotificationResult.failed('Pesan tidak ditemukan.');
    }

    final message = rows.first['message'] as String?;
    final phone = rows.first['customer_phone'] as String? ?? '';

    if (message == null || message.isEmpty || phone.isEmpty) {
      return const NotificationResult.failed(
          'Isi pesan tidak tersimpan. Kirim dari layar detail order.');
    }

    final result = await _sender.send(phone: phone, message: message);

    if (result.sent) {
      // Lewat _markDelivered, bukan UPDATE langsung: pesan yang sama mungkin
      // sudah tercatat terkirim dari jalur lain, dan UPDATE langsung akan
      // melanggar indeks unik lalu memunculkan galat di layar pemilik.
      final attempts = (rows.first['attempts'] as num?)?.toInt() ?? 0;

      await _markDelivered(
        logId,
        rows.first['order_id'] as int,
        rows.first['trigger_name'] as String,
        attempts: attempts + 1,
      );
      return result;
    }

    await db.update(
      'notification_logs',
      {
        'status': NotificationState.gagal.name,
        'sent_at': DateTime.now().toIso8601String(),
        'error': result.message,
        'next_attempt_at': null,
      },
      where: 'id = ?',
      whereArgs: [logId],
    );

    return result;
  }
}
