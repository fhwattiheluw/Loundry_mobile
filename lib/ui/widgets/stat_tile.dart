import 'package:flutter/material.dart';

/// Kotak angka di beranda dan laporan.
///
/// Satu angka besar, satu label kecil. Angka yang panjang dikecilkan otomatis
/// supaya "Rp 12.345.678" tidak terpotong di layar 5 inci.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.highlight = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: highlight ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lencana status cucian dan status bayar.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
