import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = '✨',
    this.duration = const Duration(milliseconds: 1900),
  });

  final String title;
  final String subtitle;
  final String icon;
  final Duration duration;

  static void show(
    BuildContext context, {
    required String title,
    required String subtitle,
    String icon = '✨',
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) =>
          CelebrationOverlay(title: title, subtitle: subtitle, icon: icon),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 2100), () {
      if (entry.mounted) entry.remove();
    });
  }

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final fadeIn = Curves.easeOutCubic.transform(
              (t / 0.18).clamp(0, 1),
            );
            final fadeOut =
                1 -
                Curves.easeInCubic.transform(((t - 0.78) / 0.22).clamp(0, 1));
            final opacity = (fadeIn * fadeOut).clamp(0.0, 1.0);
            return Opacity(
              opacity: opacity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _ConfettiPainter(progress: t)),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Transform.translate(
                      offset: Offset(0, 54 - (18 * fadeIn)),
                      child: Transform.scale(
                        scale: 0.94 + (0.06 * fadeIn),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 22),
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141A11).withOpacity(0.96),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: const Color(0xFFD6FF60).withOpacity(0.25),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFD6FF60,
                                ).withOpacity(0.22),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.35),
                                blurRadius: 30,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD6FF60),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Center(
                                  child: Text(
                                    widget.icon,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      widget.subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFFB7C2A8),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(12);
    final colors = [
      const Color(0xFFD6FF60),
      const Color(0xFFE8FF8A),
      Colors.white.withOpacity(0.9),
      const Color(0xFFB7C2A8),
    ];
    for (int i = 0; i < 44; i++) {
      final startX = random.nextDouble() * size.width;
      final fall =
          Curves.easeOut.transform(progress) *
          (120 + random.nextDouble() * 180);
      final sway =
          math.sin((progress * math.pi * 2) + i) *
          (12 + random.nextDouble() * 18);
      final y = 20 + fall + random.nextDouble() * 70;
      final paint = Paint()
        ..color = colors[i % colors.length].withOpacity(
          (1 - progress).clamp(0.0, 0.85),
        );
      final rect = Rect.fromCenter(
        center: Offset(startX + sway, y),
        width: 4 + random.nextDouble() * 5,
        height: 8 + random.nextDouble() * 8,
      );
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(progress * math.pi * 2 + i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: rect.width,
            height: rect.height,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
