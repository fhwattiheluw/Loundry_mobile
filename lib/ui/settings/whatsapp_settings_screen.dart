import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/db/settings_keys.dart';

/// Pilihan mode pengiriman WhatsApp dan jam tenang (FR-66, FR-67, FR-72).
class WhatsAppSettingsScreen extends ConsumerStatefulWidget {
  const WhatsAppSettingsScreen({super.key});

  @override
  ConsumerState<WhatsAppSettingsScreen> createState() =>
      _WhatsAppSettingsScreenState();
}

class _WhatsAppSettingsScreenState
    extends ConsumerState<WhatsAppSettingsScreen> {
  late final TextEditingController _phoneId;
  late final TextEditingController _token;
  late final TextEditingController _templateName;
  late final TextEditingController _apiVersion;
  late final TextEditingController _quietStart;
  late final TextEditingController _quietEnd;

  late String _mode;
  late bool _quietEnabled;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsRepoProvider);

    _mode = s.get(SettingsKeys.whatsappMode, fallback: 'manual');
    _quietEnabled = s.getBool(SettingsKeys.quietHoursEnabled);

    _phoneId =
        TextEditingController(text: s.get(SettingsKeys.whatsappPhoneNumberId));
    _token = TextEditingController(text: s.get(SettingsKeys.whatsappToken));
    _templateName =
        TextEditingController(text: s.get(SettingsKeys.whatsappTemplateName));
    _apiVersion = TextEditingController(
        text: s.get(SettingsKeys.whatsappApiVersion, fallback: 'v21.0'));
    _quietStart = TextEditingController(
        text: s.get(SettingsKeys.quietHoursStart, fallback: '21:00'));
    _quietEnd = TextEditingController(
        text: s.get(SettingsKeys.quietHoursEnd, fallback: '08:00'));
  }

  @override
  void dispose() {
    for (final c in [
      _phoneId,
      _token,
      _templateName,
      _apiVersion,
      _quietStart,
      _quietEnd,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_mode == 'api' &&
        (_phoneId.text.trim().isEmpty || _token.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mode API butuh Phone Number ID dan token.'),
        ),
      );
      return;
    }

    await ref.read(settingsRepoProvider).setAll({
      SettingsKeys.whatsappMode: _mode,
      SettingsKeys.whatsappPhoneNumberId: _phoneId.text.trim(),
      SettingsKeys.whatsappToken: _token.text.trim(),
      SettingsKeys.whatsappTemplateName: _templateName.text.trim(),
      SettingsKeys.whatsappApiVersion: _apiVersion.text.trim(),
      SettingsKeys.quietHoursEnabled: _quietEnabled ? '1' : '0',
      SettingsKeys.quietHoursStart: _quietStart.text.trim(),
      SettingsKeys.quietHoursEnd: _quietEnd.text.trim(),
    });

    ref.invalidate(settingsLoadedProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pengaturan WhatsApp disimpan.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengiriman WhatsApp')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text('Mode pengiriman',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          RadioGroup<String>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v ?? _mode),
            child: const Column(
              children: [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'manual',
                  title: Text('Manual (disarankan)'),
                  subtitle: Text(
                    'Aplikasi membuka WhatsApp dengan pesan sudah terisi, '
                    'kasir menekan kirim. Gratis, tanpa server, dan nomor '
                    'usaha aman.',
                  ),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'api',
                  title: Text('Otomatis lewat WhatsApp Cloud API'),
                  subtitle: Text(
                    'Terkirim sendiri tanpa membuka WhatsApp. Berbayar per '
                    'percakapan dan butuh verifikasi bisnis di Meta.',
                  ),
                ),
              ],
            ),
          ),

          if (_mode == 'api') ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Sebelum mengaktifkan: nomor harus didaftarkan ke Cloud API '
                  'dan tidak boleh nomor WhatsApp biasa yang sedang aktif di '
                  'ponsel. Pesan yang dimulai bisnis juga wajib memakai '
                  'template yang sudah disetujui Meta.\n\n'
                  'Jangan memakai gateway tidak resmi yang membajak sesi '
                  'WhatsApp pribadi: melanggar ketentuan layanan dan berisiko '
                  'nomor diblokir permanen.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneId,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Phone Number ID',
                helperText: 'Dari dasbor Meta for Developers',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _token,
              obscureText: !_showToken,
              decoration: InputDecoration(
                labelText: 'Access token',
                helperText: 'Token permanen, bukan token sementara 24 jam',
                suffixIcon: IconButton(
                  icon: Icon(
                      _showToken ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _templateName,
              decoration: const InputDecoration(
                labelText: 'Nama template (opsional)',
                helperText: 'Kosongkan untuk teks biasa, hanya berhasil dalam '
                    '24 jam setelah pelanggan membalas',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _apiVersion,
              decoration: const InputDecoration(labelText: 'Versi API'),
            ),
          ],

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _quietEnabled,
            onChanged: (v) => setState(() => _quietEnabled = v),
            title: const Text('Jam tenang'),
            subtitle: const Text(
              'Pesan di luar jam operasional ditunda, bukan dibuang, dan '
              'dikirim saat jam buka berikutnya.',
            ),
          ),

          if (_quietEnabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quietStart,
                    decoration: const InputDecoration(
                      labelText: 'Mulai tenang',
                      hintText: '21:00',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _quietEnd,
                    decoration: const InputDecoration(
                      labelText: 'Selesai tenang',
                      hintText: '08:00',
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
