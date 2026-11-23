import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/security.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../widgets/layout.dart';

class UserSettingsScreen extends ConsumerStatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  ConsumerState<UserSettingsScreen> createState() =>
      _UserSettingsScreenState();
}

class _UserSettingsScreenState extends ConsumerState<UserSettingsScreen> {
  List<AppUser> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await ref.read(userRepoProvider).all();
    if (mounted) setState(() => _users = users);
  }

  /// Membuat kode pemulihan baru dan menampilkannya satu kali.
  ///
  /// Kode lama langsung mati begitu yang baru dibuat, jadi dikonfirmasi
  /// dulu: pemilik yang masih menyimpan catatan lama tidak boleh
  /// kehilangannya karena salah ketuk.
  Future<void> _regenerateRecoveryCode() async {
    final recovery = ref.read(pinRecoveryProvider);

    if (recovery.hasRecoveryCode) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Buat kode pemulihan baru?'),
          content: const Text(
              'Kode lama langsung tidak berlaku. Pastikan Anda mencatat '
              'yang baru.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Buat baru'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }

    final code = await recovery.generateRecoveryCode();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.key_outlined),
        title: const Text('Catat kode ini'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tidak bisa dilihat lagi setelah layar ini ditutup.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kode disalin.')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Salin'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Saya sudah mencatat'),
          ),
        ],
      ),
    );

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengguna dan PIN')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addUser,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Tambah kasir'),
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Setiap transaksi menyimpan siapa yang membuatnya. Beri PIN '
                'berbeda untuk tiap kasir supaya selisih kas bisa dilacak.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            // Kode pemulihan hanya berguna bila pemilik tahu ia ada. Ditaruh
            // di atas daftar pengguna, bukan terkubur di bawahnya.
            Card(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ListTile(
                leading: const IconBadge(Icons.key_outlined, tone: 11),
                title: const Text('Kode pemulihan PIN'),
                subtitle: Text(
                  ref.read(pinRecoveryProvider).hasRecoveryCode
                      ? 'Sudah dibuat. Buat baru bila catatannya hilang.'
                      : 'Belum ada. Buat sekarang dan catat di tempat aman.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _regenerateRecoveryCode,
              ),
            ),

            for (final user in _users) ...[
              ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    user.isOwner ? Icons.admin_panel_settings : Icons.person,
                  ),
                ),
                title: Text(user.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(user.role.label),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'pin') {
                      await _resetPin(user);
                    } else {
                      await _deactivate(user);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'pin', child: Text('Ganti PIN')),
                    PopupMenuItem(
                        value: 'off', child: Text('Nonaktifkan akun')),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Alasan sebuah PIN tidak boleh dipakai, atau null bila boleh.
  ///
  /// Login hanya memakai PIN, tanpa nama pengguna. Dua orang dengan PIN yang
  /// sama membuat aplikasi menebak salah satunya, dan kasir bisa masuk
  /// sebagai Owner. Karena itu PIN harus unik, juga saat PIN diganti.
  Future<String?> _pinProblem(String pin, {int? exceptUserId}) async {
    if (pin.length < 4) return 'PIN minimal 4 digit.';

    final holder = await ref.read(userRepoProvider).authenticate(pin);
    if (holder != null && holder.id != exceptUserId) {
      return 'PIN itu sudah dipakai pengguna lain. Pilih PIN yang berbeda.';
    }
    return null;
  }

  Future<void> _addUser() async {
    final nameController = TextEditingController();
    final pinController = TextEditingController();
    var role = UserRole.kasir;

    // Galat tampil di dalam dialog, di samping kolomnya. Kalau dialog
    // ditutup dulu baru diperiksa, nama dan PIN yang sudah diketik hilang.
    String? nameError;
    String? pinError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tambah pengguna'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nama',
                  errorText: nameError,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'PIN (4-6 digit)',
                  counterText: '',
                  errorText: pinError,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in UserRole.values)
                    ChoiceChip(
                      label: Text(value.label),
                      selected: role == value,
                      onSelected: (_) => setDialogState(() => role = value),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final nameProblem = nameController.text.trim().isEmpty
                    ? 'Nama wajib diisi.'
                    : null;
                final pinProblem =
                    await _pinProblem(pinController.text.trim());

                if (nameProblem != null || pinProblem != null) {
                  setDialogState(() {
                    nameError = nameProblem;
                    pinError = pinProblem;
                  });
                  return;
                }

                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final name = nameController.text.trim();
    final pin = pinController.text.trim();

    await ref.read(userRepoProvider).insert(
          AppUser(name: name, pinHash: hashPin(pin), role: role),
        );

    await _load();
    _snack('$name ditambahkan.');
  }

  Future<void> _resetPin(AppUser user) async {
    final controller = TextEditingController();
    String? pinError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Ganti PIN ${user.name}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'PIN baru (4-6 digit)',
              counterText: '',
              errorText: pinError,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                // PIN lama pengguna ini sendiri boleh dipakai lagi; yang
                // ditolak hanya PIN milik orang lain.
                final problem = await _pinProblem(
                  controller.text.trim(),
                  exceptUserId: user.id,
                );

                if (problem != null) {
                  setDialogState(() => pinError = problem);
                  return;
                }

                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    await ref.read(userRepoProvider).setPin(user.id!, controller.text.trim());
    await _load();
    _snack('PIN ${user.name} diganti.');
  }

  Future<void> _deactivate(AppUser user) async {
    final repo = ref.read(userRepoProvider);

    if (user.id == ref.read(currentUserProvider).id) {
      _snack('Anda sedang masuk dengan akun ini. Masuk sebagai Owner lain '
          'untuk menonaktifkannya.');
      return;
    }

    if (user.isOwner && await repo.isLastOwner(user.id!)) {
      _snack('Ini satu-satunya Owner. Buat Owner lain dulu sebelum '
          'menonaktifkan.');
      return;
    }

    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nonaktifkan ${user.name}?'),
        content: const Text(
          'Akun ini tidak bisa masuk lagi. Riwayat transaksinya tetap '
          'tersimpan di laporan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (yes != true) return;

    await repo.deactivate(user.id!);
    await _load();
    _snack('${user.name} dinonaktifkan.');
  }
}
