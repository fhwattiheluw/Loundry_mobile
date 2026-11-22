import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../data/db/settings_keys.dart';
import '../../domain/models/models.dart';
import '../settings/printer_settings_screen.dart';
import '../widgets/app_logo.dart';

/// Empat langkah yang harus dilewati toko baru sebelum melayani pelanggan.
///
/// Tanpa layar ini, toko baru mendarat di dashboard bernama "Laundry Saya"
/// dengan harga contoh, dan sebagian besar pemilik tidak akan pernah
/// menemukan Pengaturan sendiri. Mereka akan memakainya dengan harga yang
/// salah selama berminggu-minggu, lalu menyalahkan aplikasinya.
///
/// Tiap langkah bisa dilewati kecuali yang pertama. Memaksa orang mengisi
/// semuanya di menit pertama adalah cara lain untuk kehilangan mereka.
class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});

  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  final _page = PageController();
  int _index = 0;
  bool _saving = false;

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  String? _pinError;

  /// Harga yang sedang diketik, dikunci pada id layanan.
  final _prices = <int, TextEditingController>{};

  @override
  void dispose() {
    _page.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _next() async {
    if (_saving) return;

    final ok = await _saveCurrentStep();
    if (!ok || !mounted) return;

    if (_index >= 3) {
      await _finish();
      return;
    }

    setState(() => _index++);
    _page.animateToPage(
      _index,
      duration: AppDuration.normal,
      curve: Curves.easeOut,
    );
  }

  /// Menyimpan langkah yang sedang terbuka. Mengembalikan false bila ada
  /// isian yang belum sah, supaya wizard tidak maju.
  Future<bool> _saveCurrentStep() async {
    final settings = ref.read(settingsRepoProvider);

    switch (_index) {
      case 0:
        final name = _nameController.text.trim();
        if (name.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nama usaha wajib diisi.')),
          );
          return false;
        }
        await settings.setAll({
          SettingsKeys.businessName: name,
          SettingsKeys.businessAddress: _addressController.text.trim(),
          SettingsKeys.businessPhone: _phoneController.text.trim(),
        });
        ref.invalidate(settingsLoadedProvider);
        return true;

      case 1:
        final services = await ref.read(servicesProvider.future);
        final repo = ref.read(serviceRepoProvider);

        for (final service in services) {
          final text = _prices[service.id]?.text;
          if (text == null) continue;

          final price = parseRupiah(text);
          if (price <= 0 || price == service.price) continue;

          await repo.update(LaundryService(
            id: service.id,
            name: service.name,
            unit: service.unit,
            price: price,
            durationHours: service.durationHours,
            minQty: service.minQty,
            roundingStep: service.roundingStep,
            expressMultiplier: service.expressMultiplier,
            expressDurationHours: service.expressDurationHours,
            active: service.active,
          ));
        }
        ref.invalidate(servicesProvider);
        return true;

      case 2:
        final pin = _pinController.text;
        if (pin.isEmpty) return true; // Dilewati, PIN lama tetap berlaku.

        if (pin.length < 4) {
          setState(() => _pinError = 'PIN minimal 4 angka.');
          return false;
        }
        if (pin != _pinConfirmController.text) {
          setState(() => _pinError = 'Dua isian PIN berbeda.');
          return false;
        }

        final user = ref.read(currentUserProvider);
        await ref.read(userRepoProvider).setPin(user.id!, pin);
        setState(() => _pinError = null);
        return true;

      default:
        return true;
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    await ref
        .read(settingsRepoProvider)
        .set(SettingsKeys.setupDone, '1');
    ref.invalidate(settingsLoadedProvider);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Container(
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: i <= _index
                              ? scheme.primary
                              : scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _stepBusiness(),
                  _stepPrices(),
                  _stepPin(),
                  _stepPrinter(),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  if (_index > 0)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () {
                              setState(() => _index--);
                              _page.animateToPage(
                                _index,
                                duration: AppDuration.normal,
                                curve: Curves.easeOut,
                              );
                            },
                      child: const Text('Kembali'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _saving ? null : _next,
                    icon: Icon(_index >= 3 ? Icons.check : Icons.arrow_forward),
                    label: Text(_index >= 3 ? 'Mulai pakai' : 'Lanjut'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrap({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.sm),
        Text(title,
            style:
                const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        ...children,
      ],
    );
  }

  Widget _stepBusiness() {
    return _wrap(
      title: 'Nama laundry Anda',
      subtitle: 'Ini yang tercetak di nota dan terkirim ke WhatsApp '
          'pelanggan. Bisa diubah kapan saja nanti.',
      children: [
        const Center(child: AnimatedAppLogo(size: 72)),
        const SizedBox(height: AppSpacing.xl),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama usaha',
            hintText: 'Contoh: Laundry Manise Ambon',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _addressController,
          decoration: const InputDecoration(
            labelText: 'Alamat (boleh dikosongkan)',
            prefixIcon: Icon(Icons.place_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Nomor telepon (boleh dikosongkan)',
            prefixIcon: Icon(Icons.call_outlined),
          ),
        ),
      ],
    );
  }

  Widget _stepPrices() {
    final services = ref.watch(servicesProvider);

    return services.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Gagal memuat layanan: $e')),
      data: (list) {
        for (final service in list) {
          _prices.putIfAbsent(
            service.id!,
            () => TextEditingController(text: formatPlain(service.price)),
          );
        }

        return _wrap(
          title: 'Harga Anda',
          subtitle: 'Angka di bawah ini hanya contoh. Ganti dengan harga '
              'laundry Anda sekarang, supaya nota pertama sudah benar.',
          children: [
            for (final service in list) ...[
              TextField(
                controller: _prices[service.id],
                keyboardType: TextInputType.number,
                inputFormatters: rupiahInputFormatters,
                decoration: InputDecoration(
                  labelText: '${service.name} (per ${service.unit.label})',
                  prefixText: 'Rp ',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              'Minimum berat, pembulatan, dan tarif express diatur nanti '
              'di Pengaturan. Layanan yang tidak Anda jual bisa dimatikan '
              'di sana.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  Widget _stepPin() {
    return _wrap(
      title: 'Ganti PIN Anda',
      subtitle: 'PIN bawaan 1234 dipakai semua orang yang memasang aplikasi '
          'ini. Selama belum diganti, siapa pun yang memegang HP Anda bisa '
          'membuka laporan pendapatan.',
      children: [
        TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'PIN baru',
            helperText: '4 sampai 6 angka',
            counterText: '',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _pinConfirmController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: 'Ulangi PIN baru',
            counterText: '',
            errorText: _pinError,
            prefixIcon: const Icon(Icons.lock_reset),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Dikosongkan berarti PIN tetap 1234, dan bisa diganti nanti di '
          'Pengaturan. Tapi jangan lama-lama.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _stepPrinter() {
    return _wrap(
      title: 'Printer nota',
      subtitle: 'Kalau printer Bluetooth Anda sudah menyala, hubungkan '
          'sekarang. Kalau belum ada, lewati saja — nota tetap bisa '
          'dikirim lewat WhatsApp.',
      children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
          ),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Hubungkan printer'),
        ),
        const SizedBox(height: AppSpacing.xl),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Setelah ini',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.sm),
                const Text('1. Buka shift dan masukkan kas awal di laci'),
                const Text('2. Tekan Order Baru saat pelanggan datang'),
                const Text('3. Backup seminggu sekali, simpan di luar HP'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
