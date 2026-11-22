import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../services/license/license_service.dart';
import '../widgets/app_logo.dart';

/// Layar langganan. Muncul saat masa coba habis dan belum berlangganan.
///
/// Satu hal yang sengaja tidak dilakukan layar ini: menyandera data. Ekspor
/// dan backup tetap bisa dijalankan dari sini walau langganan mati. Data
/// laundry itu milik pemiliknya, bukan jaminan pembayaran.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key, required this.status});

  final LicenseStatus status;

  @override
  ConsumerState<SubscriptionScreen> createState() =>
      _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$failure $e')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Keadaan langganan dibaca ulang; pembelian yang berhasil
        // membuka aplikasi tanpa perlu dimulai ulang.
        ref.invalidate(licenseStatusProvider);
      }
    }
  }

  Future<void> _exportBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(backupServiceProvider).shareLatest();
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final purchases = ref.watch(purchaseServiceProvider);
    final price = purchases.subscriptionPriceLabel;
    final tampered = widget.status.state == LicenseState.clockTampered;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AnimatedAppLogo(size: 88)),
                  const SizedBox(height: AppSpacing.lg),

                  Text(
                    tampered
                        ? 'Jam perangkat berubah'
                        : 'Masa coba sudah habis',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    tampered
                        ? 'Jam di HP ini mundur jauh dari terakhir kali '
                            'aplikasi dibuka. Sambungkan internet sebentar '
                            'supaya langganan bisa diperiksa ulang.'
                        : 'Lanjutkan memakai Laundry Manise dengan langganan '
                            'bulanan. Semua data dan pengaturan Anda tetap '
                            'utuh, dan iklan hilang selama berlangganan.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  if (price.isNotEmpty)
                    Text(
                      '$price / bulan',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),

                  FilledButton.icon(
                    onPressed: _busy || !purchases.isAvailable
                        ? null
                        : () => _run(
                              () => purchases.subscribe(),
                              'Gagal memulai langganan:',
                            ),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.workspace_premium_outlined),
                    label: const Text('Berlangganan sekarang'),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => purchases.restore(),
                              'Gagal memulihkan:',
                            ),
                    icon: const Icon(Icons.restore),
                    label: const Text('Saya sudah berlangganan'),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  const Divider(),
                  const SizedBox(height: AppSpacing.sm),

                  Text(
                    'Data laundry Anda tetap milik Anda. Backup bisa '
                    'diambil kapan saja, termasuk sekarang.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: _busy ? null : _exportBackup,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Ambil backup data'),
                  ),

                  if (!purchases.isAvailable) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Play Store tidak tersedia di perangkat ini, jadi '
                      'langganan tidak bisa dibeli dari sini.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pemberitahuan sisa masa coba. Ditampilkan di atas layar utama, dan baru
/// muncul pada tujuh hari terakhir supaya tidak jadi gangguan harian.
class TrialStrip extends ConsumerWidget {
  const TrialStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(licenseStatusProvider);
    if (status.state != LicenseState.trial || status.daysLeft > 7) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final until = status.until;

    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 16, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Masa coba tersisa ${status.daysLeft} hari'
                '${until == null ? '' : ', sampai ${formatDate(until)}'}.',
                style:
                    TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
