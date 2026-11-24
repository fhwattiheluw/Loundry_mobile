import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/providers.dart';
import '../../core/design_system.dart';
import '../../services/backup/backup_service.dart';
import '../widgets/layout.dart';

/// Kartu folder backup otomatis: di mana berkasnya sekarang, apakah
/// selamat bila aplikasi dicopot, dan tombol untuk menggantinya.
///
/// Dipakai di Pengaturan dan di wizard backup, supaya keduanya selalu
/// menunjukkan hal yang sama.
class BackupFolderCard extends ConsumerStatefulWidget {
  const BackupFolderCard({super.key, this.onChanged});

  /// Dipanggil setelah folder berhasil diganti, misalnya untuk memuat ulang
  /// daftar backup.
  final VoidCallback? onChanged;

  @override
  ConsumerState<BackupFolderCard> createState() => _BackupFolderCardState();
}

class _BackupFolderCardState extends ConsumerState<BackupFolderCard> {
  late Future<BackupFolder> _folder = _load();

  Future<BackupFolder> _load() =>
      ref.read(backupServiceProvider).currentFolder();

  Future<void> _change() async {
    final changed = await showBackupFolderSheet(context);
    if (changed != true || !mounted) return;
    setState(() => _folder = _load());
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.status;

    return FutureBuilder<BackupFolder>(
      future: _folder,
      builder: (context, snapshot) {
        final folder = snapshot.data;
        if (folder == null) return const SizedBox.shrink();

        final safe = folder.survivesUninstall && folder.problem == null;
        final tone = safe ? palette.lunas : palette.belumLunas;

        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: _change,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const IconBadge(Icons.folder_outlined, tone: 4),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Folder backup otomatis',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              folderLabel(folder.kind),
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _change,
                        child: const Text('Ubah'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          folder.path,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Salin jalur',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: folder.path));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Jalur folder disalin.')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        safe ? Icons.verified_outlined : Icons.warning_amber,
                        size: 16,
                        color: tone,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          folder.problem ??
                              (safe
                                  ? 'Tetap ada walau aplikasi dicopot. Tetap '
                                      'ikut hilang bila HP hilang.'
                                  : 'Ikut terhapus bila aplikasi dicopot. '
                                      'Ketuk Ubah untuk memilih folder '
                                      'Download.'),
                          style: TextStyle(fontSize: 12.5, color: tone),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Nama folder dalam bahasa pemilik.
String folderLabel(BackupFolderKind kind) => switch (kind) {
      BackupFolderKind.download => 'Download / $backupSubfolder',
      BackupFolderKind.documents => 'Documents / $backupSubfolder',
      BackupFolderKind.custom => 'Folder pilihan sendiri',
      BackupFolderKind.app => 'Folder aplikasi',
    };

/// Lembar pemilihan folder. Mengembalikan true bila folder berhasil
/// diganti dan backup pertama di folder baru sudah dibuat.
Future<bool?> showBackupFolderSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _FolderSheet(),
  );
}

class _FolderSheet extends ConsumerStatefulWidget {
  const _FolderSheet();

  @override
  ConsumerState<_FolderSheet> createState() => _FolderSheetState();
}

class _FolderSheetState extends ConsumerState<_FolderSheet> {
  bool _busy = false;
  String? _problem;

  Future<void> _choose(String pref) async {
    setState(() {
      _busy = true;
      _problem = null;
    });

    final service = ref.read(backupServiceProvider);
    final problem = await service.changeFolder(pref);

    if (problem != null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = problem;
        });
      }
      return;
    }

    // Backup pertama langsung dibuat di folder baru. Sekaligus membuktikan
    // bahwa database benar-benar bisa ditulis di sana, bukan hanya berkas
    // percobaan kecil.
    final result = await service.createLocal();
    ref.read(backupTickProvider.notifier).state++;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.success
            ? 'Folder diganti. Backup pertama di folder baru sudah dibuat.'
            : 'Folder diganti, tapi backup pertama gagal: ${result.message}'),
      ),
    );
  }

  Future<void> _pickOther() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pilih folder backup',
    );
    if (path == null || path.trim().isEmpty || path == '/') {
      if (mounted && path != null) {
        setState(() => _problem = 'Folder itu tidak bisa dipakai. Pilih '
            'folder di dalam Download atau Documents.');
      }
      return;
    }
    await _choose(path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Simpan backup otomatis di mana?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Backup dibuat sekali sehari saat aplikasi dibuka. Folder di '
              'luar folder aplikasi tetap ada walau aplikasi dicopot.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            _option(
              icon: Icons.download_outlined,
              title: folderLabel(BackupFolderKind.download),
              body: 'Mudah ditemukan di aplikasi Berkas. Tetap ada walau '
                  'aplikasi dicopot.',
              badge: 'Disarankan',
              onTap: () => _choose('download'),
            ),
            _option(
              icon: Icons.description_outlined,
              title: folderLabel(BackupFolderKind.documents),
              body: 'Sama amannya dengan Download, terpisah dari unduhan '
                  'lain.',
              onTap: () => _choose('documents'),
            ),
            _option(
              icon: Icons.drive_folder_upload_outlined,
              title: 'Pilih folder lain',
              body: 'Harus berada di dalam Download atau Documents. Android '
                  'tidak mengizinkan aplikasi menulis di folder lain.',
              onTap: _pickOther,
            ),
            _option(
              icon: Icons.phone_android_outlined,
              title: folderLabel(BackupFolderKind.app),
              body: 'Tidak perlu izin apa pun, tapi ikut terhapus bila '
                  'aplikasi dicopot.',
              onTap: () => _choose(''),
            ),
            if (_busy) ...[
              const SizedBox(height: AppSpacing.md),
              const LinearProgressIndicator(),
            ],
            if (_problem != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  _problem!,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _option({
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onTap,
    String? badge,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        enabled: !_busy,
        onTap: onTap,
        leading: Icon(icon, color: scheme.primary),
        title: Row(
          children: [
            Flexible(child: Text(title)),
            if (badge != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(body),
      ),
    );
  }
}
