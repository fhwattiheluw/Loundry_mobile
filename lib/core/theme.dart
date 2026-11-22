import 'package:flutter/material.dart';

/// Tema dirancang untuk konter: tombol besar, kontras tinggi, dan angka
/// yang terbaca sambil berdiri. Tombol utama minimal 48 dp (NFR-08).
abstract final class AppTheme {
  static const seed = Color(0xFF00695C);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.07)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  /// Warna status cucian. Dipakai konsisten di daftar dan detail order.
  static Color statusColor(String status, ColorScheme scheme) =>
      switch (status) {
        'diterima' => const Color(0xFF546E7A),
        'diproses' => const Color(0xFF1565C0),
        'selesai' => const Color(0xFF2E7D32),
        'diambil' => const Color(0xFF6D4C41),
        'dibatalkan' => const Color(0xFFC62828),
        _ => scheme.outline,
      };
}
