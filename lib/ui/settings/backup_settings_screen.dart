import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/formatters.dart';
import '../../services/backup/backup_service.dart';

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

  Future<void> _run(Future<BackupResult> Function() action) async {
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    final result = await action();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup dan Restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded),
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
            onPressed: _busy
                ? null
                : () => _run(ref.read(backupServiceProvider).shareLatest),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Buat & bagikan backup'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Kirim ke WhatsApp pribadi, email, atau simpan ke Google Drive.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(ref.read(backupServiceProvider).createLocal),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Backup ke perangkat saja'),
          ),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restorePicked,
            icon: const Icon(Icons.restore),
            label: const Text('Kembalikan dari berkas backup'),
          ),

          const SizedBox(height: 28),
          const Text(
            'Backup tersimpan di perangkat',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Aplikasi menyimpan tujuh backup terakhir dan membuat satu '
            'otomatis setiap hari saat dibuka.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
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
                      leading: const Icon(Icons.description_outlined),
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
