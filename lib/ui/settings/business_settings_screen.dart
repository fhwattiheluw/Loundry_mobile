import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/db/settings_keys.dart';
import '../widgets/feedback.dart';

/// Profil usaha dan teks yang tercetak di nota.
///
/// Catatan kaki nota adalah teks yang melindungi pemilik saat ada sengketa
/// cucian hilang atau rusak, jadi harus bisa diubah tanpa menunggu rilis baru.
class BusinessSettingsScreen extends ConsumerStatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  ConsumerState<BusinessSettingsScreen> createState() =>
      _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState
    extends ConsumerState<BusinessSettingsScreen> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, String> _initial;
  final _errors = <String, String>{};
  bool _saving = false;

  bool get _dirty => _controllers.entries
      .any((e) => e.value.text.trim() != (_initial[e.key] ?? '').trim());

  static const _fields = <String, (String, String?)>{
    SettingsKeys.businessName: ('Nama usaha', null),
    SettingsKeys.businessAddress: ('Alamat', null),
    SettingsKeys.businessPhone: ('Nomor telepon', null),
    SettingsKeys.openHours: ('Jam operasional', 'Contoh: Buka 08.00 - 20.00'),
    SettingsKeys.receiptFooter: (
      'Catatan kaki nota',
      'Ketentuan klaim dan batas penyimpanan cucian',
    ),
    SettingsKeys.paymentMethods: (
      'Metode pembayaran',
      'Pisahkan dengan koma. Contoh: Tunai,Transfer,QRIS',
    ),
    SettingsKeys.reminderDays: (
      'Pengingat setelah berapa hari',
      'Order selesai yang belum diambil akan ditandai setelah sekian hari',
    ),
    SettingsKeys.maxCashierDiscount: (
      'Batas diskon kasir (Rp)',
      'Diskon di atas ini butuh PIN Owner',
    ),
    SettingsKeys.perfumes: (
      'Pilihan parfum',
      'Pisahkan dengan koma. Kosongkan bila tidak memakai parfum',
    ),
    SettingsKeys.extraFeeLabel: (
      'Nama biaya tambahan',
      'Contoh: Antar-jemput, Kantong khusus',
    ),
  };

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsRepoProvider);
    _initial = {for (final key in _fields.keys) key: settings.get(key)};
    _controllers = {
      for (final key in _fields.keys)
        key: TextEditingController(text: _initial[key]),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Memeriksa isian sebelum disimpan. Nilai yang salah di sini tidak
  /// merusak data, tapi diam-diam mematikan fitur: pengingat 0 hari menandai
  /// semua cucian sebagai menumpuk, dan daftar metode kosong membuat kasir
  /// tidak bisa memilih cara bayar.
  Map<String, String> _validate() {
    final errors = <String, String>{};
    String text(String key) => _controllers[key]!.text.trim();

    if (text(SettingsKeys.businessName).isEmpty) {
      errors[SettingsKeys.businessName] =
          'Nama usaha wajib diisi, karena tercetak di setiap nota';
    }

    if (text(SettingsKeys.paymentMethods)
        .split(',')
        .every((e) => e.trim().isEmpty)) {
      errors[SettingsKeys.paymentMethods] =
          'Isi minimal satu, misalnya Tunai';
    }

    final days = int.tryParse(text(SettingsKeys.reminderDays));
    if (days == null || days < 1 || days > 90) {
      errors[SettingsKeys.reminderDays] = 'Isi angka antara 1 sampai 90';
    }

    final discount = int.tryParse(text(SettingsKeys.maxCashierDiscount));
    if (discount == null || discount < 0) {
      errors[SettingsKeys.maxCashierDiscount] =
          'Isi angka, atau 0 bila kasir tidak boleh memberi diskon';
    }

    return errors;
  }

  Future<void> _save() async {
    final errors = _validate();
    if (errors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
      });
      showToast(context, 'Ada isian yang perlu diperbaiki. Lihat tulisan merah.');
      return;
    }

    setState(() => _saving = true);

    await ref.read(settingsRepoProvider).setAll({
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    });

    ref.invalidate(settingsLoadedProvider);

    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pengaturan disimpan.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      hasChanges: () => _dirty && !_saving,
      child: Scaffold(
      appBar: AppBar(title: const Text('Profil usaha dan nota')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          for (final entry in _fields.entries) ...[
            TextField(
              controller: _controllers[entry.key],
              maxLines: entry.key == SettingsKeys.receiptFooter ? 4 : 1,
              keyboardType: _isNumeric(entry.key)
                  ? TextInputType.number
                  : TextInputType.text,
              textInputAction: entry.key == SettingsKeys.receiptFooter
                  ? TextInputAction.newline
                  : TextInputAction.next,
              onChanged: (_) {
                if (_errors.containsKey(entry.key)) {
                  setState(() => _errors.remove(entry.key));
                }
              },
              decoration: InputDecoration(
                labelText: entry.value.$1,
                helperText: entry.value.$2,
                helperMaxLines: 2,
                errorText: _errors[entry.key],
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: 18),
          ],
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Menyimpan...' : 'Simpan'),
          ),
        ],
      ),
      ),
    );
  }

  bool _isNumeric(String key) =>
      key == SettingsKeys.reminderDays ||
      key == SettingsKeys.maxCashierDiscount;
}
