import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../domain/models/enums.dart';

/// Pesan yang belum sampai ke pelanggan, beserta tombol kirim ulang (FR-68).
///
/// Di mode manual, kirim ulang membuka WhatsApp seperti biasa. Di mode API,
/// aplikasi sudah mencoba sendiri sampai tiga kali; yang muncul di sini
/// berarti sudah menyerah atau masih menunggu giliran.
class NotificationLogScreen extends ConsumerStatefulWidget {
  const NotificationLogScreen({super.key});

  @override
  ConsumerState<NotificationLogScreen> createState() =>
      _NotificationLogScreenState();
}

class _NotificationLogScreenState
    extends ConsumerState<NotificationLogScreen> {
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(notificationServiceProvider).failures();
    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  Future<void> _resend(int id) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(notificationServiceProvider).resend(id);

    await _load();
    ref.invalidate(pendingNotificationsProvider);

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.sent ? 'Pesan terkirim.' : result.message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesan Belum Terkirim'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mark_chat_read_outlined,
                            size: 48, color: Color(0xFF2E7D32)),
                        SizedBox(height: 16),
                        Text(
                          'Semua pesan sudah terkirim.',
                          style: TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = _rows[i];
                    final pending = row['status'] == 'tertunda';
                    final attempts = (row['attempts'] as num?)?.toInt() ?? 0;
                    final nextAt = row['next_attempt_at'] as String?;

                    return ListTile(
                      leading: Icon(
                        pending ? Icons.schedule : Icons.error_outline,
                        color: pending
                            ? scheme.primary
                            : const Color(0xFFC62828),
                      ),
                      title: Text(
                        '${row['order_no']}  ${row['customer_name']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${NotificationTrigger.fromDb(row['trigger_name'] as String).label}'
                        ' · percobaan $attempts\n'
                        '${formatDateTime(DateTime.parse(row['sent_at'] as String))}'
                        '${nextAt != null ? '\nDicoba lagi ${formatDateTime(DateTime.parse(nextAt))}' : ''}'
                        '${row['error'] != null ? '\n${row['error']}' : ''}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Kirim ulang sekarang',
                        icon: const Icon(Icons.send),
                        onPressed: () => _resend(row['id'] as int),
                      ),
                    );
                  },
                ),
    );
  }
}
