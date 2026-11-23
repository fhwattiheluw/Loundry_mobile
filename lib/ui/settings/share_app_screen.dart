import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/providers.dart';
import '../../core/app_identity.dart';
import '../../core/design_system.dart';
import '../../data/db/settings_keys.dart';
import '../widgets/feedback.dart';
import '../widgets/layout.dart';

/// Cara pemilik ikut menyebarkan aplikasi ini, dan sakelar untuk baris
/// kecil di kaki nota.
class ShareAppScreen extends ConsumerStatefulWidget {
  const ShareAppScreen({super.key});

  @override
  ConsumerState<ShareAppScreen> createState() => _ShareAppScreenState();
}

class _ShareAppScreenState extends ConsumerState<ShareAppScreen> {
  late bool _onReceipt = ref
      .read(settingsRepoProvider)
      .getBool(SettingsKeys.receiptPromo, fallback: true);

  Future<void> _setOnReceipt(bool value) async {
    setState(() => _onReceipt = value);
    await ref
        .read(settingsRepoProvider)
        .set(SettingsKeys.receiptPromo, value ? '1' : '0');
    ref.invalidate(settingsLoadedProvider);
  }

  Future<void> _share() async {
    final name = ref.read(settingsRepoProvider).get(SettingsKeys.businessName);

    await SharePlus.instance.share(
      ShareParams(
        text: AppIdentity.shareMessage(businessName: name),
        subject: AppIdentity.name,
      ),
    );
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(
      const ClipboardData(text: AppIdentity.playStoreUrl),
    );
    if (mounted) showToast(context, 'Tautan disalin.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paper =
        ref.watch(settingsRepoProvider).getInt(SettingsKeys.paperWidth,
            fallback: 58);

    return Scaffold(
      appBar: AppBar(title: const Text('Bagikan aplikasi')),
      body: ListView(
        padding: EdgeInsets.all(context.screenPadding),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Beri tahu sesama pemilik laundry',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          'Rekomendasi dari teman yang sudah memakai jauh '
                          'lebih dipercaya daripada iklan. Teks di bawah ini '
                          'sudah disiapkan, tinggal kirim ke grup WhatsApp '
                          'atau teman usaha.',
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, AppTouch.comfortable),
                          ),
                          onPressed: _share,
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Bagikan sekarang'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, AppTouch.comfortable),
                          ),
                          onPressed: _copyLink,
                          icon: const Icon(Icons.link),
                          label: const Text('Salin tautan aplikasi'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _onReceipt,
                        onChanged: _setOnReceipt,
                        title: const Text('Nama aplikasi di kaki nota'),
                        subtitle: const Text(
                          'Dua baris huruf kecil di bawah "Terima kasih". '
                          'Identitas toko Anda tetap paling besar di atas.',
                        ),
                      ),
                      if (_onReceipt)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Terima kasih',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                for (final line
                                    in AppIdentity.receiptLines(
                                        cols: paper == 80 ? 48 : 32))
                                  Text(
                                    line,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: ListTile(
                    leading: const IconBadge(Icons.chat_outlined, tone: 3),
                    title: const Text('Di pesan WhatsApp'),
                    subtitle: const Text(
                      'Tambahkan {aplikasi} di Pengaturan, Template pesan, '
                      'bila ingin tautan aplikasi ikut terkirim ke pelanggan. '
                      'Tidak dipasang otomatis, karena pesan itu atas nama '
                      'toko Anda.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
