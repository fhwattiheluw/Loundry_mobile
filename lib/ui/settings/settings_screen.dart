import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../data/db/settings_keys.dart';
import '../shift/shift_screen.dart';
import 'backup_settings_screen.dart';
import 'business_settings_screen.dart';
import 'printer_settings_screen.dart';
import 'service_settings_screen.dart';
import 'template_settings_screen.dart';
import 'user_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final settings = ref.watch(settingsRepoProvider);
    final isOwner = user?.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(user?.name ?? '-'),
              subtitle: Text(user?.role.label ?? ''),
              trailing: TextButton.icon(
                onPressed: () =>
                    ref.read(sessionProvider.notifier).signOut(),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Keluar'),
              ),
            ),
          ),

          const SizedBox(height: 16),
          const _Heading('Kas'),
          Card(
            child: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final shift = ref.watch(currentShiftProvider);
                    return ListTile(
                      leading: const Icon(Icons.point_of_sale_outlined),
                      title: const Text('Shift kasir'),
                      subtitle: Text(
                        shift.maybeWhen(
                          data: (s) => s == null
                              ? 'Belum dibuka'
                              : 'Berjalan sejak ${formatDateTime(s.openedAt)}',
                          orElse: () => 'Memuat...',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, const ShiftScreen()),
                    );
                  },
                ),
                if (isOwner) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Riwayat shift dan selisih kas'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(context, const ShiftHistoryScreen()),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          const _Heading('Perangkat'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: const Text('Printer Bluetooth'),
                  subtitle: Text(
                    settings.get(SettingsKeys.printerName).isEmpty
                        ? 'Belum dipilih'
                        : '${settings.get(SettingsKeys.printerName)} · '
                            '${settings.get(SettingsKeys.paperWidth, fallback: '58')} mm',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, const PrinterSettingsScreen()),
                ),
              ],
            ),
          ),

          if (isOwner) ...[
            const SizedBox(height: 16),
            const _Heading('Usaha'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: const Text('Profil usaha dan nota'),
                    subtitle: Text(
                        settings.get(SettingsKeys.businessName, fallback: '-')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _open(context, const BusinessSettingsScreen()),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.local_offer_outlined),
                    title: const Text('Layanan dan harga'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _open(context, const ServiceSettingsScreen()),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.chat_outlined),
                    title: const Text('Template WhatsApp'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _open(context, const TemplateSettingsScreen()),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: const Text('Pengguna dan PIN'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(context, const UserSettingsScreen()),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Backup dan restore'),
                    subtitle: const Text(
                        'Data hanya ada di ponsel ini. Bagikan backup rutin.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(context, const BackupSettingsScreen()),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const _Heading('Iklan'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.ads_click),
                    title: const Text('Tampilkan iklan'),
                    subtitle: const Text(
                      'Banner di daftar order dan laporan. Tidak pernah '
                      'muncul di layar input order maupun pembayaran.',
                    ),
                    value: settings.getBool(SettingsKeys.adsEnabled,
                        fallback: true),
                    onChanged: (value) async {
                      await settings.set(
                          SettingsKeys.adsEnabled, value ? '1' : '0');
                      ref.invalidate(settingsLoadedProvider);
                    },
                  ),
                  // Hanya muncul di wilayah yang mewajibkannya, misalnya
                  // Uni Eropa. Menyediakannya adalah syarat kepatuhan UMP.
                  FutureBuilder<bool>(
                    future: ref
                        .read(consentManagerProvider)
                        .isPrivacyOptionsRequired(),
                    builder: (context, snapshot) {
                      if (snapshot.data != true) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        children: [
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.privacy_tip_outlined),
                            title: const Text('Opsi privasi iklan'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => ref
                                .read(consentManagerProvider)
                                .showPrivacyOptions(),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Center(
            child: Text(
              'POS Laundry v0.1.0',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      );
}
