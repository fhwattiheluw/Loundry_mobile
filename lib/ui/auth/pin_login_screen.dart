import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/db/settings_keys.dart';
import '../../services/auth/pin_guard.dart';
import '../widgets/app_logo.dart';
import 'forgot_pin_screen.dart';
import '../widgets/layout.dart';

/// Login memakai PIN, bukan email dan kata sandi, supaya kasir bisa masuk
/// dalam dua detik saat konter ramai.
class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen>
    with SingleTickerProviderStateMixin {
  /// Getaran kecil pada titik-titik PIN saat PIN salah. Kasir yang salah
  /// ketik biasanya sedang tidak menatap layar, jadi umpan baliknya dibuat
  /// terasa, bukan hanya terbaca.
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  String _pin = '';
  bool _checking = false;
  String? _error;

  static const _minLength = 4;
  static const _maxLength = 6;

  /// PIN di aplikasi ini panjangnya 4 sampai 6 digit, dan hash-nya tidak
  /// memberi tahu panjangnya. Jadi aplikasi tidak boleh menebak kapan
  /// pengguna selesai mengetik: pengguna yang menyatakannya, lewat tombol
  /// panah. Mencoba sendiri di digit keempat membuat PIN enam digit tidak
  /// mungkin dipakai, dan lebih buruk lagi: PIN 1234 akan mencuri login
  /// pengguna yang PIN-nya 123456, karena empat digit pertamanya cocok.
  Future<void> _submit() async {
    if (_pin.length < _minLength || _checking) return;

    final guard = ref.read(pinGuardProvider);

    // Terkunci: PIN tidak diperiksa sama sekali. Memeriksanya tetap akan
    // memberi tahu penebak apakah tebakannya benar.
    final locked = guard.lockRemaining();
    if (locked != null) {
      setState(() {
        _error = 'Terlalu banyak PIN salah. Coba lagi dalam '
            '${PinGuard.describe(locked)}.';
        _pin = '';
      });
      HapticFeedback.mediumImpact();
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    final user = await ref.read(userRepoProvider).authenticate(_pin);

    if (!mounted) return;

    if (user == null) {
      final lock = await guard.recordFailure();
      if (!mounted) return;

      setState(() {
        _checking = false;
        _error = lock > Duration.zero
            ? 'PIN salah terlalu sering. Layar dikunci '
                '${PinGuard.describe(lock)}.'
            : 'PIN salah. Sisa ${guard.attemptsLeftInRound} kesempatan '
                'sebelum layar dikunci.';
        _pin = '';
      });
      _shake.forward(from: 0);
      HapticFeedback.mediumImpact();
      return;
    }

    await guard.recordSuccess();
    ref.read(sessionProvider.notifier).signIn(user);
  }

  void _tap(String digit) {
    if (_pin.length >= _maxLength || _checking) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    // Enam digit adalah batas atas. Tidak ada lagi yang bisa diketik, jadi
    // tidak ada yang perlu ditunggu.
    if (_pin.length >= _maxLength) _submit();
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsRepoProvider);
    final businessName =
        settings.get(SettingsKeys.businessName, fallback: 'Laundry Manise');

    return Scaffold(
      body: ContentWidth(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AnimatedAppLogo(size: 104),
                    const SizedBox(height: 14),

                    // Nama usaha dan petunjuk muncul sedikit setelah logo,
                    // supaya mata berhenti dulu di logo, baru membaca.
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 650),
                      curve: const Interval(0.35, 1, curve: Curves.easeOut),
                      builder: (context, t, child) => Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 10),
                          child: child,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            businessName,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          const Text('Masukkan PIN Anda, 4 sampai 6 digit'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    AnimatedBuilder(
                      animation: _shake,
                      builder: (context, child) {
                        final t = _shake.value;
                        // Ayunan yang mengecil, bukan getaran tetap: terasa
                        // seperti kepala menggeleng sekali, lalu berhenti.
                        final offset =
                            math.sin(t * math.pi * 4) * 12 * (1 - t);
                        return Transform.translate(
                          offset: Offset(offset, 0),
                          child: child,
                        );
                      },
                      child: _Dots(length: _pin.length, max: _maxLength),
                    ),
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
                    // Hanya pemilik yang punya jalan pemulihan. Kasir yang
                    // lupa PIN cukup diberi PIN baru oleh pemiliknya.
                    TextButton(
                      onPressed: () async {
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPinScreen(),
                          ),
                        );
                        if (changed == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'PIN pemilik sudah diganti. Masuk dengan PIN baru.'),
                            ),
                          );
                        }
                      },
                      child: const Text('Lupa PIN pemilik?'),
                    ),
                    const SizedBox(height: 4),

                    _Keypad(
                      onDigit: _tap,
                      onBackspace: _backspace,
                      onSubmit: _submit,
                      canSubmit: _pin.length >= _minLength && !_checking,
                    ),
                  ],
                ),
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
    required this.canSubmit,
  });

  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

  /// Tombol panah mati sampai PIN cukup panjang, supaya pengguna melihat
  /// bahwa menekannya sekarang tidak ada gunanya.
  final bool canSubmit;

  @override
  Widget build(BuildContext context) {
    Widget key(String label,
        {VoidCallback? onTap, IconData? icon, bool enabled = true}) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          height: 64,
          child: OutlinedButton(
            onPressed:
                enabled ? (onTap ?? () => onDigit(label)) : null,
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
              child: key('',
                  onTap: onSubmit,
                  icon: Icons.arrow_forward,
                  enabled: canSubmit),
            ),
          ],
        ),
      ],
    );
  }
}
