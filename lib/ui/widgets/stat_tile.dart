import 'package:flutter/material.dart';

import '../../core/design_system.dart';

/// Kotak angka di beranda, laporan, dan shift.
///
/// Satu angka besar, satu label kecil. Angka panjang dikecilkan otomatis
/// supaya "Rp 12.345.678" tidak terpotong di layar 5 inci.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.highlight = false,
    this.onTap,
    this.trend,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool highlight;
  final VoidCallback? onTap;

  /// Keterangan singkat di bawah angka, misalnya perbandingan periode.
  final String? trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final foreground =
        highlight ? scheme.onPrimaryContainer : scheme.onSurface;
    final muted = highlight
        ? scheme.onPrimaryContainer.withValues(alpha: 0.75)
        : scheme.onSurfaceVariant;

    return Card(
      color: highlight ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: muted),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: 24,
                    color: foreground,
                  ),
                ),
              ),
              if (trend != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  trend!,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lencana status cucian dan status bayar.
///
/// Kadar warnanya diambil dari tema, karena warna pekat yang enak dibaca
/// di latar putih jadi menyilaukan di latar gelap.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
    this.icon,
  });

  final String label;
  final Color color;
  final bool compact;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tint = context.status.onStatusTint;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: tint),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: tint * 2.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 12 : 14, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
