import 'package:material_ui/material_ui.dart';

/// Tata nilai desain aplikasi.
///
/// Semua angka jarak, sudut, dan ukuran huruf berasal dari sini. Tanpa satu
/// sumber seperti ini, tiap layar perlahan memakai angka sendiri dan
/// aplikasi terlihat seperti dikerjakan beberapa orang yang tidak bicara.
abstract final class AppSpacing {
  /// Kelipatan 4. Angka di luar daftar ini tidak dipakai.
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// Jarak tepi layar. Di layar lebar diberi lebih lega.
  static const screenPhone = 16.0;
  static const screenTablet = 24.0;
}

abstract final class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

/// Ukuran jendela mengikuti pembagian Material 3.
///
/// Dipakai apa adanya, bukan diotak-atik, supaya perilaku aplikasi sama
/// dengan aplikasi Android lain yang sudah dikenal pengguna.
enum WindowSize {
  /// HP tegak.
  compact,

  /// HP mendatar, tablet kecil.
  medium,

  /// Tablet besar.
  expanded;

  static WindowSize of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return WindowSize.compact;
    if (width < 905) return WindowSize.medium;
    return WindowSize.expanded;
  }

  bool get isCompact => this == WindowSize.compact;
  bool get isWide => this != WindowSize.compact;
}

extension WindowSizeContext on BuildContext {
  WindowSize get windowSize => WindowSize.of(this);
  bool get isWide => windowSize.isWide;

  /// Jarak tepi yang menyesuaikan lebar layar.
  double get screenPadding =>
      isWide ? AppSpacing.screenTablet : AppSpacing.screenPhone;

  /// Jumlah kolom untuk daftar kartu.
  int get gridColumns => switch (windowSize) {
        WindowSize.compact => 1,
        WindowSize.medium => 2,
        WindowSize.expanded => 3,
      };
}

/// Ukuran sentuh minimum.
///
/// Kasir sering memakai aplikasi ini sambil berdiri, dengan tangan basah,
/// dan buru-buru. Tombol kecil bukan sekadar kurang nyaman di sini:
/// salah tekan berarti salah nota.
abstract final class AppTouch {
  static const minimum = 48.0;
  static const comfortable = 56.0;
  static const primary = 64.0;
}

/// Bayangan lembut untuk kartu dan bilah navigasi.
///
/// Sengaja tipis dan berwarna teal gelap, bukan hitam: bayangan hitam
/// membuat tampilan terasa berat dan kusam.
abstract final class AppShadow {
  static List<BoxShadow> soft(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) return const [];
    return [
      BoxShadow(
        color: const Color(0xFF004D40).withValues(alpha: 0.07),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];
  }
}

/// Gradasi merek: teal dalam ke teal cerah.
abstract final class AppGradient {
  static LinearGradient brand(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? const [Color(0xFF004D40), Color(0xFF00796B)]
          : const [Color(0xFF00574B), Color(0xFF00897B)],
    );
  }
}

abstract final class AppDuration {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 360);
}

/// Warna yang membawa arti, bukan sekadar hiasan.
///
/// Dibuat berpasangan terang dan gelap supaya mode gelap tidak perlu
/// ditambal belakangan di tiap layar.
class StatusPalette extends ThemeExtension<StatusPalette> {
  const StatusPalette({
    required this.diterima,
    required this.diproses,
    required this.selesai,
    required this.diambil,
    required this.dibatalkan,
    required this.lunas,
    required this.belumLunas,
    required this.onStatusTint,
  });

  final Color diterima;
  final Color diproses;
  final Color selesai;
  final Color diambil;
  final Color dibatalkan;
  final Color lunas;
  final Color belumLunas;

  /// Kadar transparansi latar lencana status.
  final double onStatusTint;

  static const light = StatusPalette(
    // Kuning tua, bukan abu kebiruan. Di daftar order, abu-abu di atas
    // kartu abu-abu membuat semua baris terlihat sama dari jarak satu meja.
    diterima: Color(0xFF9A6300),
    diproses: Color(0xFF1565C0),
    selesai: Color(0xFF2E7D32),
    diambil: Color(0xFF6D4C41),
    dibatalkan: Color(0xFFC62828),
    lunas: Color(0xFF2E7D32),
    belumLunas: Color(0xFFC62828),
    onStatusTint: 0.12,
  );

  /// Di latar gelap, warna pekat jadi sulit dibaca. Semua naik ke nada
  /// yang lebih terang, dan kadar latarnya diturunkan.
  static const dark = StatusPalette(
    diterima: Color(0xFFFFCC80),
    diproses: Color(0xFF82B1FF),
    selesai: Color(0xFF81C784),
    diambil: Color(0xFFBCAAA4),
    dibatalkan: Color(0xFFEF9A9A),
    lunas: Color(0xFF81C784),
    belumLunas: Color(0xFFEF9A9A),
    onStatusTint: 0.18,
  );

  Color forStatus(String status) => switch (status) {
        'diterima' => diterima,
        'diproses' => diproses,
        'selesai' => selesai,
        'diambil' => diambil,
        'dibatalkan' => dibatalkan,
        _ => diterima,
      };

  @override
  StatusPalette copyWith({
    Color? diterima,
    Color? diproses,
    Color? selesai,
    Color? diambil,
    Color? dibatalkan,
    Color? lunas,
    Color? belumLunas,
    double? onStatusTint,
  }) =>
      StatusPalette(
        diterima: diterima ?? this.diterima,
        diproses: diproses ?? this.diproses,
        selesai: selesai ?? this.selesai,
        diambil: diambil ?? this.diambil,
        dibatalkan: dibatalkan ?? this.dibatalkan,
        lunas: lunas ?? this.lunas,
        belumLunas: belumLunas ?? this.belumLunas,
        onStatusTint: onStatusTint ?? this.onStatusTint,
      );

  @override
  StatusPalette lerp(ThemeExtension<StatusPalette>? other, double t) {
    if (other is! StatusPalette) return this;
    return StatusPalette(
      diterima: Color.lerp(diterima, other.diterima, t)!,
      diproses: Color.lerp(diproses, other.diproses, t)!,
      selesai: Color.lerp(selesai, other.selesai, t)!,
      diambil: Color.lerp(diambil, other.diambil, t)!,
      dibatalkan: Color.lerp(dibatalkan, other.dibatalkan, t)!,
      lunas: Color.lerp(lunas, other.lunas, t)!,
      belumLunas: Color.lerp(belumLunas, other.belumLunas, t)!,
      onStatusTint: onStatusTint + (other.onStatusTint - onStatusTint) * t,
    );
  }
}

extension StatusPaletteContext on BuildContext {
  StatusPalette get status =>
      Theme.of(this).extension<StatusPalette>() ?? StatusPalette.light;
}
