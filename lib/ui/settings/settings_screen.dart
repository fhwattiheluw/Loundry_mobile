import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../data/db/settings_keys.dart';
import '../customers/customer_screen.dart';
import '../help/help_screen.dart';
import '../../services/ads/ad_service.dart';
import '../widgets/layout.dart';
import 'ad_status_screen.dart';
import '../shift/shift_screen.dart';
import 'backup_settings_screen.dart';
import 'business_settings_screen.dart';
import 'logo_settings_screen.dart';
import 'notification_log_screen.dart';
import 'printer_settings_screen.dart';
import 'service_settings_screen.dart';
import 'share_app_screen.dart';
import 'template_settings_screen.dart';
import 'user_settings_screen.dart';
import 'whatsapp_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final settings = ref.watch(settingsRepoProvider);
    final isOwner = user?.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: AppGradient.brand(context),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: AppShadow.soft(context),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      (user?.name.isNotEmpty ?? false)
                          ? user!.name.substring(0, 1).toUpperCase()
                          : '?',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: const Color(0xFF00574B),
                          ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? '-',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(color: Colors.white),
                        ),
                        Text(
                          user?.role.label ?? '',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        ref.read(sessionProvider.notifier).signOut(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppTouch.minimum),
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Keluar'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const _Heading('Bantuan'),
            Card(
              child: ListTile(
                leading: const IconBadge(Icons.help_outline, tone: 13),
                title: const Text('Panduan dan pertanyaan umum'),
                subtitle: const Text(
                    'Cara order, cetak nota, backup, dan lupa PIN'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, const HelpScreen()),
              ),
            ),

            const SizedBox(height: 20),
            const _Heading('Tampilan'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mode warna'),
                    const SizedBox(height: AppSpacing.md),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'system',
                          label: Text('Ikuti HP'),
                          icon: Icon(Icons.brightness_auto_outlined),
                        ),
                        ButtonSegment(
                          value: 'light',
                          label: Text('Terang'),
                          icon: Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: 'dark',
                          label: Text('Gelap'),
                          icon: Icon(Icons.dark_mode_outlined),
                        ),
                      ],
                      selected: {
                        settings.get(SettingsKeys.themeMode, fallback: 'system'),
                      },
                      onSelectionChanged: (value) async {
                        await settings.set(
                            SettingsKeys.themeMode, value.first);
                        ref.invalidate(settingsLoadedProvider);
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Mode gelap menghemat baterai di layar OLED dan lebih '
                      'nyaman saat konter tutup malam.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            const _Heading('Kas'),
            Card(
              child: Column(
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final shift = ref.watch(currentShiftProvider);
                      return ListTile(
                        leading: const IconBadge(Icons.point_of_sale_outlined, tone: 1),
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
                    const Divider(height: 1, indent: 70),
                    ListTile(
                      leading: const IconBadge(Icons.history, tone: 2),
                      title: const Text('Riwayat shift dan selisih kas'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, const ShiftHistoryScreen()),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),
            const _Heading('Perangkat'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const IconBadge(Icons.print_outlined, tone: 3),
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
              const SizedBox(height: 20),
              const _Heading('Usaha'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const IconBadge(Icons.storefront_outlined, tone: 4),
                      title: const Text('Profil usaha dan nota'),
                      subtitle: Text(
                          settings.get(SettingsKeys.businessName, fallback: '-')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          _open(context, const BusinessSettingsScreen()),
                    ),
                    const Divider(height: 1, indent: 70),
                    ListTile(
                      leading: const IconBadge(Icons.local_offer_outlined, tone: 5),
                      title: const Text('Layanan dan harga'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          _open(context, const ServiceSettingsScreen()),
                    ),
                    const Divider(height: 1, indent: 70),
                    ListTile(
                      leading: const IconBadge(Icons.people_outline, tone: 6),
                      title: const Text('Pelanggan'),
                      subtitle: const Text('Ubah data, impor CSV, kirim promo'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, const CustomerScreen()),
                    ),
                    const Divider(height: 1, indent: 70),
                    ListTile(
                      leading: const IconBadge(Icons.chat_outlined, tone: 7),
                      title: const Text('Template WhatsApp'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          _open(context, const TemplateSettingsScreen()),
                    ),
                    const Divider(height: 1, indent: 70),
                    ListTile(
                      leading: const IconBadge(Icons.send_outlined, tone: 8),
                      title: const Text('Mode pengiriman dan jam tenang'),
                      subtitle: Text(
                        settings.get(SettingsKeys.whatsappMode,
                                    fallback: 'manual') ==
                                'api'
                            ? 'Otomatis lewat Cloud API'
                            : 'Manual lewat wa.me',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          _open(context, const WhatsAppSettingsScreen()),
                    ),
                    const Divider(height: 1, indent: 70),
                    Consumer(
                      builder: (context, ref, _) {
                        final pending = ref.watch(pendingNotificationsProvider);
                        final count = pending.maybeWhen(
                          data: (c) => c,
                          orElse: () => 0,
                        );

                        return ListTile(
                          leading: const IconBadge(Icons.mark_chat_unread_outlined, tone: 9),
                          title: const Text('Pesan belum terkirim'),
                          subtitle: Text(count == 0
                              ? 'Semua pesan sudah terkirim'
                              : '$count pesan menunggu'),
                          trailing: count == 0
                              ? const Icon(Icons.chevron_right)
                              : Chip(
                                  label: Text('$count'),
                                  visualDensity: VisualDensity.compact,
                                ),
                          onTap: () =>
                              _open(context, const NotificationLogScreen()),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 70),
                    ListTile(
                      leading: const IconBadge(Icons.group_outlined, tone: 10),
                      title: const Text('Pengguna dan PIN'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, const UserSettingsScreen()),
                    ),
                    const Divider(height: 1, indent: 70),
                    ListTile(
                      leading: const IconBadge(Icons.backup_outlined, tone: 11),
                      title: const Text('Backup dan restore'),
                      subtitle: const Text(
                          'Data hanya ada di ponsel ini. Bagikan backup rutin.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, const BackupSettingsScreen()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const _Heading('Nota'),
              Card(
                child: ListTile(
                  leading: const IconBadge(Icons.image_outlined, tone: 12),
                  title: const Text('Logo di nota'),
                  subtitle: Text(
                    settings.get(SettingsKeys.receiptLogoPath).isEmpty
                        ? 'Belum ada logo'
                        : 'Logo terpasang',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, const LogoSettingsScreen()),
                ),
              ),

              const SizedBox(height: 20),
              const _Heading('Aplikasi'),
              Card(
                child: ListTile(
                  leading: const IconBadge(Icons.share_outlined, tone: 4),
                  title: const Text('Bagikan aplikasi'),
                  subtitle: Text(
                    settings.getBool(SettingsKeys.receiptPromo, fallback: true)
                        ? 'Nama aplikasi tercetak di kaki nota'
                        : 'Baris di kaki nota sedang dimatikan',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, const ShareAppScreen()),
                ),
              ),

              const SizedBox(height: 20),
              const _Heading('Iklan'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: IconBadge(
                        !kDebugMode && !AdIds.allProduction
                            ? Icons.warning_amber_rounded
                            : Icons.ads_click,
                        color: !kDebugMode && !AdIds.allProduction
                            ? context.status.belumLunas
                            : null,
                      ),
                      title: const Text('Status iklan'),
                      subtitle: Text(
                        kDebugMode
                            ? 'Mode pengembangan: iklan uji'
                            : AdIds.allProduction
                                ? 'ID produksi terpasang'
                                : 'Masih ID uji: belum menghasilkan uang',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, const AdStatusScreen()),
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
                            const Divider(height: 1, indent: 70),
                            ListTile(
                              leading: const IconBadge(Icons.privacy_tip_outlined, tone: 14),
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
              child: Image.asset(
                'assets/brand/logo.png',
                width: 44,
                height: 44,
                errorBuilder: (context, _, __) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Laundry Manise v0.1.0',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
