import 'package:material_ui/material_ui.dart';

import '../../core/design_system.dart';
import 'layout.dart';

/// Makna sebuah tombol, bukan warnanya.
///
/// Kasir mengenali tombol dari warnanya sebelum sempat membaca labelnya,
/// jadi warna dipakai konsisten di seluruh aplikasi: hijau tosca untuk
/// melangkah maju, kuning untuk apa pun yang menyangkut uang, garis tepi
/// untuk aksi pendukung, merah untuk yang merugikan bila salah tekan.
enum ActionKind { primary, money, neutral, danger }

class AppAction {
  const AppAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.kind = ActionKind.neutral,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final ActionKind kind;
  final bool busy;
}

/// Tumpukan tombol aksi yang menempel di bawah layar.
///
/// [primary] digambar selebar layar dan bertumpuk, satu aksi satu baris,
/// karena inilah yang ditekan sambil berdiri. [secondary] dipadatkan jadi
/// satu baris berisi dua sampai tiga tombol bergaris tepi: tetap terlihat
/// tanpa menyaingi aksi utama, dan tidak lagi bersembunyi di menu tiga titik
/// yang jarang dibuka orang.
class ActionStack extends StatelessWidget {
  const ActionStack({
    super.key,
    this.primary = const [],
    this.secondary = const [],
  });

  final List<AppAction> primary;
  final List<AppAction> secondary;

  @override
  Widget build(BuildContext context) {
    if (primary.isEmpty && secondary.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
          // Di tablet tombol tidak ikut melebar sampai ujung layar; lebarnya
          // disamakan dengan isi halaman di atasnya.
          child: ContentWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (secondary.isNotEmpty)
                  Row(
                    children: [
                      for (var i = 0; i < secondary.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.sm),
                        Expanded(child: _button(context, secondary[i], true)),
                      ],
                    ],
                  ),
                for (var i = 0; i < primary.length; i++) ...[
                  if (i > 0 || secondary.isNotEmpty)
                    const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: _button(context, primary[i], false),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(BuildContext context, AppAction action, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.status;
    final height = compact ? AppTouch.minimum : AppTouch.comfortable;

    final icon = action.busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(action.icon, size: compact ? 18 : 20);

    final label = Text(
      action.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final onPressed = action.busy ? null : action.onPressed;

    return switch (action.kind) {
      ActionKind.neutral => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, height),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          onPressed: onPressed,
          icon: icon,
          label: label,
        ),
      ActionKind.primary => FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: Size(0, height)),
          onPressed: onPressed,
          icon: icon,
          label: label,
        ),
      // Kuning dengan tulisan gelap: menonjol tanpa tertukar dengan tombol
      // utama, dan tetap terbaca di layar HP murah yang pucat.
      ActionKind.money => FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: Size(0, height),
            backgroundColor: palette.belumLunas,
            foregroundColor: Colors.black.withValues(alpha: 0.87),
          ),
          onPressed: onPressed,
          icon: icon,
          label: label,
        ),
      ActionKind.danger => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, height),
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
          ),
          onPressed: onPressed,
          icon: icon,
          label: label,
        ),
    };
  }
}
