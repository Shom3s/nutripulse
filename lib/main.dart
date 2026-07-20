import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';

import 'screens/welcome/welcome_screen.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/health/health_monitor_screen.dart';
import 'screens/notifications/daily_report_detail_screen.dart';
import 'screens/settings/app_settings_screen.dart';
import 'screens/calendar/health_calendar_diary_screen.dart';
import 'services/gamification_service.dart';
import 'services/notification_service.dart';
import 'theme/nutripulse_theme_controller.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  NotificationService.navigatorKey = navigatorKey;
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await NotificationService.instance.init();
  await NotificationService.instance.scheduleEnabledLocalNotifications();

  await nutriThemeController.load();

  runApp(const NutriPulseApp());
}

class NutriPulseApp extends StatefulWidget {
  const NutriPulseApp({super.key});

  @override
  State<NutriPulseApp> createState() => _NutriPulseAppState();
}

class _NutriPulseAppState extends State<NutriPulseApp> {
  StreamSubscription<Map<String, dynamic>>? _rewardSub;
  Timer? _hideTimer;

  Map<String, dynamic>? _reward;
  int _rewardKey = 0;

  @override
  void initState() {
    super.initState();

    _rewardSub = GamificationService.rewardStream.listen((event) {
      final xp = event['awardedXp'];
      final xpValue = xp is num ? xp.toInt() : 0;
      if (xpValue <= 0) return;

      HapticFeedback.mediumImpact();

      setState(() {
        _reward = event;
        _rewardKey++;
      });

      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(milliseconds: 2300), () {
        if (!mounted) return;
        setState(() => _reward = null);
      });
    });
  }

  @override
  void dispose() {
    _rewardSub?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: nutriThemeController,
      builder: (context, _) {
        final appTheme = nutriThemeController.materialTheme();
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'NutriPulse',
          theme: appTheme.copyWith(
            textTheme: GoogleFonts.outfitTextTheme(appTheme.textTheme),
          ),
          builder: (context, child) {
            return Stack(
              children: [
                child ?? const SizedBox.shrink(),

                if (_reward != null)
                  _GlobalRewardBanner(
                    key: ValueKey(_rewardKey),
                    xp: (_reward!['awardedXp'] is num)
                        ? (_reward!['awardedXp'] as num).toInt()
                        : 0,
                    title: _reward!['title']?.toString() ?? 'XP Earned',
                    levelUp: _reward!['levelUp'] == true,
                  ),
              ],
            );
          },
          home: const AuthGate(),
          routes: {
            '/welcome': (context) => const WelcomeScreen(),
            '/onboarding': (context) => const OnboardingFlow(),
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            '/dashboard': (context) => const DashboardScreen(),
            '/health-monitor': (context) => const HealthMonitorScreen(),
            '/daily-report': (context) => const DailyReportDetailScreen(),
            '/app-settings': (context) => const AppSettingsScreen(),
            '/health-calendar': (context) => const HealthCalendarDiaryScreen(),
          },
        );
      },
    );
  }
}

class _GlobalRewardBanner extends StatefulWidget {
  const _GlobalRewardBanner({
    super.key,
    required this.xp,
    required this.title,
    required this.levelUp,
  });

  final int xp;
  final String title;
  final bool levelUp;

  @override
  State<_GlobalRewardBanner> createState() => _GlobalRewardBannerState();
}

class _GlobalRewardBannerState extends State<_GlobalRewardBanner>
    with TickerProviderStateMixin {
  static const Color lime = Color(0xFFD6FF60);

  late final AnimationController _controller;
  late final AnimationController _countController;

  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;
  late final Animation<int> _xpCounter;

  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    _countController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _scale = Tween<double>(
      begin: 0.86,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _slide = Tween<Offset>(
      begin: const Offset(0, -0.20),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _xpCounter = IntTween(begin: 0, end: widget.xp).animate(
      CurvedAnimation(parent: _countController, curve: Curves.easeOutCubic),
    );

    _controller.forward();
    _countController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return IgnorePointer(
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: RepaintBoundary(
            child: Stack(
              children: [
                ...List.generate(10, (i) => _animatedParticle(width, i)),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: ScaleTransition(
                          scale: _scale,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: lime.withOpacity(0.24),
                                  blurRadius: 22,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(30),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  width: width * 0.89,
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        const Color(
                                          0xFF1C2318,
                                        ).withOpacity(0.96),
                                        const Color(
                                          0xFF131811,
                                        ).withOpacity(0.94),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.08),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFFE7FF85),
                                              Color(0xFFD6FF60),
                                              Color(0xFFAEEA32),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: lime.withOpacity(0.30),
                                              blurRadius: 18,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          widget.levelUp
                                              ? Icons.workspace_premium_rounded
                                              : Icons.auto_awesome_rounded,
                                          color: Colors.black,
                                          size: 30,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.levelUp
                                                  ? 'LEVEL UP!'
                                                  : widget.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.outfit(
                                                color: Colors.white,
                                                fontSize: 19,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: -0.4,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            AnimatedBuilder(
                                              animation: _xpCounter,
                                              builder: (_, __) {
                                                return Text(
                                                  '+${_xpCounter.value} XP Earned',
                                                  style: GoogleFonts.outfit(
                                                    color: lime,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                );
                                              },
                                            ),
                                            if (widget.levelUp) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                'New level unlocked',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white
                                                      .withOpacity(0.68),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _animatedParticle(double width, int index) {
    final left = 20 + _random.nextDouble() * (width - 40);
    final top = 8 + _random.nextDouble() * 110;
    final size = 3 + _random.nextDouble() * 5;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 760 + _random.nextInt(420)),
      curve: Curves.easeOut,
      builder: (_, value, __) {
        return Positioned(
          left: left,
          top: top - (value * 20),
          child: Opacity(
            opacity: 1 - value,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.72),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: lime.withOpacity(0.30), blurRadius: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingScreen();
        }

        if (snapshot.hasData && snapshot.data != null) {
          return const DashboardScreen();
        }

        return const WelcomeScreen();
      },
    );
  }
}

class AppLoadingScreen extends StatelessWidget {
  const AppLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF10150D),
      body: Center(child: CircularProgressIndicator(color: Color(0xFFD6FF60))),
    );
  }
}
