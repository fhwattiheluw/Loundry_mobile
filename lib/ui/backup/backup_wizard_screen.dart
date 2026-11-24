import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../core/formatters.dart';
import '../../services/backup/backup_reminder.dart';
import '../../services/backup/backup_service.dart';
import '../widgets/layout.dart';
import 'backup_folder_card.dart';

/// Empat langkah membuat backup: kenapa, ke mana, buat, selesai.
///
/// Backup adalah satu-satunya pengaman data di aplikasi ini, tapi tombol
/// "Backup dan Restore" di Pengaturan jarang dibuka orang yang tidak tahu
/// kenapa ia penting. Wizard ini menjelaskan risikonya dulu, membiarkan
/// pemilik memilih tujuan dengan akibatnya yang jelas, lalu mencatat bahwa
/// backup sudah dibuat sehingga pengingat mingguan mulai menghitung ulang.
class BackupWizardScreen extends ConsumerStatefulWidget {
  const BackupWizardScreen({super.key});

  @override
  ConsumerState<BackupWizardScreen> createState() =>
      _BackupWizardScreenState();
}

class _BackupWizardScreenState extends ConsumerState<BackupWizardScreen> {
  static const _lastStep = 3;

  int _step = 0;
  BackupMethod _method = BackupMethod.share;
  bool _busy = false;
  String? _problem;
  BackupResult? _result;
  bool? _notificationsAllowed;

  void _go(int step) => setState(() {
        _step = step;
        _problem = null;
      });

  Future<void> _createBackup() async {
    setState(() {
      _busy = true;
      _problem = null;
    });

    final service = ref.read(backupServiceProvider);
    final result = _method == BackupMethod.share
        ? await service.shareLatest()
        : await service.createLocal();

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _busy = false;
        _problem = result.message;
      });
      return;
    }

    final reminder = ref.read(backupReminderProvider);
    await reminder.markDone(_method);
    ref.read(backupTickProvider.notifier).state++;

    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      _step = _lastStep;
    });

    // Izin diminta di sini, bukan di awal aplikasi: pemilik baru saja
    // mengerti kenapa pengingat itu ada.
    final allowed = await reminder.requestPermission();
    if (mounted) setState(() => _notificationsAllowed = allowed);
  }

  Future<void> _askNotificationPermission() async {
    final allowed = await ref.read(backupReminderProvider).requestPermission();
    if (mounted) setState(() => _notificationsAllowed = allowed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Wizard backup data')),
        body: SafeArea(
          child: ContentWidth(
            maxWidth: 640,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i <= _lastStep; i++)
                        Expanded(
                          child: Container(
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: i <= _step
                                  ? scheme.primary
                                  : scheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppDuration.normal,
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.sm,
                          AppSpacing.lg,
                          AppSpacing.xxl,
                        ),
                        children: switch (_step) {
                          0 => _stepWhy(),
                          1 => _stepChoose(),
                          2 => _stepCreate(),
                          _ => _stepDone(),
                        },
                      ),
                    ),
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final isDone = _step == _lastStep;
    final isCreate = _step == 2;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          if (_step > 0 && !isDone)
            TextButton(
              onPressed: _busy ? null : () => _go(_step - 1),
              child: const Text('Kembali'),
            ),
          const Spacer(),
          if (isDone)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppTouch.comfortable),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.check),
              label: const Text('Selesai'),
            )
          else if (isCreate)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppTouch.comfortable),
              ),
              onPressed: _busy ? null : _createBackup,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _method == BackupMethod.share
                          ? Icons.share_outlined
                          : Icons.save_outlined,
                    ),
              label: Text(
                _method == BackupMethod.share
                    ? 'Buat dan bagikan backup'
                    : 'Simpan backup di HP',
              ),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppTouch.comfortable),
              ),
              onPressed: () => _go(_step + 1),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Lanjut'),
            ),
        ],
      ),
    );
  }

  Widget _title(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- langkah 1

  List<Widget> _stepWhy() {
    return [
      _title(
        'Data Anda hanya ada di HP ini',
        'Aplikasi ini tidak menyimpan apa pun di server. Itu membuatnya '
            'cepat dan privat, tapi seluruh riwayat dan piutang bergantung '
            'pada satu HP.',
      ),
      const _RiskTile(
        icon: Icons.phonelink_erase_outlined,
        tone: 2,
        title: 'HP hilang, dicuri, atau rusak',
        body: 'Semua order, pelanggan, dan piutang ikut hilang. '
            'Tidak ada cara memulihkannya tanpa backup.',
      ),
      const _RiskTile(
        icon: Icons.delete_outline,
        tone: 4,
        title: 'Aplikasi terhapus atau data dibersihkan',
        body: 'Mencopot aplikasi menghapus datanya, termasuk backup yang '
            'tersimpan di dalam HP.',
      ),
      const _RiskTile(
        icon: Icons.timer_outlined,
        tone: 1,
        title: 'Hanya butuh satu menit',
        body: 'Wizard ini memandu Anda. Setelah itu aplikasi mengingatkan '
            'seminggu sekali lewat notifikasi.',
      ),
    ];
  }

  // ------------------------------------------------------------- langkah 2

  List<Widget> _stepChoose() {
    return [
      _title(
        'Simpan backup di mana?',
        'Pilih satu. Anda bisa memilih yang lain di backup berikutnya.',
      ),
      _ChoiceCard(
        icon: Icons.share_outlined,
        title: 'Bagikan ke luar HP',
        badge: 'Disarankan',
        body: 'Kirim ke WhatsApp pribadi, email, atau Google Drive. '
            'Satu-satunya cara yang tetap selamat bila HP hilang.',
        selected: _method == BackupMethod.share,
        onTap: () => setState(() => _method = BackupMethod.share),
      ),
      const SizedBox(height: AppSpacing.md),
      _ChoiceCard(
        icon: Icons.phone_android_outlined,
        title: 'Simpan di HP ini saja',
        body: 'Disimpan di folder pilihan Anda, misalnya Download. Tetap '
            'ada walau aplikasi dicopot, tapi ikut hilang bila HP hilang.',
        selected: _method == BackupMethod.device,
        onTap: () => setState(() => _method = BackupMethod.device),
      ),
      const SizedBox(height: AppSpacing.lg),
      Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 20),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Berkas backup memuat data pelanggan dan riwayat transaksi '
                  'dan bisa dibaca siapa pun yang memegangnya. Kirim hanya '
                  'ke chat pribadi atau penyimpanan milik Anda, jangan ke '
                  'grup.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // ------------------------------------------------------------- langkah 3

  List<Widget> _stepCreate() {
    final share = _method == BackupMethod.share;

    return [
      _title(
        'Buat backup sekarang',
        share
            ? 'Aplikasi menyiapkan berkas, lalu membuka lembar bagikan. '
                'Pilih tujuan: chat WhatsApp ke nomor sendiri, email, atau '
                'Google Drive.'
            : 'Aplikasi menyimpan salinan data di folder di bawah. Ketuk '
                'Ubah untuk memilih folder lain, misalnya Download.',
      ),
      Card(
        child: ListTile(
          leading: IconBadge(
            share ? Icons.share_outlined : Icons.phone_android_outlined,
            tone: share ? 6 : 1,
          ),
          title: Text(share ? 'Bagikan ke luar HP' : 'Simpan di HP ini'),
          subtitle: Text(
            share
                ? 'Backup dihitung selesai setelah Anda memilih tujuan.'
                : 'Tidak melindungi dari HP hilang. Bagikan juga bila bisa.',
          ),
        ),
      ),
      // Folder yang sama dipakai backup otomatis harian, jadi pilihan di
      // sini sekaligus mengatur keduanya.
      if (!share) ...[
        const SizedBox(height: AppSpacing.md),
        const BackupFolderCard(),
      ],
      if (_problem != null) ...[
        const SizedBox(height: AppSpacing.md),
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(_problem!)),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  // ------------------------------------------------------------- langkah 4

  List<Widget> _stepDone() {
    final status = ref.watch(backupStatusProvider);
    final result = _result;
    final fileName = result?.file?.path.split('/').last;
    final parts = result?.file?.path.split('/');
    final folder = parts == null || parts.length < 2
        ? null
        : parts.sublist(0, parts.length - 1).join('/');
    final scheme = Theme.of(context).colorScheme;

    return [
      Center(
        child: Container(
          width: 72,
          height: 72,
          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
          decoration: BoxDecoration(
            color: context.status.selesai.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 40,
            color: context.status.selesai,
          ),
        ),
      ),
      Center(
        child: Text(
          'Backup selesai',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Center(
        child: Text(
          _method == BackupMethod.share
              ? 'Pastikan berkasnya sudah sampai di tujuan.'
              : 'Tersimpan di folder yang Anda pilih.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const IconBadge(Icons.schedule, tone: 1),
              title: const Text('Dibuat'),
              subtitle: Text(formatDateTime(status.lastAt ?? status.now)),
            ),
            if (fileName != null) ...[
              const Divider(height: 1),
              ListTile(
                leading: const IconBadge(Icons.description_outlined, tone: 5),
                title: const Text('Nama berkas'),
                subtitle: Text(fileName),
              ),
              if (_method == BackupMethod.device && folder != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const IconBadge(Icons.folder_outlined, tone: 4),
                  title: const Text('Folder'),
                  subtitle: Text(folder),
                ),
              ],
            ],
            const Divider(height: 1),
            ListTile(
              leading: const IconBadge(Icons.notifications_active_outlined,
                  tone: 2),
              title: const Text('Pengingat berikutnya'),
              subtitle: Text(
                'Sekitar ${formatDate(status.nextDue)}, lalu setiap minggu.',
              ),
            ),
          ],
        ),
      ),
      if (_notificationsAllowed == false) ...[
        const SizedBox(height: AppSpacing.md),
        Card(
          color: scheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notifikasi belum diizinkan, jadi pengingat mingguan tidak '
                  'akan muncul. Kartu pengingat di Beranda tetap tampil bila '
                  'backup terlambat.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _askNotificationPermission,
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Izinkan notifikasi'),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }
}

class _RiskTile extends StatelessWidget {
  const _RiskTile({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final int tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon, tone: tone),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(body, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.5)
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon, tone: selected ? 0 : 1),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                color: scheme.onPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(body, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
