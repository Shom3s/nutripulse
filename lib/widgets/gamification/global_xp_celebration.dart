import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class GlobalXpCelebration {
  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required int xp,
    required String title,
  }) {
    if (xp <= 0) return;

    try {
      _entry?.remove();
    } catch (_) {}

    HapticFeedback.mediumImpact();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (_) => _CelebrationPopup(xp: xp, title: title),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (_entry != null) {
          overlay.insert(_entry!);
        }
      } catch (_) {}
    });

    Future.delayed(const Duration(milliseconds: 2200), () {
      try {
        _entry?.remove();
      } catch (_) {}

      _entry = null;
    });
  }
}

class _CelebrationPopup extends StatefulWidget {
  final int xp;
  final String title;

  const _CelebrationPopup({required this.xp, required this.title});

  @override
  State<_CelebrationPopup> createState() => _CelebrationPopupState();
}

class _CelebrationPopupState extends State<_CelebrationPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  late Animation<double> _scale;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  static const Color lime = Color(0xFFD6FF60);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _scale = Tween<double>(
      begin: 0.82,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slide = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 18),
              child: FadeTransition(
                opacity: _opacity,
                child: SlideTransition(
                  position: _slide,
                  child: ScaleTransition(
                    scale: _scale,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.88,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF171C15).withOpacity(0.94),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: lime.withOpacity(0.22),
                                blurRadius: 28,
                                spreadRadius: 1,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: lime,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Colors.black,
                                  size: 28,
                                ),
                              ),

                              const SizedBox(width: 16),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      '+${widget.xp} XP Earned',
                                      style: GoogleFonts.outfit(
                                        color: lime,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
