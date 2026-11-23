import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/db/settings_keys.dart';
import '../../services/notification/whatsapp_api_sender.dart';

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

  void _warn(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Membuka pemilih jam. Mengetik "9" atau "21.00" dulu membuat jam tenang
  /// mati diam-diam karena formatnya tidak dikenali; pemilih jam tidak bisa
  /// menghasilkan format yang salah.
  Future<void> _pickTime(TextEditingController controller, String help) async {
    final parts = controller.text.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: help,
    );
    if (picked == null || !mounted) return;

    setState(() {
      controller.text = '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _save() async {
    if (_mode == 'api' &&
        (_phoneId.text.trim().isEmpty || _token.text.trim().isEmpty)) {
      _warn('Mode API butuh Phone Number ID dan token.');
      return;
    }

    final version = WhatsAppApiSender.normalizeApiVersion(_apiVersion.text);
    if (version == null) {
      _warn('Versi API harus berbentuk seperti v21.0.');
      return;
    }

    // Meta hanya menerima huruf kecil, angka, dan garis bawah pada nama
    // template. Salah huruf di sini baru ketahuan saat pesan pertama ditolak.
    final templateName = _templateName.text.trim();
    if (templateName.isNotEmpty &&
        !RegExp(r'^[a-z0-9_]+$').hasMatch(templateName)) {
      _warn('Nama template hanya boleh huruf kecil, angka, dan garis bawah, '
          'misalnya nota_laundry.');
      return;
    }

    await ref.read(settingsRepoProvider).setAll({
      SettingsKeys.whatsappMode: _mode,
      SettingsKeys.whatsappPhoneNumberId: _phoneId.text.trim(),
      SettingsKeys.whatsappToken: _token.text.trim(),
      SettingsKeys.whatsappTemplateName: templateName,
      SettingsKeys.whatsappApiVersion: version,
      SettingsKeys.quietHoursEnabled: _quietEnabled ? '1' : '0',
      SettingsKeys.quietHoursStart: _quietStart.text.trim(),
      SettingsKeys.quietHoursEnd: _quietEnd.text.trim(),
    });

    ref.invalidate(settingsLoadedProvider);

    if (!mounted) return;
    _warn('Pengaturan WhatsApp disimpan.');
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
                  tooltip: _showToken ? 'Sembunyikan token' : 'Tampilkan token',
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
                    '24 jam setelah pelanggan membalas. Dengan template, '
                    'isi pesan disatukan menjadi satu baris karena Meta '
                    'melarang baris baru di dalam template.',
                helperMaxLines: 5,
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
            subtitle: Text(
              _mode == 'api'
                  ? 'Pesan otomatis di luar jam operasional ditunda, bukan '
                      'dibuang, dan dikirim saat jam buka berikutnya.'
                  : 'Hanya berlaku di mode otomatis. Di mode manual kasir '
                      'sendiri yang menekan kirim, jadi tidak ada pesan yang '
                      'ditahan.',
            ),
          ),

          if (_quietEnabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quietStart,
                    readOnly: true,
                    onTap: () => _pickTime(_quietStart, 'Mulai jam tenang'),
                    decoration: const InputDecoration(
                      labelText: 'Mulai tenang',
                      suffixIcon: Icon(Icons.schedule),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _quietEnd,
                    readOnly: true,
                    onTap: () => _pickTime(_quietEnd, 'Selesai jam tenang'),
                    decoration: const InputDecoration(
                      labelText: 'Selesai tenang',
                      suffixIcon: Icon(Icons.schedule),
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
