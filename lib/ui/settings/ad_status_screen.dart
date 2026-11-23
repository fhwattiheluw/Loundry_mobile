import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../services/ads/ad_service.dart';
import '../widgets/layout.dart';

/// Memeriksa apakah iklan benar-benar bisa tayang dan menghasilkan uang.
///
/// Iklan yang tidak tampil hampir selalu punya satu dari beberapa sebab
/// yang bisa dibaca dari sini: ID masih uji, persetujuan belum ada, unit
/// baru belum punya iklan ("no fill"), atau ID salah ketik.
class AdStatusScreen extends ConsumerWidget {
  const AdStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.status;
    final ads = ref.watch(adServiceProvider);

    final production = !kDebugMode && AdIds.allProduction;
    final partial = !kDebugMode && !AdIds.allProduction && !AdIds.allTest;

    final (Color color, IconData icon, String title, String body) = kDebugMode
        ? (
            palette.diterima,
            Icons.bug_report_outlined,
            'Mode pengembangan: iklan uji',
            'Wajar bila memakai iklan uji saat debug. Iklan uji tidak '
                'menghasilkan uang. Pendapatan hanya dari build rilis dengan '
                'ID unit iklan produksi.',
          )
        : production
            ? (
                palette.lunas,
                Icons.verified_outlined,
                'Memakai ID produksi',
                'Semua unit iklan memakai ID AdMob Anda. Iklan yang tayang '
                    'di sini menghasilkan uang.',
              )
            : partial
                ? (
                    palette.diterima,
                    Icons.warning_amber_rounded,
                    'Sebagian unit masih iklan uji',
                    'Unit yang bertanda "Uji" di bawah belum menghasilkan '
                        'uang. Isi ID-nya di ad_config.dart lalu bangun ulang.',
                  )
                : (
                    palette.belumLunas,
                    Icons.money_off_csred_outlined,
                    'Semua unit masih iklan uji: pendapatan Rp 0',
                    'Isi ID unit iklan produksi di ad_config.dart (atau lewat '
                        '--dart-define), pakai ID Aplikasi AdMob asli di '
                        'AndroidManifest.xml, lalu bangun ulang.',
                  );

    final real = AdIds.realByFormat;

    return Scaffold(
      appBar: AppBar(title: const Text('Status iklan')),
      body: ContentWidth(
        child: ValueListenableBuilder<Map<String, String>>(
          valueListenable: AdService.report,
          builder: (context, report, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  color: color.withValues(alpha: palette.onStatusTint),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconBadge(icon, color: color),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: theme.textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text(body, style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),
                const SectionHeader('Mesin iklan'),
                Card(
                  child: Column(
                    children: [
                      _Row(
                        label: 'Iklan aktif',
                        value: ads.enabled ? 'Ya, selalu' : 'Tidak (bukan perangkat seluler)',
                        ok: ads.enabled,
                      ),
                      const Divider(height: 1),
                      _Row(
                        label: 'Persetujuan privasi',
                        value: report['Persetujuan'] ?? 'Belum diperiksa',
                        ok: report['Persetujuan'] == 'OK',
                      ),
                      const Divider(height: 1),
                      _Row(
                        label: 'SDK iklan',
                        value: report['SDK'] ?? 'Belum siap',
                        ok: report['SDK'] == 'Siap',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),
                const SectionHeader('Unit iklan'),
                Card(
                  child: Column(
                    children: [
                      for (final format in real.keys) ...[
                        if (format != real.keys.first) const Divider(height: 1),
                        _Row(
                          label: '$format  ·  ${real[format]! ? 'Produksi' : 'Uji'}',
                          value: report[format] ?? 'Belum diminta',
                          ok: report[format] == 'Siap',
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, AppTouch.comfortable),
                  ),
                  onPressed: () {
                    ref.read(adServiceProvider).reloadAll();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Meminta ulang iklan...')),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Minta ulang semua iklan'),
                ),

                const SizedBox(height: AppSpacing.xl),
                const SectionHeader('Kalau iklan belum muncul'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      '• "Gagal (3) No fill": unit iklan baru butuh waktu, dan '
                      'iklan sungguhan baru ada setelah akun AdMob disetujui '
                      'dan aplikasi tayang di Play Store. Bisa sampai beberapa '
                      'hari.\n\n'
                      '• "Gagal (0) Internal error" atau "Invalid request": ID '
                      'unit salah ketik, atau ID Aplikasi di '
                      'AndroidManifest.xml bukan milik akun yang sama dengan '
                      'unit iklannya.\n\n'
                      '• "Gagal (2) Network error": periksa internet.\n\n'
                      '• Persetujuan "Belum mengizinkan": pengguna menolak '
                      'formulir privasi iklan.\n\n'
                      '• Pastikan app-ads.txt sudah terpasang di situs '
                      'pengembang dan akun AdMob sudah mengisi data '
                      'pembayaran.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.ok});

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.status;

    return ListTile(
      dense: true,
      title: Text(label, style: theme.textTheme.titleSmall),
      subtitle: Text(value),
      trailing: Icon(
        ok ? Icons.check_circle : Icons.radio_button_unchecked,
        color: ok ? palette.lunas : theme.colorScheme.outline,
      ),
    );
  }
}
