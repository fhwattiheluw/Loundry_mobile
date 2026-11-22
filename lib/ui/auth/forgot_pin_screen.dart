import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../widgets/layout.dart';

/// Pemulihan PIN pemilik.
///
/// Layar ini tidak pernah menampilkan PIN lama, karena PIN lama memang tidak
/// tersimpan di mana pun — hanya hasil pengacakannya. Yang dilakukan di sini
/// adalah membuktikan bahwa orang di depan layar memang pemiliknya, lalu
/// mempersilakan ia memasang PIN baru.
class ForgotPinScreen extends ConsumerStatefulWidget {
  const ForgotPinScreen({super.key});

  @override
  ConsumerState<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

enum _Step { choose, enterCode, newPin }

enum _Method { whatsapp, recovery }

class _ForgotPinScreenState extends ConsumerState<ForgotPinScreen> {
  _Step _step = _Step.choose;
  _Method _method = _Method.whatsapp;

  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _sendWhatsApp() async {
    final recovery = ref.read(pinRecoveryProvider);

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });

    final result = await recovery.sendResetCode();

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.sent) {
        _method = _Method.whatsapp;
        _step = _Step.enterCode;
        _info = 'Kode dikirim ke ${recovery.maskedOwnerPhone}. '
            'Berlaku 15 menit.';
      } else {
        _error = result.message;
      }
    });
  }

  void _checkCode() {
    final recovery = ref.read(pinRecoveryProvider);
    final code = _codeController.text;

    final ok = _method == _Method.whatsapp
        ? recovery.verifyResetCode(code)
        : recovery.verifyRecoveryCode(code);

    setState(() {
      if (ok) {
        _step = _Step.newPin;
        _error = null;
        _info = null;
      } else {
        _error = _method == _Method.whatsapp
            ? 'Kode salah atau sudah kedaluwarsa.'
            : 'Kode pemulihan tidak cocok.';
      }
    });
  }

  Future<void> _savePin() async {
    final pin = _pinController.text;

    if (pin.length < 4) {
      setState(() => _error = 'PIN minimal 4 angka.');
      return;
    }
    if (pin != _pinConfirmController.text) {
      setState(() => _error = 'Dua isian PIN berbeda.');
      return;
    }

    setState(() => _busy = true);
    await ref.read(pinRecoveryProvider).resetOwnerPin(pin);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(pinRecoveryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Lupa PIN pemilik')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_info != null) ...[
            _Banner(text: _info!, error: false),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_error != null) ...[
            _Banner(text: _error!, error: true),
            const SizedBox(height: AppSpacing.md),
          ],
          switch (_step) {
            _Step.choose => _chooseStep(recovery),
            _Step.enterCode => _codeStep(),
            _Step.newPin => _pinStep(),
          },
        ],
      ),
    );
  }

  Widget _chooseStep(dynamic recovery) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PIN lama tidak bisa dikirim ulang',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Yang tersimpan di HP ini hanya hasil pengacakan PIN, bukan '
          'PIN-nya. Itu yang membuat laporan dan harga Anda tetap aman '
          'walau HP jatuh ke tangan orang lain. Jadi yang bisa dilakukan '
          'adalah memasang PIN baru setelah Anda membuktikan diri.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),

        Card(
          child: ListTile(
            leading: const IconBadge(Icons.chat_outlined, tone: 11),
            title: const Text('Kirim kode ke WhatsApp pemilik'),
            subtitle: Text(
              recovery.canSendViaWhatsApp
                  ? 'Kode dikirim ke ${recovery.maskedOwnerPhone}'
                  : 'Hanya tersedia bila notifikasi WhatsApp dipasang '
                      'dalam mode API, dan nomor usaha sudah diisi',
            ),
            enabled: recovery.canSendViaWhatsApp && !_busy,
            onTap: _sendWhatsApp,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        Card(
          child: ListTile(
            leading: const IconBadge(Icons.key_outlined, tone: 12),
            title: const Text('Pakai kode pemulihan'),
            subtitle: Text(
              recovery.hasRecoveryCode
                  ? 'Kode 10 angka yang Anda catat saat pengaturan awal'
                  : 'Belum pernah dibuat di HP ini',
            ),
            enabled: recovery.hasRecoveryCode && !_busy,
            onTap: () => setState(() {
              _method = _Method.recovery;
              _step = _Step.enterCode;
              _error = null;
            }),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        Text(
          'Kalau keduanya tidak bisa, jalan terakhir adalah memasang ulang '
          'aplikasi dan memulihkan data dari berkas backup. Itu sebabnya '
          'backup mingguan penting.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: _method == _Method.whatsapp
                ? 'Kode dari WhatsApp'
                : 'Kode pemulihan',
            prefixIcon: const Icon(Icons.pin_outlined),
          ),
          onSubmitted: (_) => _checkCode(),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _busy ? null : _checkCode,
          child: const Text('Lanjut'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _step = _Step.choose;
            _error = null;
          }),
          child: const Text('Kembali'),
        ),
      ],
    );
  }

  Widget _pinStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pasang PIN baru',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'PIN baru',
            helperText: '4 sampai 6 angka',
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _pinConfirmController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Ulangi PIN baru',
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _busy ? null : _savePin,
          child: const Text('Simpan PIN baru'),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.error});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = error ? scheme.errorContainer : scheme.secondaryContainer;
    final foreground =
        error ? scheme.onErrorContainer : scheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.info_outline,
              size: 18, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }
}
