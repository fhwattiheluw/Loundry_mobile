import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../core/security.dart';
import '../../data/db/settings_keys.dart';
import '../../domain/models/models.dart';
import '../backup/backup_folder_card.dart';
import '../settings/printer_settings_screen.dart';
import '../widgets/app_logo.dart';
import '../widgets/layout.dart';
import '../../core/friendly_error.dart';
import '../widgets/states.dart';

/// Lima langkah yang harus dilewati toko baru sebelum melayani pelanggan:
/// nama usaha, harga, printer, backup, lalu PIN.
///
/// Pada pemasangan baru wizard ini muncul SEBELUM layar masuk, karena
/// pemilik belum punya PIN. Urusan toko dulu, PIN dibuat paling akhir. Pada
/// pemasangan lama yang belum menyelesaikannya, wizard muncul sesudah masuk
/// dan langkah PIN boleh dikosongkan.
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
  static const _lastIndex = 4;

  int _index = 0;
  bool _saving = false;

  /// Hasil permintaan izin notifikasi di langkah terakhir. Null: belum diminta.
  bool? _reminderAllowed;

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  String? _pinError;

  /// Harga yang sedang diketik, dikunci pada id layanan.
  final _prices = <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();

    // Wizard yang terputus di tengah (aplikasi ditutup) dimulai lagi dari
    // awal; isian yang sudah tersimpan jangan sampai terlihat hilang.
    final settings = ref.read(settingsRepoProvider);
    final name = settings.get(SettingsKeys.businessName);
    final address = settings.get(SettingsKeys.businessAddress);

    if (name != 'Laundry Saya') _nameController.text = name;
    if (address != 'Jl. Contoh No. 1') _addressController.text = address;
    _phoneController.text = settings.get(SettingsKeys.businessPhone);
  }

  /// Benar selama pemilik belum punya PIN. Dibaca dari database lewat
  /// [firstRunProvider], jadi tidak mungkin berselisih dengan keadaan PIN.
  bool get _firstRun => ref.read(firstRunProvider).valueOrNull ?? false;

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

    if (_index >= _lastIndex) {
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

      case 4:
        final pin = _pinController.text;

        if (pin.isEmpty) {
          if (!_firstRun) return true; // Dilewati, PIN lama tetap berlaku.

          setState(() => _pinError = 'Buat PIN dulu untuk mulai memakai.');
          return false;
        }

        if (pin.length < 4) {
          setState(() => _pinError = 'PIN minimal 4 angka.');
          return false;
        }
        if (isWeakPin(pin)) {
          setState(() => _pinError =
              'PIN ini terlalu mudah ditebak. Hindari 1234, 0000, atau '
              'angka berurutan.');
          return false;
        }
        if (pin != _pinConfirmController.text) {
          setState(() => _pinError = 'Dua isian PIN berbeda.');
          return false;
        }

        // Baru disimpan di _finish, bersama kode pemulihan, supaya wizard
        // yang terputus tidak meninggalkan PIN tanpa kode pemulihan.
        setState(() => _pinError = null);
        return true;

      default:
        return true;
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);

    final firstRun = _firstRun;
    final users = ref.read(userRepoProvider);
    final pin = _pinController.text;
    AppUser? owner;

    try {
      if (firstRun) {
        owner = await users.createFirstOwnerPin(pin);
      } else if (pin.isNotEmpty) {
        await users.setPin(ref.read(currentUserProvider).id!, pin);
      }

      // Kode pemulihan dibuat di akhir wizard, bukan saat PIN diganti:
      // pemilik yang melewati langkah PIN pun tetap harus punya jalan masuk
      // kembali bila suatu hari ia terkunci di luar.
      final code = await ref.read(pinRecoveryProvider).generateRecoveryCode();

      await ref.read(settingsRepoProvider).set(SettingsKeys.setupDone, '1');

      if (mounted) await _showRecoveryCode(code);
    } catch (e) {
      // PIN mungkin sudah tersimpan sebelum galat; baca ulang keadaan
      // sebenarnya supaya aplikasi tidak macet di wizard.
      ref.invalidate(firstRunProvider);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Belum selesai. ${friendlyError(e)}')),
        );
      }
      return;
    }

    // Pemilik yang baru saja membuat PIN langsung masuk; menyuruhnya
    // mengetik PIN yang detik tadi ia buat hanya membuang waktu.
    if (owner != null) ref.read(sessionProvider.notifier).signIn(owner);

    ref.invalidate(firstRunProvider);
    ref.invalidate(settingsLoadedProvider);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _showRecoveryCode(String code) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.key_outlined),
        title: const Text('Catat kode pemulihan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kode ini satu-satunya jalan masuk kembali bila Anda lupa '
              'PIN pemilik. Tulis di buku, atau simpan di tempat yang '
              'hanya Anda tahu.',
            ),
            const SizedBox(height: AppSpacing.lg),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Kode ini tidak bisa dilihat lagi setelah layar ini ditutup. '
              'Kalau hilang, buat yang baru di Pengaturan.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kode disalin.')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Salin'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Saya sudah mencatat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: ContentWidth(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
                child: Row(
                  children: [
                    for (var i = 0; i <= _lastIndex; i++)
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
                    _stepPrinter(),
                    _stepBackup(),
                    _stepPin(),
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
                      icon: Icon(
                          _index >= _lastIndex ? Icons.check : Icons.arrow_forward),
                      label: Text(_index >= _lastIndex ? 'Mulai pakai' : 'Lanjut'),
                    ),
                  ],
                ),
              ),
            ],
          ),
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

  Future<void> _enableReminder() async {
    final allowed = await ref.read(backupReminderProvider).requestPermission();
    if (mounted) setState(() => _reminderAllowed = allowed);
  }

  Widget _stepBackup() {
    final scheme = Theme.of(context).colorScheme;

    return _wrap(
      title: 'Jaga data Anda',
      subtitle: 'Data order dan piutang hanya tersimpan di HP ini. Kalau HP '
          'hilang atau rusak, semuanya ikut hilang kecuali Anda punya '
          'backup.',
      children: [
        const Card(
          child: ListTile(
            leading: IconBadge(Icons.notifications_active_outlined, tone: 2),
            title: Text('Pengingat backup tiap minggu'),
            subtitle: Text(
              'Aplikasi mengirim notifikasi seminggu sekali agar Anda '
              'membuat backup. Backup bisa dibagikan ke WhatsApp pribadi, '
              'email, atau disimpan di HP.',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_reminderAllowed == true)
          Card(
            color: scheme.primaryContainer,
            child: const ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Pengingat aktif'),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _enableReminder,
            icon: const Icon(Icons.notifications_outlined),
            label: Text(
              _reminderAllowed == false
                  ? 'Izin ditolak, coba lagi'
                  : 'Izinkan notifikasi',
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        // Dipilih sejak hari pertama: backup otomatis harian yang tersimpan
        // di Download tetap ada walau aplikasi suatu saat dicopot.
        const BackupFolderCard(),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Anda bisa membuat backup pertama kapan saja lewat Pengaturan, '
          'Backup dan Restore, atau lewat wizard backup di Beranda saat '
          'pengingat muncul.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
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
      error: (e, _) => ErrorState(
        title: 'Layanan belum bisa dimuat',
        message: friendlyError(e),
        onRetry: () => ref.invalidate(servicesProvider),
      ),
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
    final firstRun = ref.watch(firstRunProvider).valueOrNull ?? false;

    return _wrap(
      title: firstRun ? 'Buat PIN aplikasi' : 'Ganti PIN Anda',
      subtitle: firstRun
          ? 'Langkah terakhir. PIN dipakai setiap kali membuka aplikasi dan '
              'melindungi laporan pendapatan dari siapa pun yang memegang HP '
              'Anda. Pilih angka yang mudah Anda ingat tapi tidak mudah '
              'ditebak.'
          : 'Isi bila ingin mengganti PIN sekarang. Dikosongkan berarti PIN '
              'lama tetap berlaku.',
      children: [
        TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'PIN',
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
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          decoration: InputDecoration(
            labelText: 'Ulangi PIN',
            counterText: '',
            errorText: _pinError,
            prefixIcon: const Icon(Icons.lock_reset),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          firstRun
              ? 'Setelah menekan Mulai pakai, Anda akan diberi kode pemulihan '
                  'untuk berjaga-jaga bila suatu hari lupa PIN. PIN bisa '
                  'diganti kapan saja di Pengaturan.'
              : 'PIN bisa diganti kapan saja di Pengaturan.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Setelah ini',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: AppSpacing.sm),
                Text('1. Buka shift dan masukkan kas awal di laci'),
                Text('2. Tekan Order Baru saat pelanggan datang'),
                Text('3. Backup seminggu sekali, simpan di luar HP'),
              ],
            ),
          ),
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
      ],
    );
  }
}
