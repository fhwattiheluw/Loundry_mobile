import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Logo Laundry Manise dengan riak air yang berdenyut pelan di belakangnya.
///
/// Riaknya sengaja lambat dan tipis. Layar masuk dilihat puluhan kali sehari
/// oleh orang yang sedang buru-buru; animasi yang mencolok akan terasa
/// menghalangi setelah hari kedua.
class AnimatedAppLogo extends StatefulWidget {
  const AnimatedAppLogo({super.key, this.size = 104});

  final double size;

  @override
  State<AnimatedAppLogo> createState() => _AnimatedAppLogoState();
}

class _AnimatedAppLogoState extends State<AnimatedAppLogo>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void initState() {
    super.initState();
    // Pengulangan dinyalakan di frame pertama, bukan di sini, supaya bisa
    // dibatalkan bila pengguna mematikan animasi di setelan Android.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!MediaQuery.of(context).disableAnimations) _ripple.repeat();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = MediaQuery.of(context).disableAnimations;

    final grow = CurvedAnimation(parent: _entrance, curve: Curves.easeOutBack);
    final fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);

    final logo = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.size * 0.22),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Image.asset(
        'assets/brand/logo.png',
        width: widget.size,
        height: widget.size,
        // Logo gagal dimuat tidak boleh membuat layar masuk kosong, karena
        // tanpa layar ini kasir tidak bisa bekerja sama sekali.
        errorBuilder: (context, _, __) => Icon(
          Icons.local_laundry_service_outlined,
          size: widget.size * 0.7,
          color: scheme.primary,
        ),
      ),
    );

    return SizedBox(
      width: widget.size * 2,
      height: widget.size * 1.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!reduced)
            AnimatedBuilder(
              animation: _ripple,
              builder: (context, _) => CustomPaint(
                size: Size(widget.size * 2, widget.size * 1.6),
                painter: _RipplePainter(
                  progress: _ripple.value,
                  color: scheme.primary,
                  innerRadius: widget.size * 0.6,
                ),
              ),
            ),
          FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.72, end: 1).animate(grow),
              child: logo,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dua lingkaran yang melebar bergantian, seperti riak di permukaan air.
class _RipplePainter extends CustomPainter {
  const _RipplePainter({
    required this.progress,
    required this.color,
    required this.innerRadius,
  });

  final double progress;
  final Color color;
  final double innerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (var i = 0; i < 2; i++) {
      // Riak kedua tertinggal setengah putaran dari yang pertama.
      final t = (progress + i * 0.5) % 1.0;
      final radius = innerRadius + t * innerRadius * 0.9;
      final opacity = (1 - t) * 0.28;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: math.max(0, opacity)),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.progress != progress || old.color != color;
}
