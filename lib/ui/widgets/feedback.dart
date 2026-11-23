import 'package:material_ui/material_ui.dart';

import '../../core/design_system.dart';

/// Konfirmasi dan umpan balik yang seragam.
///
/// Sebelum ini tiap layar menulis dialognya sendiri, dengan kata tombol yang
/// berbeda-beda ("Ya", "OK", "Lanjut"). Di sini tombol selalu memakai kata
/// kerja yang menjelaskan akibatnya, dan aksi yang merusak diberi warna
/// merah supaya tidak tertekan sambil lalu.

/// Meminta persetujuan sebelum aksi yang sulit dibatalkan.
///
/// Mengembalikan true hanya bila pengguna menekan tombol konfirmasi.
/// Menutup dialog dengan menyentuh luar atau tombol kembali berarti batal.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Batal',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;

      return AlertDialog(
        icon: icon == null ? null : Icon(icon),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );

  return result ?? false;
}

/// Menampilkan satu pesan singkat, menggantikan pesan sebelumnya.
///
/// Bila ditumpuk, pesan lama harus habis dulu sebelum yang baru terbaca, dan
/// kasir yang menekan tombol dua kali melihat pesan yang sama berulang kali.
void showToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: actionLabel == null ? duration : const Duration(seconds: 8),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
}

/// Kotak penjelasan kecil di dalam formulir, untuk istilah yang tidak
/// diketahui orang awam. Lebih baik daripada menaruh teks panjang di bawah
/// setiap kolom, karena yang sudah paham tidak perlu membacanya lagi.
class HintBox extends StatelessWidget {
  const HintBox(this.text, {super.key, this.icon = Icons.lightbulb_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// Menahan tombol kembali bila ada isian yang belum disimpan.
///
/// Kasir yang sedang mengetik tiga layanan lalu tak sengaja menyentuh tombol
/// kembali kehilangan semuanya. Dialog ini hanya muncul bila memang ada yang
/// akan hilang, dan menutup layar langsung bila tidak ada.
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.hasChanges,
    required this.child,
    this.message = 'Isian yang belum disimpan akan hilang.',
  });

  /// Dicek saat tombol kembali ditekan, bukan saat layar digambar, jadi
  /// layar tidak perlu menggambar ulang setiap ada huruf yang diketik.
  final bool Function() hasChanges;
  final Widget child;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        final navigator = Navigator.of(context);

        if (!hasChanges()) {
          navigator.pop();
          return;
        }

        final leave = await confirmAction(
          context,
          title: 'Keluar tanpa menyimpan?',
          message: message,
          confirmLabel: 'Keluar',
          cancelLabel: 'Lanjut mengisi',
          destructive: true,
        );

        if (leave) navigator.pop();
      },
      child: child,
    );
  }
}
