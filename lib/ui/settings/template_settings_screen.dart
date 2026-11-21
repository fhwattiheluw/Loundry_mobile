import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/db/settings_keys.dart';

/// Template pesan WhatsApp yang bisa diubah pemilik (FR-65).
class TemplateSettingsScreen extends ConsumerStatefulWidget {
  const TemplateSettingsScreen({super.key});

  @override
  ConsumerState<TemplateSettingsScreen> createState() =>
      _TemplateSettingsScreenState();
}

class _TemplateSettingsScreenState
    extends ConsumerState<TemplateSettingsScreen> {
  late final Map<String, TextEditingController> _controllers;

  static const _templates = <String, String>{
    SettingsKeys.templateOrderCreated: 'Saat order diterima',
    SettingsKeys.templateOrderDone: 'Saat cucian selesai',
    SettingsKeys.templateReminder: 'Pengingat belum diambil',
  };

  static const _toggles = <String, String>{
    SettingsKeys.notifyOrderCreated: 'Kirim saat order diterima',
    SettingsKeys.notifyOrderDone: 'Kirim saat cucian selesai',
    SettingsKeys.notifyReminder: 'Kirim pengingat pengambilan',
  };

  static const _variables = [
    '{nama}',
    '{no_order}',
    '{layanan}',
    '{total}',
    '{dibayar}',
    '{sisa}',
    '{status_bayar}',
    '{estimasi}',
    '{tanggal}',
    '{nama_usaha}',
    '{jam_buka}',
  ];

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsRepoProvider);
    _controllers = {
      for (final key in _templates.keys)
        key: TextEditingController(text: settings.get(key)),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(settingsRepoProvider).setAll({
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    });

    ref.invalidate(settingsLoadedProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Template disimpan.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsRepoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Template WhatsApp')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cara kerja pengiriman',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text(
                    'Aplikasi membuka WhatsApp dengan pesan sudah terisi, '
                    'kasir tinggal menekan tombol kirim. Cara ini gratis dan '
                    'tidak berisiko memblokir nomor usaha Anda.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          for (final entry in _toggles.entries)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value),
              value: settings.getBool(entry.key, fallback: true),
              onChanged: (value) async {
                await settings.set(entry.key, value ? '1' : '0');
                ref.invalidate(settingsLoadedProvider);
                setState(() {});
              },
            ),

          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Variabel yang bisa dipakai',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final variable in _variables)
                        Chip(
                          label: Text(variable,
                              style: const TextStyle(fontSize: 11.5)),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          for (final entry in _templates.entries) ...[
            Text(entry.value,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _controllers[entry.key],
              maxLines: 7,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
          ],

          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan template'),
          ),
        ],
      ),
    );
  }
}
