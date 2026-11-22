import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system.dart';
import '../../application/providers.dart';
import '../../core/security.dart';
import '../../data/db/settings_keys.dart';
import '../../domain/models/models.dart';

/// Kirim pesan promo ke pelanggan terpilih (FR-64).
///
/// Di mode manual, setiap pesan membuka WhatsApp satu per satu dan kasir
/// menekan kirim. Itu memang lambat, tapi inilah satu-satunya cara yang
/// tidak berisiko memblokir nomor usaha.
///
/// Pelanggan yang mematikan notifikasi tidak pernah muncul di daftar ini.
class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key});

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen> {
  final _messageController = TextEditingController();
  final _selected = <int>{};
  final _sent = <int>{};

  List<Customer> _targets = const [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await ref.read(customerRepoProvider).broadcastTargets();
    if (mounted) {
      setState(() {
        _targets = rows;
        _loading = false;
      });
    }
  }

  String _render(Customer customer) {
    final businessName =
        ref.read(settingsRepoProvider).get(SettingsKeys.businessName);

    return _messageController.text
        .replaceAll('{nama}', customer.name)
        .replaceAll('{nama_usaha}', businessName)
        .trim();
  }

  Future<void> _sendTo(Customer customer) async {
    final messenger = ScaffoldMessenger.of(context);
    final sender = ref.read(broadcastSenderProvider);

    final result = await sender.send(
      phone: customer.phone,
      message: _render(customer),
    );

    if (!mounted) return;

    if (result.sent) {
      setState(() => _sent.add(customer.id!));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  /// Kirim berurutan ke semua yang dipilih. Hanya masuk akal di mode API,
  /// karena mode manual membuka layar WhatsApp tiap pesan.
  Future<void> _sendAll() async {
    setState(() => _sending = true);

    for (final customer in _targets) {
      if (!_selected.contains(customer.id)) continue;
      if (_sent.contains(customer.id)) continue;

      await _sendTo(customer);

      // Jeda kecil supaya pengiriman tidak terlihat seperti spam otomatis
      // dan tidak menabrak batas laju Cloud API.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
    }

    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final isApiMode = ref.watch(notificationServiceProvider).isApiMode;
    final ready = _messageController.text.trim().isNotEmpty &&
        _selected.isNotEmpty &&
        !_sending;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kirim Promo'),
        actions: [
          TextButton(
            onPressed: _targets.isEmpty
                ? null
                : () => setState(() {
                      if (_selected.length == _targets.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(_targets.map((c) => c.id!));
                      }
                    }),
            child: Text(
              _selected.length == _targets.length ? 'Hapus pilihan' : 'Pilih semua',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _messageController,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Isi pesan promo',
                    hintText:
                        'Halo {nama}, ada diskon 20% untuk cuci kiloan minggu ini!',
                    helperText: 'Bisa memakai {nama} dan {nama_usaha}',
                  ),
                ),
                const SizedBox(height: 10),
                if (!isApiMode)
                  Text(
                    'Mode manual: WhatsApp terbuka satu per satu dan Anda '
                    'menekan kirim sendiri. Cara ini aman untuk nomor usaha.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _targets.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Belum ada pelanggan yang bisa dikirimi pesan. '
                            'Pelanggan perlu punya nomor WhatsApp dan '
                            'mengizinkan notifikasi.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _targets.length,
                        itemBuilder: (context, i) {
                          final customer = _targets[i];
                          final done = _sent.contains(customer.id);

                          return CheckboxListTile(
                            value: _selected.contains(customer.id),
                            onChanged: done
                                ? null
                                : (checked) => setState(() {
                                      if (checked == true) {
                                        _selected.add(customer.id!);
                                      } else {
                                        _selected.remove(customer.id);
                                      }
                                    }),
                            title: Text(customer.name),
                            subtitle: Text(
                              done
                                  ? 'Sudah dikirim'
                                  : prettyPhone(customer.phone),
                            ),
                            secondary: done
                                ? const Icon(Icons.check_circle,
                                    color: context.status.lunas)
                                : IconButton(
                                    tooltip: 'Kirim ke pelanggan ini',
                                    icon: const Icon(Icons.send),
                                    onPressed:
                                        _messageController.text.trim().isEmpty
                                            ? null
                                            : () => _sendTo(customer),
                                  ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: ready ? _sendAll : null,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.campaign_outlined),
            label: Text(
              _sending
                  ? 'Mengirim...'
                  : 'Kirim ke ${_selected.length} pelanggan',
            ),
          ),
        ),
      ),
    );
  }
}
