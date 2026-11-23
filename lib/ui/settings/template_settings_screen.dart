import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/db/default_templates.dart';
import '../../data/db/settings_keys.dart';
import '../../services/notification/message_template.dart';
import '../widgets/layout.dart';

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
  late final Map<String, FocusNode> _focusNodes;

  /// Kolom template yang terakhir disentuh. Tombol variabel menyisipkan ke
  /// sini; ingatannya bertahan walau fokus berpindah ke tombol itu sendiri.
  String? _activeKey;

  static const _templates = <String, String>{
    SettingsKeys.templateOrderCreated: 'Saat order diterima',
    SettingsKeys.templateOrderDone: 'Saat cucian selesai',
    SettingsKeys.templateReminder: 'Pengingat belum diambil',
    SettingsKeys.templatePayment: 'Saat pembayaran diterima',
  };

  /// Isi bawaan tiap template, untuk tombol "Pulihkan bawaan".
  static const _defaults = <String, String>{
    SettingsKeys.templateOrderCreated: DefaultTemplates.orderCreated,
    SettingsKeys.templateOrderDone: DefaultTemplates.orderDone,
    SettingsKeys.templateReminder: DefaultTemplates.reminder,
    SettingsKeys.templatePayment: DefaultTemplates.payment,
  };

  static const _toggles = <String, String>{
    SettingsKeys.notifyOrderCreated: 'Kirim saat order diterima',
    SettingsKeys.notifyOrderDone: 'Kirim saat cucian selesai',
    SettingsKeys.notifyReminder: 'Kirim pengingat pengambilan',
    SettingsKeys.notifyPaymentReceived: 'Kirim saat pembayaran diterima',
  };

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsRepoProvider);
    _controllers = {
      for (final key in _templates.keys)
        key: TextEditingController(text: settings.get(key)),
    };
    _focusNodes = {
      for (final key in _templates.keys)
        key: FocusNode()
          ..addListener(() {
            if (_focusNodes[key]?.hasFocus ?? false) _activeKey = key;
          }),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _warn(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Menyisipkan variabel di posisi kursor kolom yang terakhir disentuh.
  /// Mengetik kurung kurawal dan ejaan variabel dengan benar di keyboard HP
  /// itu lambat dan gampang salah.
  void _insert(String variable) {
    final key = _activeKey;
    if (key == null) {
      _warn('Ketuk dulu di dalam kolom template, baru pilih variabelnya.');
      return;
    }

    final controller = _controllers[key]!;
    final text = controller.text;
    final selection = controller.selection;

    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;

    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, variable),
      selection: TextSelection.collapsed(offset: start + variable.length),
    );
    _focusNodes[key]!.requestFocus();
  }

  /// Menampilkan pesan yang akan diterima pelanggan, dengan order rekaan.
  void _preview(String key) {
    final message = MessageTemplate(ref.read(settingsRepoProvider))
        .render(_controllers[key]!.text, MessageTemplate.sampleOrder());

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Contoh: ${_templates[key]}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nama, layanan, dan harga di bawah ini rekaan.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SelectableText(message),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // Template kosong terkirim sebagai pesan kosong, dan variabel yang salah
    // ketik terkirim apa adanya ("Halo {nama_pelanggan}"). Keduanya baru
    // ketahuan setelah pelanggan menerimanya, jadi ditolak di sini.
    for (final entry in _controllers.entries) {
      final label = _templates[entry.key]!;
      final text = entry.value.text.trim();

      if (text.isEmpty) {
        _warn('Template "$label" masih kosong. Isi, atau ketuk Pulihkan '
            'bawaan.');
        return;
      }

      final unknown = MessageTemplate.unknownVariables(text);
      if (unknown.isNotEmpty) {
        _warn('Template "$label" memuat ${unknown.join(', ')} yang tidak '
            'dikenal. Periksa ejaannya, atau pilih dari daftar variabel.');
        return;
      }
    }

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
      body: ContentWidth(
        child: ListView(
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
                    Text(
                      settings.get(SettingsKeys.whatsappMode,
                                  fallback: 'manual') ==
                              'api'
                          ? 'Pesan dikirim otomatis lewat WhatsApp Cloud API, '
                              'tanpa membuka WhatsApp. Pengiriman diatur di '
                              'Pengaturan, Pengiriman WhatsApp.'
                          : 'Aplikasi membuka WhatsApp dengan pesan sudah '
                              'terisi, kasir tinggal menekan tombol kirim. Cara '
                              'ini gratis dan tidak berisiko memblokir nomor '
                              'usaha Anda.',
                      style: const TextStyle(fontSize: 13),
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
                value: settings.getBool(
                  entry.key,
                  fallback: entry.key != SettingsKeys.notifyPaymentReceived,
                ),
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
                    const SizedBox(height: 6),
                    const Text(
                      'Ketuk di kolom template, lalu ketuk variabel untuk '
                      'menyisipkannya. {rincian} memuat tiap item dengan '
                      'jumlah, satuan, harga, dan subtotalnya. {ringkasan} '
                      'memuat subtotal, diskon, total, sudah dibayar, dan sisa '
                      'tagihan.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final variable in MessageTemplate.variables)
                          ActionChip(
                            label: Text(variable,
                                style: const TextStyle(fontSize: 11.5)),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _insert(variable),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            for (final entry in _templates.entries) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(entry.value,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Lihat contoh pesan',
                    icon: const Icon(Icons.visibility_outlined),
                    onPressed: () => _preview(entry.key),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _controllers[entry.key]!.text = _defaults[entry.key]!;
                    }),
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Pulihkan bawaan'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controllers[entry.key],
                focusNode: _focusNodes[entry.key],
                minLines: 8,
                maxLines: 20,
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
      ),
    );
  }
}
