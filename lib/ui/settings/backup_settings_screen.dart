import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../services/backup/backup_reminder.dart';
import '../../services/backup/backup_service.dart';
import '../backup/backup_wizard_screen.dart';
import '../widgets/layout.dart';
import '../../core/design_system.dart';

class BackupSettingsScreen extends ConsumerStatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  ConsumerState<BackupSettingsScreen> createState() =>
      _BackupSettingsScreenState();
}

class _BackupSettingsScreenState
    extends ConsumerState<BackupSettingsScreen> {
  List<BackupInfo> _backups = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(backupServiceProvider).list();
    if (mounted) setState(() => _backups = list);
  }

  /// [method] diisi untuk backup yang dibuat pemilik sendiri. Hanya itu yang
  /// menggeser pengingat mingguan; restore dan backup harian tidak.
  Future<void> _run(
    Future<BackupResult> Function() action, {
    BackupMethod? method,
  }) async {
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    final result = await action();

    if (result.success && method != null) {
      await ref.read(backupReminderProvider).markDone(method);
      ref.read(backupTickProvider.notifier).state++;
    }

    await _load();
    if (!mounted) return;

    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _restorePicked() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kembalikan data?'),
        content: const Text(
          'Seluruh data saat ini akan diganti dengan isi berkas backup. '
          'Data yang ada sekarang disalin dulu ke pre-restore, tapi order '
          'yang dibuat setelah backup itu dibuat akan hilang.\n\n'
          'Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kembalikan'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _run(() =>
        ref.read(backupServiceProvider).restoreFrom(File(path)));

    ref.refreshOrderData();
    ref.invalidate(settingsLoadedProvider);
    ref.invalidate(servicesProvider);
  }

  Future<void> _openWizard() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BackupWizardScreen()),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup dan Restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _StatusCard(
            status: ref.watch(backupStatusProvider),
            onWizard: _busy ? null : _openWizard,
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(Icons.warning_amber_rounded, tone: 2),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Data aplikasi ini hanya ada di ponsel ini. Kalau ponsel '
                      'hilang, rusak, atau aplikasi terhapus, seluruh riwayat '
                      'dan piutang hilang permanen.\n\n'
                      'Bagikan backup ke luar ponsel minimal seminggu sekali.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppTouch.comfortable),
            ),
            onPressed: _busy
                ? null
                : () => _run(
                      ref.read(backupServiceProvider).shareLatest,
                      method: BackupMethod.share,
                    ),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Buat & bagikan backup'),
          ),
          const SizedBox(height: 8),
          Text(
            'Kirim ke WhatsApp pribadi, email, atau simpan ke Google Drive.',
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                      ref.read(backupServiceProvider).createLocal,
                      method: BackupMethod.device,
                    ),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Backup ke perangkat saja'),
          ),

          const SizedBox(height: 16),
          // Pemilik yang tahu jalurnya bisa menyalin berkasnya sendiri
          // lewat Pengelola File, tanpa membuka aplikasi ini.
          FutureBuilder<String>(
            future: ref.read(backupServiceProvider).backupFolderPath(),
            builder: (context, snapshot) {
              final path = snapshot.data;
              if (path == null) return const SizedBox.shrink();

              return Card(
                child: ListTile(
                  leading: const IconBadge(Icons.folder_outlined, tone: 4),
                  title: const Text('Folder backup otomatis'),
                  subtitle: Text(
                    path,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    tooltip: 'Salin jalur',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: path));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Jalur folder disalin.')),
                      );
                    },
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restorePicked,
            icon: const Icon(Icons.restore),
            label: const Text('Kembalikan dari berkas backup'),
          ),

          const SizedBox(height: 28),
          Text(
            'Backup tersimpan di perangkat',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Aplikasi menyimpan tujuh backup terakhir dan membuat satu '
            'otomatis setiap hari saat dibuka.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),

          if (_backups.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.inbox_outlined),
                title: Text('Belum ada backup'),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < _backups.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: const IconBadge(Icons.description_outlined, tone: 5),
                      title: Text(_backups[i].name),
                      subtitle: Text(
                        '${formatDateTime(_backups[i].createdAt)} · '
                        '${_backups[i].sizeLabel}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Kembalikan dari backup ini',
                        icon: const Icon(Icons.restore),
                        onPressed: _busy
                            ? null
                            : () => _run(() => ref
                                .read(backupServiceProvider)
                                .restoreFrom(_backups[i].file)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}


/// Ringkasan backup buatan pemilik, dengan jalan pintas ke wizard.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.onWizard});

  final BackupStatus status;
  final VoidCallback? onWizard;

  @override
  Widget build(BuildContext context) {
    final overdue = status.overdue;
    final color = overdue
        ? Theme.of(context).colorScheme.error
        : context.status.selesai;

    final title = status.neverBackedUp
        ? 'Belum pernah membuat backup'
        : 'Backup terakhir ${relativeDays(status.lastAt!, status.now)}';

    final detail = overdue
        ? 'Sudah waktunya backup lagi. Pengingat dikirim setiap minggu.'
        : 'Pengingat berikutnya sekitar ${formatDate(status.nextDue)}.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  overdue ? Icons.warning_amber_rounded : Icons.verified_outlined,
                  color: color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onWizard,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('Buka wizard backup'),
            ),
          ],
        ),
      ),
    );
  }
}
