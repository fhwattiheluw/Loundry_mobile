import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../application/providers.dart';
import '../../data/db/settings_keys.dart';
import '../../core/friendly_error.dart';
import '../widgets/layout.dart';

/// Logo usaha yang tercetak di kepala nota (FR-88).
class LogoSettingsScreen extends ConsumerStatefulWidget {
  const LogoSettingsScreen({super.key});

  @override
  ConsumerState<LogoSettingsScreen> createState() =>
      _LogoSettingsScreenState();
}

class _LogoSettingsScreenState extends ConsumerState<LogoSettingsScreen> {
  bool _busy = false;

  String get _path =>
      ref.read(settingsRepoProvider).get(SettingsKeys.receiptLogoPath);

  Future<void> _pick() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Logo nota dicetak selebar 300 titik, jadi gambar besar hanya
        // memperlambat tanpa menambah ketajaman.
        maxWidth: 600,
      );

      if (picked == null) {
        setState(() => _busy = false);
        return;
      }

      // Disalin ke folder aplikasi. Berkas di galeri bisa dihapus pemilik
      // kapan saja, dan nota akan kehilangan logonya tanpa penjelasan.
      final dir = await getApplicationDocumentsDirectory();
      final target = File(p.join(dir.path, 'logo_nota.png'));
      await File(picked.path).copy(target.path);

      await ref
          .read(settingsRepoProvider)
          .set(SettingsKeys.receiptLogoPath, target.path);

      ref.invalidate(settingsLoadedProvider);

      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Logo belum terpasang. ${friendlyError(e)}'),
        ),
      );
    }
  }

  Future<void> _remove() async {
    await ref.read(settingsRepoProvider).set(SettingsKeys.receiptLogoPath, '');
    ref.invalidate(settingsLoadedProvider);
    if (mounted) setState(() {});
  }

  Future<void> _testPrint() async {
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await ref.read(receiptBuilderProvider).buildTestPage();
    final result = await ref.read(printerProvider).printBytes(bytes, copies: 1);

    messenger.showSnackBar(
      SnackBar(content: Text(result.success ? 'Uji cetak dikirim.' : result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsLoadedProvider);
    final path = _path;
    final hasLogo = path.isNotEmpty && File(path).existsSync();

    return Scaffold(
      appBar: AppBar(title: const Text('Logo di nota')),
      body: ContentWidth(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (hasLogo)
                    // Pratinjau hitam putih, karena begitulah nanti
                    // tercetak di printer thermal.
                    ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.2126, 0.7152, 0.0722, 0, 0, //
                        0.2126, 0.7152, 0.0722, 0, 0, //
                        0.2126, 0.7152, 0.0722, 0, 0, //
                        0, 0, 0, 1, 0, //
                      ]),
                      child: Image.file(
                        File(path),
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    Column(
                      children: [
                        Icon(Icons.image_outlined,
                            size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 10),
                        Text('Belum ada logo',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(hasLogo ? 'Ganti logo' : 'Pilih logo dari galeri'),
          ),

          if (hasLogo) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _testPrint,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Uji cetak'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _busy ? null : _remove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus logo'),
            ),
          ],

          const SizedBox(height: 24),
          Text(
            'Printer thermal hanya mencetak hitam putih. Logo dengan garis '
            'tebal dan kontras tinggi hasilnya paling baik; logo berwarna '
            'lembut atau bergradasi biasanya tercetak jadi bercak abu-abu.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      )),
    );
  }
}
