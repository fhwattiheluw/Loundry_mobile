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

    final foreground = highlight ? Colors.white : scheme.onSurface;
    final muted = highlight
        ? Colors.white.withValues(alpha: 0.78)
        : scheme.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        gradient: highlight ? AppGradient.brand(context) : null,
        color: highlight ? null : scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: highlight
            ? null
            : Border.all(color: theme.dividerTheme.color ?? Colors.black12),
        boxShadow: AppShadow.soft(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: highlight
                              ? Colors.white.withValues(alpha: 0.18)
                              : scheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Icon(
                          icon,
                          size: 18,
                          color: highlight ? Colors.white : scheme.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontSize: highlight ? 30 : 24,
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
