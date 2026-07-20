import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _entryController;
  late AnimationController _heartController;
  late AnimationController _buttonController;

  late Animation<double> _fade;
  late Animation<Offset> _slide;
  late Animation<double> _heartBeat;
  late Animation<double> _buttonScale;

  static const lime = Color(0xFFCCFF45);
  static const dark = Color(0xFF10150D);
  static const softText = Color(0xFFBFC9B5);

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);

    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );

    _fade = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);

    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
        );

    _heartBeat =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.00, end: 1.08), weight: 25),
          TweenSequenceItem(tween: Tween(begin: 1.08, end: 0.98), weight: 25),
          TweenSequenceItem(tween: Tween(begin: 0.98, end: 1.04), weight: 20),
          TweenSequenceItem(tween: Tween(begin: 1.04, end: 1.00), weight: 30),
        ]).animate(
          CurvedAnimation(parent: _heartController, curve: Curves.easeInOut),
        );

    _buttonScale = _buttonController;

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _heartController.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  void _goToOnboarding() async {
    await _buttonController.reverse();
    await _buttonController.forward();

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dark,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.35,
            colors: [Color(0xFF2B3A19), Color(0xFF10150D), Color(0xFF070907)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 190,
                          height: 190,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: lime.withOpacity(0.05),
                            boxShadow: [
                              BoxShadow(
                                color: lime.withOpacity(0.16),
                                blurRadius: 80,
                                spreadRadius: 12,
                              ),
                            ],
                          ),
                        ),
                        ScaleTransition(
                          scale: _heartBeat,
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 148,
                            height: 148,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),

                    Text(
                      'Monitor Your Health,\nTrack Your Nutrition',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 33,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'Smart health tracking, AI meal scanning, and personalized nutrition guidance in one simple app.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: softText,
                        fontSize: 15.5,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 30),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          _miniInfo(Icons.favorite_rounded, 'Health'),
                          _divider(),
                          _miniInfo(Icons.restaurant_rounded, 'Meals'),
                          _divider(),
                          _miniInfo(Icons.auto_awesome_rounded, 'AI Guide'),
                        ],
                      ),
                    ),

                    const Spacer(flex: 3),

                    ScaleTransition(
                      scale: _buttonScale,
                      child: GestureDetector(
                        onTap: _goToOnboarding,
                        child: Container(
                          width: double.infinity,
                          height: 64,
                          decoration: BoxDecoration(
                            color: lime,
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: lime.withOpacity(0.28),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Get Started',
                                style: GoogleFonts.outfit(
                                  color: Colors.black,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.black,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    GestureDetector(
                      onTap: () {
                        Navigator.pushNamed(context, '/login');
                      },
                      child: Container(
                        width: double.infinity,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Existing User? Login',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniInfo(IconData icon, String text) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: lime, size: 23),
          const SizedBox(height: 7),
          Text(
            text,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 38,
      color: Colors.white.withOpacity(0.09),
    );
  }
}
