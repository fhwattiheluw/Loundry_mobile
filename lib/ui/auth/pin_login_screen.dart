import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/db/settings_keys.dart';

/// Login memakai PIN, bukan email dan kata sandi, supaya kasir bisa masuk
/// dalam dua detik saat konter ramai.
class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen> {
  String _pin = '';
  bool _checking = false;
  String? _error;

  static const _maxLength = 6;

  Future<void> _submit() async {
    if (_pin.length < 4 || _checking) return;

    setState(() {
      _checking = true;
      _error = null;
    });

    final user = await ref.read(userRepoProvider).authenticate(_pin);

    if (!mounted) return;

    if (user == null) {
      setState(() {
        _checking = false;
        _error = 'PIN salah.';
        _pin = '';
      });
      return;
    }

    ref.read(sessionProvider.notifier).signIn(user);
  }

  void _tap(String digit) {
    if (_pin.length >= _maxLength) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length >= 4) _maybeAutoSubmit();
  }

  void _maybeAutoSubmit() {
    // PIN empat digit langsung dicoba. Yang lebih panjang menunggu tombol OK.
    if (_pin.length == 4) _submit();
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsRepoProvider);
    final businessName =
        settings.get(SettingsKeys.businessName, fallback: 'POS Laundry');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_laundry_service_outlined, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    businessName,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text('Masukkan PIN Anda'),
                  const SizedBox(height: 28),
                  _Dots(length: _pin.length, max: _maxLength),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 24,
                    child: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _error ?? '',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  _Keypad(
                    onDigit: _tap,
                    onBackspace: _backspace,
                    onSubmit: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.length, required this.max});

  final int length;
  final int max;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(max, (i) {
        final filled = i < length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? scheme.primary : Colors.transparent,
            border: Border.all(
              color: filled ? scheme.primary : scheme.outlineVariant,
              width: 2,
            ),
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
  });

  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          height: 64,
          child: OutlinedButton(
            onPressed: onTap ?? () => onDigit(label),
            style: OutlinedButton.styleFrom(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: icon != null
                ? Icon(icon, size: 24)
                : Text(label,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            children: [for (final digit in row) Expanded(child: key(digit))],
          ),
        Row(
          children: [
            Expanded(
                child: key('', onTap: onBackspace, icon: Icons.backspace_outlined)),
            Expanded(child: key('0')),
            Expanded(
                child: key('', onTap: onSubmit, icon: Icons.arrow_forward)),
          ],
        ),
      ],
    );
  }
}
