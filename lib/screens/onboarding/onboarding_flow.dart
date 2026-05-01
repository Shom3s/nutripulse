import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  @override
  void initState() {
    super.initState();
    _displayedTopProgress = currentTopProgress;
  }

  final PageController _pageController = PageController();

  int _index = 0;
  bool _loadingStarted = false;
  double _displayedTopProgress = 0.0;
  double _previousTopProgress = 0.0;

  String? gender;
  int workoutsPerWeek = 0;
  bool? usedOtherApps;

  bool useMetric = false;

  double heightCm = 177;
  double weightKg = 63;
  DateTime birthDate = DateTime(2003, 1, 1);

  String goal = '';
  double desiredWeightKg = 63;
  double weeklyRateKg = 0.8;

  String blocker = '';
  String diet = '';

  int get pageCount => 14;

  bool get showGlobalTopBar => _index < 12;

  double get currentTopProgress {
    if (_index <= 0) return 1 / 10;
    if (_index >= 9) return 1;
    return (_index + 1) / 10;
  }

  int get age {
    final now = DateTime.now();
    int years = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      years--;
    }
    return years.clamp(13, 80);
  }

  double get heightM => heightCm / 100;

  double get activityFactor {
    if (workoutsPerWeek <= 0) return 1.2;
    if (workoutsPerWeek <= 1) return 1.2;
    if (workoutsPerWeek <= 3) return 1.375;
    if (workoutsPerWeek <= 5) return 1.55;
    return 1.725;
  }

  double get bmr {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    if (gender == 'Male') return base + 5;
    if (gender == 'Female') return base - 161;
    return base - 80;
  }

  double get tdee => bmr * activityFactor;

  double get targetCalories {
    double result = tdee;
    if (goal == 'Lose weight') {
      result -= math.min(weeklyRateKg * 1000, 700);
    } else if (goal == 'Gain weight') {
      result += math.min(weeklyRateKg * 900, 650);
    }
    return result.clamp(1400, 4500);
  }

  double get proteinGrams {
    if (goal == 'Lose weight') return weightKg * 2.1;
    if (goal == 'Gain weight') return weightKg * 2.2;
    return weightKg * 1.8;
  }

  double get fatsGrams {
    return math.max((targetCalories * 0.25) / 9, 45);
  }

  double get carbsGrams {
    final remaining = targetCalories - (proteinGrams * 4) - (fatsGrams * 9);
    return math.max(remaining / 4, 80);
  }

  int get caloriesRounded => targetCalories.round();
  int get proteinRounded => proteinGrams.round();
  int get fatsRounded => fatsGrams.round();
  int get carbsRounded => carbsGrams.round();

  int get monthsToGoal {
    final diff = (desiredWeightKg - weightKg).abs();
    if (weeklyRateKg <= 0) return 3;
    final weeks = diff / weeklyRateKg;
    return math.max(1, (weeks / 4.0).ceil());
  }

  bool get canContinue {
    switch (_index) {
      case 0:
        return gender != null;
      case 1:
        return workoutsPerWeek > 0;
      case 2:
        return usedOtherApps != null;
      case 5:
        return goal.isNotEmpty;
      case 8:
        return blocker.isNotEmpty;
      case 9:
        return diet.isNotEmpty;
      default:
        return true;
    }
  }

  void next() {
    if (_index < pageCount - 1) {
      _pageController.animateToPage(
        _index + 1,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
  }

  void back() {
    if (_index > 0) {
      _pageController.animateToPage(
        _index - 1,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _startLoadingAndAdvance() async {
    if (_loadingStarted) return;
    _loadingStarted = true;
    await Future.delayed(const Duration(milliseconds: 3200));
    if (!mounted) return;
    next();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NPColors.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.34, 1.0],
            colors: [
              NPColors.bgTop,
              NPColors.bgMid,
              NPColors.bgBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
          children: [
            if (showGlobalTopBar)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                child: Row(
                  children: [
                    _BackCircle(onTap: back),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _PersistentTopProgress(
                        progress: _displayedTopProgress,
                        previousProgress: _previousTopProgress,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (value) {
                  setState(() {
                    _previousTopProgress = _displayedTopProgress;
                    _index = value;
                    _displayedTopProgress = currentTopProgress;
                  });
                  if (value == 12) {
                    _startLoadingAndAdvance();
                  }
                },
                children: [
            _QuestionScaffold(
              progress: 1 / 10,
              onBack: back,
              canContinue: canContinue,
              onContinue: next,
              title: 'Choose your Gender',
              subtitle: 'This will be used to calibrate your custom plan.',
              child: Column(
                children: [
                  _SelectionTile(
                    title: 'Male',
                    selected: gender == 'Male',
                    onTap: () => setState(() => gender = 'Male'),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: 'Female',
                    selected: gender == 'Female',
                    onTap: () => setState(() => gender = 'Female'),
                  ),
                ],
              ),
            ),
            _QuestionScaffold(
              progress: 2 / 10,
              onBack: back,
              canContinue: canContinue,
              onContinue: next,
              title: 'How many workouts\ndo you do per week?',
              subtitle: 'This will be used to calibrate your custom plan.',
              child: Column(
                children: [
                  _SelectionTile(
                    title: '0-2',
                    subtitle: 'Workouts now and then',
                    icon: Icons.circle,
                    selected: workoutsPerWeek > 0 && workoutsPerWeek <= 2,
                    onTap: () => setState(() => workoutsPerWeek = 2),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: '3-5',
                    subtitle: 'A few workouts per week',
                    icon: Icons.more_horiz,
                    selected: workoutsPerWeek >= 3 && workoutsPerWeek <= 5,
                    onTap: () => setState(() => workoutsPerWeek = 4),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: '6+',
                    subtitle: 'Dedicated athlete',
                    icon: Icons.grid_view_rounded,
                    selected: workoutsPerWeek >= 6,
                    onTap: () => setState(() => workoutsPerWeek = 6),
                  ),
                ],
              ),
            ),
            _QuestionScaffold(
              progress: 3 / 10,
              onBack: back,
              canContinue: canContinue,
              onContinue: next,
              title: 'Have you tried other\ncalorie tracking apps?',
              child: Column(
                children: [
                  _SelectionTile(
                    title: 'Yes',
                    icon: Icons.thumb_up_alt_rounded,
                    selected: usedOtherApps == true,
                    onTap: () => setState(() => usedOtherApps = true),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: 'No',
                    icon: Icons.thumb_down_alt_rounded,
                    selected: usedOtherApps == false,
                    onTap: () => setState(() => usedOtherApps = false),
                  ),
                ],
              ),
            ),
            _HeightWeightStep(
              progress: 4 / 10,
              onBack: back,
              onContinue: next,
              useMetric: useMetric,
              heightCm: heightCm,
              weightKg: weightKg,
              onUnitChanged: (v) => setState(() => useMetric = v),
              onHeightChanged: (v) => setState(() => heightCm = v),
              onWeightChanged: (v) => setState(() => weightKg = v),
            ),
            _BirthStep(
              progress: 5 / 10,
              onBack: back,
              onContinue: next,
              birthDate: birthDate,
              onChanged: (value) => setState(() => birthDate = value),
            ),
            _QuestionScaffold(
              progress: 6 / 10,
              onBack: back,
              canContinue: canContinue,
              onContinue: next,
              title: 'What is your goal?',
              subtitle: 'This helps us generate a plan for your calorie intake.',
              child: Column(
                children: [
                  _SelectionTile(
                    title: 'Lose weight',
                    selected: goal == 'Lose weight',
                    onTap: () => setState(() { goal = 'Lose weight'; if (desiredWeightKg >= weightKg) desiredWeightKg = math.max(35.0, weightKg - 1); }),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: 'Maintain',
                    selected: goal == 'Maintain',
                    onTap: () => setState(() { goal = 'Maintain'; desiredWeightKg = weightKg; }),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: 'Gain weight',
                    selected: goal == 'Gain weight',
                    onTap: () => setState(() { goal = 'Gain weight'; if (desiredWeightKg <= weightKg) desiredWeightKg = math.min(120.0, weightKg + 1); }),
                  ),
                ],
              ),
            ),
            _DesiredWeightStep(
              progress: 7 / 10,
              onBack: back,
              onContinue: next,
              goal: goal,
              currentWeightKg: weightKg,
              value: desiredWeightKg,
              onChanged: (v) {
                setState(() => desiredWeightKg = v);
              },
            ),
            _SpeedStep(
              progress: 8 / 10,
              onBack: back,
              onContinue: next,
              value: weeklyRateKg,
              monthsToGoal: monthsToGoal,
              caloriesRounded: caloriesRounded,
              onChanged: (v) {
                setState(() => weeklyRateKg = v);
              },
            ),
            _QuestionScaffold(
              progress: 9 / 10,
              onBack: back,
              canContinue: canContinue,
              onContinue: next,
              title: 'What’s stopping you\nfrom reaching your\ngoals?',
              child: Column(
                children: [
                  _SelectionTile(
                    title: 'Lack of consistency',
                    icon: Icons.bar_chart_rounded,
                    selected: blocker == 'Lack of consistency',
                    onTap: () => setState(() => blocker = 'Lack of consistency'),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: 'Unhealthy eating habits',
                    icon: Icons.lunch_dining_rounded,
                    selected: blocker == 'Unhealthy eating habits',
                    onTap: () => setState(() => blocker = 'Unhealthy eating habits'),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: 'Busy schedule',
                    icon: Icons.calendar_month_rounded,
                    selected: blocker == 'Busy schedule',
                    onTap: () => setState(() => blocker = 'Busy schedule'),
                  ),
                ],
              ),
            ),
            _QuestionScaffold(
              progress: 10 / 10,
              onBack: back,
              canContinue: canContinue,
              onContinue: next,
              title: 'Do you follow a\nspecific diet?',
              child: Column(
                children: [
                  _SelectionTile(
                    title: 'Classic',
                    icon: Icons.restaurant_rounded,
                    selected: diet == 'Classic',
                    onTap: () => setState(() => diet = 'Classic'),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: 'Pescatarian',
                    icon: Icons.set_meal_rounded,
                    selected: diet == 'Pescatarian',
                    onTap: () => setState(() => diet = 'Pescatarian'),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: 'Vegetarian',
                    icon: Icons.spa_rounded,
                    selected: diet == 'Vegetarian',
                    onTap: () => setState(() => diet = 'Vegetarian'),
                  ),
                  const SizedBox(height: 16),
                  _SelectionTile(
                    title: 'Vegan',
                    icon: Icons.eco_rounded,
                    selected: diet == 'Vegan',
                    onTap: () => setState(() => diet = 'Vegan'),
                  ),
                ],
              ),
            ),
            _AccomplishStep(
              onBack: back,
              onContinue: next,
            ),
            _WeightTransitionStep(
              goal: goal.isEmpty ? 'Maintain' : goal,
              onBack: back,
              onContinue: next,
            ),
            const _LoadingPlanScreen(),
            _ResultScreen(
              calories: caloriesRounded,
              carbs: carbsRounded,
              protein: proteinRounded,
              fats: fatsRounded,
              goal: goal.isEmpty ? 'Maintain' : goal,
              gender: gender ?? 'Other',
              age: age,
              workoutsPerWeek: workoutsPerWeek,
              usedOtherApps: usedOtherApps ?? false,
              blocker: blocker,
              diet: diet,
              currentWeightKg: weightKg,
              desiredWeightKg: desiredWeightKg,
              weeklyRateKg: weeklyRateKg,
              monthsToGoal: monthsToGoal,
              onCreateAccount: () {
                Navigator.pushNamed(
                  context,
                  '/register',
                  arguments: {
                    'gender': gender,
                    'age': age,
                    'height': heightCm,
                    'weight': weightKg,
                    'goal': goal,
                    'calories': caloriesRounded,
                    'protein': proteinRounded,
                    'carbs': carbsRounded,
                    'fats': fatsRounded,
                    'diet': diet,
                    'workouts': workoutsPerWeek,
                  },
                );
              },
              onSignIn: () => Navigator.pushNamed(context, '/login'),
            ),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class NPColors {
  static const Color bg = Color(0xFF10150D);
  static const Color bgTop = Color(0xFF26331A);
  static const Color bgMid = Color(0xFF12180E);
  static const Color bgBottom = Color(0xFF050704);
  static const Color surface = Color(0xFF30322D);
  static const Color surface2 = Color(0xFF4A4D47);
  static const Color surface3 = Color(0xFF555852);
  static const Color border = Color(0xFF4B5046);
  static const Color text = Color(0xFFFFFFFF);
  static const Color soft = Color(0xFFC7CFBC);
  static const Color muted = Color(0xFF979F8E);
  static const Color primary = Color(0xFFD6FF60);
  static const Color accent = Color(0xFFD6FF60);
  static const Color protein = Color(0xFFFF7A7A);
  static const Color fats = Color(0xFF8CAAEF);

  static TextStyle title({double size = 34}) => GoogleFonts.outfit(
        color: text,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1.12,
        letterSpacing: -0.7,
      );

  static TextStyle body({double size = 15.5, Color color = soft}) =>
      GoogleFonts.outfit(
        color: color,
        fontSize: size,
        height: 1.45,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      );
}

class _LandingScreen extends StatefulWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const _LandingScreen({
    required this.onGetStarted,
    required this.onSignIn,
  });

  @override
  State<_LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<_LandingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _float;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    _float = Tween<double>(begin: -10, end: 8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _fade = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return FadeTransition(
          opacity: _fade,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EEF2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🇺🇸', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 8),
                        Text(
                          'EN',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: NPColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Transform.translate(
                  offset: Offset(0, _float.value),
                  child: Container(
                    height: 430,
                    width: 260,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(42),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 32,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(42),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Container(color: Colors.black),
                          ),
                          Positioned(
                            top: 14,
                            left: 18,
                            right: 18,
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 34,
                            left: 16,
                            right: 16,
                            child: Container(
                              height: 260,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF8A7D68),
                                    Color(0xFF534C45),
                                  ],
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 18,
                                    top: 18,
                                    child: _miniCircle(Icons.close_rounded),
                                  ),
                                  Positioned(
                                    right: 18,
                                    top: 18,
                                    child: _miniCircle(Icons.help_outline_rounded),
                                  ),
                                  const Positioned.fill(
                                    child: Center(
                                      child: Icon(
                                        Icons.document_scanner_rounded,
                                        size: 110,
                                        color: NPColors.soft,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 28,
                                    top: 72,
                                    child: _scanCorner(),
                                  ),
                                  Positioned(
                                    right: 28,
                                    top: 72,
                                    child: Transform.rotate(
                                      angle: 1.57,
                                      child: _scanCorner(),
                                    ),
                                  ),
                                  Positioned(
                                    left: 28,
                                    bottom: 68,
                                    child: Transform.rotate(
                                      angle: -1.57,
                                      child: _scanCorner(),
                                    ),
                                  ),
                                  Positioned(
                                    right: 28,
                                    bottom: 68,
                                    child: Transform.rotate(
                                      angle: 3.14,
                                      child: _scanCorner(),
                                    ),
                                  ),
                                  Positioned(
                                    left: 18,
                                    right: 18,
                                    bottom: 22,
                                    child: Container(
                                      height: 42,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: Row(
                                        children: const [
                                          Icon(Icons.auto_awesome, size: 18),
                                          SizedBox(width: 6),
                                          Text(
                                            'Scan Food',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Spacer(),
                                          Icon(Icons.tune_rounded, size: 18),
                                          SizedBox(width: 12),
                                          Icon(Icons.image_outlined, size: 18),
                                          SizedBox(width: 12),
                                          Icon(Icons.edit_outlined, size: 18),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Positioned(
                            left: 22,
                            right: 22,
                            bottom: 58,
                            child: Icon(
                              Icons.radio_button_off_rounded,
                              size: 66,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // Feature pills
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _FeaturePill(icon: Icons.sensors_rounded, label: 'IoT Health'),
                    const SizedBox(width: 8),
                    _FeaturePill(icon: Icons.auto_awesome_rounded, label: 'AI Scan'),
                    const SizedBox(width: 8),
                    _FeaturePill(icon: Icons.monitor_heart_rounded, label: 'Real-time'),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Smart health &\nnutrition advisor',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: NPColors.text,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1.18,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'AI-powered food scanning, IoT health\nmonitoring & personalized nutrition.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: NPColors.soft,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                _BottomButton(
                  label: 'Get Started',
                  enabled: true,
                  onTap: widget.onGetStarted,
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: widget.onSignIn,
                  child: const Text.rich(
                    TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(
                        color: NPColors.text,
                        fontSize: 16,
                      ),
                      children: [
                        TextSpan(
                          text: 'Sign In',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _miniCircle(IconData icon) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }

  Widget _scanCorner() {
    return SizedBox(
      width: 34,
      height: 34,
      child: CustomPaint(painter: _CornerPainter()),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool dark;
  final VoidCallback onTap;

  const _AuthButton({
    required this.icon,
    required this.label,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: dark ? NPColors.primary : NPColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: dark
              ? null
              : Border.all(color: NPColors.border, width: 1),
          boxShadow: dark
              ? [
                  BoxShadow(
                    color: NPColors.primary.withValues(alpha: 0.20),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: icon == Icons.g_mobiledata_rounded ? 26 : 20,
              color: dark ? Colors.black : NPColors.text,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.black : NPColors.text,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: NPColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: NPColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: NPColors.accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: NPColors.text,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionScaffold extends StatelessWidget {
  final double progress;
  final VoidCallback onBack;
  final bool canContinue;
  final VoidCallback onContinue;
  final String title;
  final String? subtitle;
  final Widget child;

  const _QuestionScaffold({
    required this.progress,
    required this.onBack,
    required this.canContinue,
    required this.onContinue,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOut,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      key: ValueKey(title),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: NPColors.text,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                            letterSpacing: -0.6,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              color: NPColors.soft,
                              fontSize: 16,
                              height: 1.45,
                            ),
                          ),
                        ],
                        const SizedBox(height: 34),
                        child,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: NPColors.border)),
          ),
          child: _BottomButton(
            label: 'Continue',
            enabled: canContinue,
            onTap: canContinue ? onContinue : null,
          ),
        ),
      ],
    );
  }
}

class _PersistentTopProgress extends StatefulWidget {
  final double progress;
  final double previousProgress;

  const _PersistentTopProgress({
    required this.progress,
    required this.previousProgress,
  });

  @override
  State<_PersistentTopProgress> createState() => _PersistentTopProgressState();
}

class _PersistentTopProgressState extends State<_PersistentTopProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: widget.previousProgress, end: widget.progress),
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeInOutCubicEmphasized,
      builder: (context, value, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final fillWidth =
                (constraints.maxWidth * value).clamp(0.0, constraints.maxWidth);
            return Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _shimmerController,
                    builder: (context, _) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeInOutCubicEmphasized,
                        width: fillWidth,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            begin: Alignment(
                                -1.0 + (_shimmerController.value * 2), 0),
                            end: Alignment(
                                0.2 + (_shimmerController.value * 2), 0),
                            colors: const [
                              Color(0xFFBEE64A),
                              Color(0xFFD6FF60),
                              Color(0xFFE7FFA0),
                              Color(0xFFD6FF60),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: NPColors.primary.withValues(alpha: 0.45),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (fillWidth > 12)
                    Positioned(
                      left: fillWidth - 14,
                      top: -5,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.55),
                          boxShadow: [
                            BoxShadow(
                              color: NPColors.primary.withValues(alpha: 0.60),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _HeightWeightStep extends StatelessWidget {
  final double progress;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final bool useMetric;
  final double heightCm;
  final double weightKg;
  final ValueChanged<bool> onUnitChanged;
  final ValueChanged<double> onHeightChanged;
  final ValueChanged<double> onWeightChanged;

  const _HeightWeightStep({
    required this.progress,
    required this.onBack,
    required this.onContinue,
    required this.useMetric,
    required this.heightCm,
    required this.weightKg,
    required this.onUnitChanged,
    required this.onHeightChanged,
    required this.onWeightChanged,
  });

  int get heightInches => (heightCm / 2.54).round();
  int get weightPounds => (weightKg * 2.20462).round();

  @override
  Widget build(BuildContext context) {
    final heightValue = useMetric ? heightCm.round().toDouble() : heightInches.toDouble();
    final weightValue = useMetric ? weightKg.round().toDouble() : weightPounds.toDouble();

    return _QuestionScaffold(
      progress: progress,
      onBack: onBack,
      canContinue: true,
      onContinue: onContinue,
      title: 'Height & weight',
      subtitle: 'Slide smoothly to set your current body profile.',
      child: Column(
        children: [
          const SizedBox(height: 4),
          _UnitToggle(
            useMetric: useMetric,
            onChanged: (v) {
                      onUnitChanged(v);
            },
          ),
          const SizedBox(height: 26),
          _MeasureRulerCard(
            title: 'What is your weight?',
            value: weightValue,
            unit: useMetric ? 'kg' : 'lb',
            min: useMetric ? 35 : 80,
            max: useMetric ? 185 : 300,
            step: 1,
            backgroundColor: NPColors.surface,
            accentColor: NPColors.primary,
            onChanged: (v) {
              if (useMetric) {
                onWeightChanged(v);
              } else {
                onWeightChanged(v / 2.20462);
              }
            },
          ),
          const SizedBox(height: 20),
          _MeasureRulerCard(
            title: 'What is your height?',
            value: heightValue,
            unit: useMetric ? 'cm' : 'in',
            min: useMetric ? 140 : 55,
            max: useMetric ? 220 : 86,
            step: 1,
            backgroundColor: NPColors.surface,
            accentColor: const Color(0xFFB7D8D5),
            onChanged: (v) {
              if (useMetric) {
                onHeightChanged(v);
              } else {
                onHeightChanged(v * 2.54);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _BirthStep extends StatelessWidget {
  final double progress;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final DateTime birthDate;
  final ValueChanged<DateTime> onChanged;

  const _BirthStep({
    required this.progress,
    required this.onBack,
    required this.onContinue,
    required this.birthDate,
    required this.onChanged,
  });

  int get _age {
    final now = DateTime.now();
    int years = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      years--;
    }
    return years.clamp(13, 80);
  }

  @override
  Widget build(BuildContext context) {
    return _QuestionScaffold(
      progress: progress,
      onBack: onBack,
      canContinue: true,
      onContinue: onContinue,
      title: 'What is your age?',
      subtitle: 'This helps us calculate a more accurate health and nutrition plan.',
      child: Column(
        children: [
          const SizedBox(height: 10),
          _MeasureRulerCard(
            title: 'Select your age',
            value: _age.toDouble(),
            unit: 'years',
            min: 13,
            max: 80,
            step: 1,
            backgroundColor: NPColors.surface,
            accentColor: NPColors.primary,
            onChanged: (v) {
              final now = DateTime.now();
              onChanged(DateTime(now.year - v.round(), birthDate.month, birthDate.day));
            },
          ),
        ],
      ),
    );
  }
}

class _DesiredWeightStep extends StatelessWidget {
  final double progress;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final String goal;
  final double currentWeightKg;
  final double value;
  final ValueChanged<double> onChanged;

  const _DesiredWeightStep({
    required this.progress,
    required this.onBack,
    required this.onContinue,
    required this.goal,
    required this.currentWeightKg,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeGoal = goal.isEmpty ? 'Maintain' : goal;
    double min = 35.0;
    double max = 120.0;

    if (safeGoal == 'Lose weight') {
      max = math.max(35.0, currentWeightKg - 0.1);
    } else if (safeGoal == 'Gain weight') {
      min = math.min(120.0, currentWeightKg + 0.1);
    } else {
      min = math.max(35.0, currentWeightKg - 5);
      max = math.min(120.0, currentWeightKg + 5);
    }

    final safeValue = value.clamp(min, max).toDouble();

    return _QuestionScaffold(
      progress: progress,
      onBack: onBack,
      canContinue: true,
      onContinue: onContinue,
      title: 'What is your\ndesired weight?',
      subtitle: safeGoal == 'Lose weight'
          ? 'Choose a target below your current weight.'
          : safeGoal == 'Gain weight'
              ? 'Choose a target above your current weight.'
              : 'Choose a target close to your current weight.',
      child: Column(
        children: [
          const SizedBox(height: 8),
          _MeasureRulerCard(
            title: safeGoal,
            value: safeValue,
            unit: 'kg',
            min: min,
            max: max,
            step: 0.5,
            backgroundColor: NPColors.surface,
            accentColor: NPColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SpeedStep extends StatelessWidget {
  final double progress;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final double value;
  final int monthsToGoal;
  final int caloriesRounded;
  final ValueChanged<double> onChanged;

  const _SpeedStep({
    required this.progress,
    required this.onBack,
    required this.onContinue,
    required this.value,
    required this.monthsToGoal,
    required this.caloriesRounded,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSlow = value <= 0.35;
    final isRec = value > 0.35 && value < 0.75;
    final isFast = value >= 0.75;

    return _QuestionScaffold(
      progress: progress,
      onBack: onBack,
      canContinue: true,
      onContinue: onContinue,
      title: 'How fast do you want\nto reach your goal?',
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            goalText(context),
            style: const TextStyle(
              fontSize: 15,
              color: NPColors.soft,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              '${value.toStringAsFixed(1)} kg / week',
              key: ValueKey(value.toStringAsFixed(1)),
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                color: NPColors.text,
                letterSpacing: -1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SpeedIcon(
                label: 'Gentle',
                sublabel: '≤ 0.3 kg',
                icon: Icons.directions_walk_rounded,
                active: isSlow,
                accentColor: const Color(0xFF5B8FD6),
              ),
              _SpeedIcon(
                label: 'Balanced',
                sublabel: '0.4–0.7 kg',
                icon: Icons.trending_up_rounded,
                active: isRec,
                accentColor: NPColors.accent,
              ),
              _SpeedIcon(
                label: 'Aggressive',
                sublabel: '≥ 0.8 kg',
                icon: Icons.bolt_rounded,
                active: isFast,
                accentColor: const Color(0xFFD95555),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // ── Upgraded slider ──
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: isSlow
                  ? const Color(0xFF5B8FD6)
                  : isFast
                      ? const Color(0xFFD95555)
                      : NPColors.accent,
              inactiveTrackColor: NPColors.surface2,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 26),
              overlayColor: NPColors.primary.withValues(alpha: 0.08),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              min: 0.1,
              max: 1.0,
              value: value,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: 20),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: NPColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: NPColors.border.withValues(alpha: 0.6)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: NPColors.primary.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: NPColors.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: 'Goal in ',
                          style: const TextStyle(
                            fontSize: 15,
                            color: NPColors.soft,
                            height: 1.4,
                          ),
                          children: [
                            TextSpan(
                              text: '$monthsToGoal month${monthsToGoal == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: isSlow
                                    ? const Color(0xFF5B8FD6)
                                    : isFast
                                        ? const Color(0xFFD95555)
                                        : NPColors.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Daily target: $caloriesRounded kcal',
                        style: const TextStyle(
                          fontSize: 13,
                          color: NPColors.soft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String goalText(BuildContext context) {
    return 'Weight change speed per week';
  }
}

class _AccomplishStep extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _AccomplishStep({
    required this.onBack,
    required this.onContinue,
  });

  @override
  State<_AccomplishStep> createState() => _AccomplishStepState();
}

class _AccomplishStepState extends State<_AccomplishStep> {
  String? selected;

  static const List<_AccomplishOption> _options = [
    _AccomplishOption('Eat and live healthier', Icons.apple_rounded),
    _AccomplishOption('Boost my energy and mood', Icons.wb_sunny_rounded),
    _AccomplishOption('Stay motivated and consistent', Icons.fitness_center_rounded),
    _AccomplishOption('Feel better about my body', Icons.self_improvement_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                const Text(
                  'What would you like to\naccomplish?',
                  style: TextStyle(
                    color: NPColors.text,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 34),
                ...List.generate(_options.length, (i) {
                  final opt = _options[i];
                  final isSelected = selected == opt.title;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _SelectionTile(
                      title: opt.title,
                      icon: opt.icon,
                      selected: isSelected,
                      onTap: () => setState(() => selected = opt.title),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: NPColors.border)),
          ),
          child: _BottomButton(
            label: 'Continue',
            enabled: true,
            onTap: widget.onContinue,
          ),
        ),
      ],
    );
  }
}

class _AccomplishOption {
  final String title;
  final IconData icon;
  const _AccomplishOption(this.title, this.icon);
}

// ─────────────────────────────────────────────
// Weight Transition screen
// ─────────────────────────────────────────────

class _WeightTransitionStep extends StatefulWidget {
  final String goal;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _WeightTransitionStep({
    required this.goal,
    required this.onBack,
    required this.onContinue,
  });

  @override
  State<_WeightTransitionStep> createState() => _WeightTransitionStepState();
}

class _WeightTransitionStepState extends State<_WeightTransitionStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _draw;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    _draw = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
    _fade = CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.35, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _headline {
    if (widget.goal == 'Lose weight') return 'You have great\npotential to crush\nyour goal';
    if (widget.goal == 'Gain weight') return 'You have great\npotential to crush\nyour goal';
    return 'You\'re on the right\ntrack to maintain\nyour goal';
  }

  String get _caption {
    if (widget.goal == 'Lose weight') {
      return 'Based on historical data, weight loss is usually slow at first, but after 7 days you can reach your goal quickly!';
    } else if (widget.goal == 'Gain weight') {
      return 'Based on historical data, weight gain is usually delayed at first, but after 7 days you can reach your goal quickly!';
    }
    return 'Based on historical data, users who track consistently see stable results within the first 7 days.';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: FadeTransition(
              opacity: _fade,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return Text(
                        _headline,
                        style: const TextStyle(
                          color: NPColors.text,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                          letterSpacing: -0.6,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: NPColors.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: NPColors.border.withValues(alpha: 0.7), width: 0.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your weight transition',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: NPColors.text,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 200,
                          child: AnimatedBuilder(
                            animation: _draw,
                            builder: (context, _) {
                              return CustomPaint(
                                painter: _WeightCurvePainter(
                                  progress: _draw.value,
                                  isGain: widget.goal != 'Lose weight',
                                ),
                                size: const Size(double.infinity, 200),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _caption,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: NPColors.soft,
                            height: 1.55,
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
        Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: NPColors.border)),
          ),
          child: _BottomButton(
            label: 'Continue',
            enabled: true,
            onTap: widget.onContinue,
          ),
        ),
      ],
    );
  }
}

class _WeightCurvePainter extends CustomPainter {
  final double progress;
  final bool isGain;

  const _WeightCurvePainter({required this.progress, required this.isGain});

  // Smooth cubic bezier easing — matches actual S-curve shape
  double _curve(double t) {
    if (isGain) {
      // Lag then accelerate: slow flat start, sharp rise at end
      return t < 0.5
          ? 2 * t * t * t
          : 1 - math.pow(-2 * t + 2, 3) / 2;
    } else {
      // Drop fast then flatten: inverse S
      final inv = 1 - t;
      return 1 - (inv < 0.5
          ? 2 * inv * inv * inv
          : 1 - math.pow(-2 * inv + 2, 3) / 2);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const bottomPad = 36.0;
    const topPad = 12.0;
    const leftPad = 4.0;
    const rightPad = 20.0;
    final chartW = w - leftPad - rightPad;
    final chartH = h - bottomPad - topPad;

    // Axis baseline
    final baseY = topPad + chartH;
    final endX = leftPad + chartW;

    // ── Grid lines (subtle horizontal dashes) ──
    final gridPaint = Paint()
      ..color = const Color(0xFFE5E3E8)
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 3; i++) {
      final gy = topPad + chartH * (1 - i / 4);
      const dashW = 5.0;
      const dashGap = 5.0;
      double dx = leftPad;
      while (dx < endX) {
        canvas.drawLine(Offset(dx, gy), Offset(math.min(dx + dashW, endX), gy), gridPaint);
        dx += dashW + dashGap;
      }
    }

    // ── Build full path points at high resolution ──
    const steps = 120;
    final allPts = <Offset>[];
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final y = _curve(t);
      allPts.add(Offset(
        leftPad + t * chartW,
        topPad + (1.0 - y) * chartH,
      ));
    }

    // Clip to animated progress
    final visibleEnd = leftPad + progress * chartW;
    final visPts = allPts.where((p) => p.dx <= visibleEnd + 1).toList();
    if (visPts.length < 2) return;

    // ── Fill area under curve ──
    final fillPath = Path();
    fillPath.moveTo(visPts.first.dx, baseY);
    for (int i = 0; i < visPts.length - 1; i++) {
      final p0 = visPts[i];
      final p1 = visPts[i + 1];
      final cpx = (p0.dx + p1.dx) / 2;
      fillPath.cubicTo(cpx, p0.dy, cpx, p1.dy, p1.dx, p1.dy);
    }
    fillPath.lineTo(visPts.last.dx, baseY);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            NPColors.accent.withValues(alpha: 0.22),
            NPColors.accent.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromLTWH(0, topPad, w, chartH)),
    );

    // ── Glow line (blurred, wider, behind main line) ──
    final glowPath = Path();
    glowPath.moveTo(visPts.first.dx, visPts.first.dy);
    for (int i = 0; i < visPts.length - 1; i++) {
      final p0 = visPts[i];
      final p1 = visPts[i + 1];
      final cpx = (p0.dx + p1.dx) / 2;
      glowPath.cubicTo(cpx, p0.dy, cpx, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(
      glowPath,
      Paint()
        ..color = NPColors.accent.withValues(alpha: 0.18)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // ── Main curve line ──
    canvas.drawPath(
      glowPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            NPColors.text.withValues(alpha: 0.55),
            NPColors.text,
          ],
        ).createShader(Rect.fromLTWH(leftPad, 0, chartW, h))
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // ── Milestone dots ──
    // positions as fraction of t (0..1), labels
    final milestoneTs = [0.0, 0.18, 0.40, 0.85];
    final milestoneLabels = ['Now', '3 Days', '7 Days', '30 Days'];

    final labelStyle = TextStyle(
      fontSize: 11,
      color: NPColors.soft,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.2,
    );

    for (int m = 0; m < milestoneTs.length; m++) {
      final t = milestoneTs[m];
      if (t > progress + 0.01) continue;

      final dotX = leftPad + t * chartW;
      final dotY = topPad + (1.0 - _curve(t)) * chartH;

      // Fade in the dot based on how far past it we are
      final dotAlpha = ((progress - t) / 0.08).clamp(0.0, 1.0);

      if (m == milestoneTs.length - 1 && progress >= 0.98) {
        // ── Trophy circle at goal ──
        canvas.drawCircle(
          Offset(dotX, dotY),
          14,
          Paint()..color = NPColors.accent,
        );
        canvas.drawCircle(
          Offset(dotX, dotY),
          14,
          Paint()
            ..color = NPColors.accent.withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        // Trophy emoji
        final tp = TextPainter(
          text: const TextSpan(text: '🏆', style: TextStyle(fontSize: 14)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(dotX - tp.width / 2, dotY - tp.height / 2));
      } else {
        // Regular dot: white fill + border
        canvas.drawCircle(
          Offset(dotX, dotY),
          5.5,
          Paint()
            ..color = Colors.white.withValues(alpha: dotAlpha)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          Offset(dotX, dotY),
          5.5,
          Paint()
            ..color = NPColors.text.withValues(alpha: dotAlpha)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }

      // ── Label below axis ──
      final tp = TextPainter(
        text: TextSpan(
          text: milestoneLabels[m],
          style: labelStyle.copyWith(
            color: NPColors.soft.withValues(alpha: dotAlpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelX = (dotX - tp.width / 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(labelX, baseY + 8));
    }

    // ── Moving glow dot at current draw head ──
    if (progress > 0.02 && progress < 0.99) {
      final headX = visPts.last.dx;
      final headY = visPts.last.dy;
      // Outer glow
      canvas.drawCircle(
        Offset(headX, headY),
        9,
        Paint()
          ..color = NPColors.accent.withValues(alpha: 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      // Inner dot
      canvas.drawCircle(
        Offset(headX, headY),
        4.5,
        Paint()..color = NPColors.accent,
      );
      canvas.drawCircle(
        Offset(headX, headY),
        2.5,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeightCurvePainter old) =>
      old.progress != progress || old.isGain != isGain;
}

class _LoadingPlanScreen extends StatefulWidget {
  const _LoadingPlanScreen();

  @override
  State<_LoadingPlanScreen> createState() => _LoadingPlanScreenState();
}

class _LoadingPlanScreenState extends State<_LoadingPlanScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  // Tick items: label, icon, threshold (0..1)
  static const List<_TickItem> _ticks = [
    _TickItem('Analyzing your body profile', Icons.person_rounded, 0.25),
    _TickItem('Building your nutrition target', Icons.local_fire_department_rounded, 0.50),
    _TickItem('Optimizing your macro split', Icons.grain_rounded, 0.75),
    _TickItem('Preparing your AI coach insight', Icons.auto_awesome_rounded, 1.00),
  ];

  // Per-tick animation controllers
  late final List<AnimationController> _tickControllers;
  late final List<Animation<double>> _tickScales;
  late final List<Animation<double>> _tickFades;

  final List<bool> _tickFired = [false, false, false, false];

  @override
  void initState() {
    super.initState();

    _tickControllers = List.generate(
      _ticks.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      ),
    );

    _tickScales = _tickControllers.map((c) =>
      Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOutBack),
      ),
    ).toList();

    _tickFades = _tickControllers.map((c) =>
      CurvedAnimation(parent: c, curve: Curves.easeOut),
    ).toList();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();

    _progress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    )..addListener(() {
        if (!mounted) return;
        final value = _progress.value;
        for (int i = 0; i < _ticks.length; i++) {
          if (!_tickFired[i] && value >= _ticks[i].threshold) {
            _tickFired[i] = true;
            _tickControllers[i].forward();
            HapticFeedback.lightImpact();
          }
        }
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final c in _tickControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress.value * 100).round();
    final pulse = 0.94 + (math.sin(_controller.value * math.pi * 5) * 0.05);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          Center(
            child: Transform.scale(
              scale: pulse,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      NPColors.primary.withValues(alpha: 0.10),
                      NPColors.primary.withValues(alpha: 0.03),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: NPColors.primary.withValues(alpha: 0.12),
                      blurRadius: 32,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 48,
                  color: NPColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                '$percent%',
                key: ValueKey(percent),
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  color: NPColors.primary,
                  letterSpacing: -2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Generating your personalized plan',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: NPColors.primary,
                height: 1.25,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 22),
          // Smooth progress bar
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _progress.value),
            duration: const Duration(milliseconds: 120),
            builder: (context, v, _) {
              return LayoutBuilder(builder: (context, constraints) {
                return Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Stack(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.linear,
                      width: constraints.maxWidth * _progress.value,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD6FF60), Color(0xFFBEE64A)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: NPColors.accent.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ]),
                );
              });
            },
          ),
          const SizedBox(height: 28),
          // Animated tick rows
          ...List.generate(_ticks.length, (i) {
            final fired = _tickFired[i];
            return FadeTransition(
              opacity: fired
                  ? _tickFades[i]
                  : const AlwaysStoppedAnimation(0.28),
              child: ScaleTransition(
                scale: fired
                    ? _tickScales[i]
                    : const AlwaysStoppedAnimation(1.0),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: fired
                              ? NPColors.primary
                              : Colors.black.withValues(alpha: 0.06),
                          boxShadow: fired
                              ? [
                                  BoxShadow(
                                    color: NPColors.primary.withValues(alpha: 0.20),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          fired ? Icons.check_rounded : _ticks[i].icon,
                          size: 16,
                          color: fired ? Colors.white : Colors.black38,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        _ticks[i].label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: fired ? FontWeight.w600 : FontWeight.w400,
                          color: fired ? NPColors.text : NPColors.soft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TickItem {
  final String label;
  final IconData icon;
  final double threshold;

  const _TickItem(this.label, this.icon, this.threshold);
}

class _ResultScreen extends StatefulWidget {
  final int calories;
  final int carbs;
  final int protein;
  final int fats;
  final String goal;
  final String gender;
  final int age;
  final int workoutsPerWeek;
  final bool usedOtherApps;
  final String blocker;
  final String diet;
  final double currentWeightKg;
  final double desiredWeightKg;
  final double weeklyRateKg;
  final int monthsToGoal;
  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;

  const _ResultScreen({
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fats,
    required this.goal,
    required this.gender,
    required this.age,
    required this.workoutsPerWeek,
    required this.usedOtherApps,
    required this.blocker,
    required this.diet,
    required this.currentWeightKg,
    required this.desiredWeightKg,
    required this.weeklyRateKg,
    required this.monthsToGoal,
    required this.onCreateAccount,
    required this.onSignIn,
  });

  @override
  State<_ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<_ResultScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pageAnimationController;
  late final AnimationController _celebrationController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  int get planScore {
    int score = 90;
    final diff = (widget.desiredWeightKg - widget.currentWeightKg).abs();
    if (widget.monthsToGoal <= 1) score -= 8;
    if (diff > 10) score -= 6;
    if (widget.protein < 100) score -= 4;
    if (widget.calories > 3600 || widget.calories < 1500) score -= 4;
    if (widget.workoutsPerWeek <= 1 && widget.goal.toLowerCase().contains('gain')) score -= 3;
    if (widget.workoutsPerWeek >= 6 && widget.goal.toLowerCase().contains('lose')) score -= 2;
    if (widget.blocker == 'Lack of consistency') score -= 2;
    if (widget.weeklyRateKg >= 0.9) score -= 3;
    if (widget.diet == 'Vegan' && widget.protein < 110) score -= 2;
    return score.clamp(72, 98);
  }

  String get scoreLabel {
    if (planScore >= 90) return 'Excellent';
    if (planScore >= 82) return 'Strong';
    return 'Good';
  }

  String get aiInsight {
    final pace = widget.weeklyRateKg >= 0.75
        ? 'aggressive'
        : widget.weeklyRateKg <= 0.35
            ? 'slow and controlled'
            : 'balanced';
    final training = widget.workoutsPerWeek >= 4
        ? 'Your training frequency supports this target well.'
        : 'A slightly more consistent training routine would improve results.';
    final blockerTip = widget.blocker == 'Busy schedule'
        ? 'Because you reported a busy schedule, the plan should work best with repeatable meals and simpler food choices.'
        : widget.blocker == 'Unhealthy eating habits'
            ? 'Because eating habits are your main blocker, the plan favors consistency and easier daily structure over extreme targets.'
            : 'Because consistency is your main blocker, the plan avoids unnecessary complexity and focuses on sustainable habits.';
    final appStyle = widget.usedOtherApps
        ? 'It also assumes you already understand tracking basics, so the targets are a bit more direct.'
        : 'It is structured to feel beginner-friendly so the targets are easier to follow from day one.';

    if (widget.goal.toLowerCase().contains('gain')) {
      return 'AI analysis: Based on your age, $pace weekly pace, ${widget.workoutsPerWeek} workouts per week, and $training Your calorie target uses a controlled surplus with higher protein to support quality weight gain. $blockerTip $appStyle';
    } else if (widget.goal.toLowerCase().contains('lose')) {
      return 'AI analysis: Based on your age, $pace weekly pace, ${widget.workoutsPerWeek} workouts per week, and $training Your calorie target uses a measured deficit with higher protein to protect muscle while reducing body weight. $blockerTip $appStyle';
    }
    return 'AI analysis: Based on your age, activity level, and current goal, your plan is designed to maintain body weight with stable calories and reliable protein intake. $blockerTip $appStyle';
  }

  List<String> get firstActions {
    final dietAction = widget.diet == 'Vegan'
        ? 'Plan protein sources carefully across meals because your diet is ${widget.diet.toLowerCase()}'
        : 'Build meals around your protein target first using foods that fit your ${widget.diet.toLowerCase()} diet';
    final blockerAction = widget.blocker == 'Busy schedule'
        ? 'Prepare 2-3 repeatable meals you can follow on busy days'
        : widget.blocker == 'Unhealthy eating habits'
            ? 'Start with one controlled meal routine before changing everything at once'
            : 'Use a simple daily routine so consistency becomes automatic';

    if (widget.goal.toLowerCase().contains('gain')) {
      return [
        'Hit your calorie target consistently each day',
        dietAction,
        blockerAction,
      ];
    } else if (widget.goal.toLowerCase().contains('lose')) {
      return [
        'Stay within your calorie target each day',
        'Keep protein high to preserve muscle while dieting',
        blockerAction,
      ];
    }
    return [
      'Keep your meals consistent day to day',
      dietAction,
      'Review your body weight trend every week and adjust only if needed',
    ];
  }

  List<double> get projectionWeights {
    final points = math.max(widget.monthsToGoal, 2);
    final diff = widget.desiredWeightKg - widget.currentWeightKg;
    return List.generate(
      points + 1,
      (i) => widget.currentWeightKg + (diff * (i / points)),
    );
  }

  @override
  void initState() {
    super.initState();

    _pageAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _fade = CurvedAnimation(
      parent: _pageAnimationController,
      curve: Curves.easeOut,
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _pageAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _pageAnimationController.forward();
    _celebrationController.forward();
  }

  @override
  void dispose() {
    _pageAnimationController.dispose();
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kgChange = (widget.desiredWeightKg - widget.currentWeightKg).abs();
    final goalLabel = widget.goal.isEmpty ? 'Maintain' : widget.goal;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Center(child: _ResultHero()),
              const SizedBox(height: 22),

              _GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: NPColors.primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.flag_rounded,
                            color: Colors.black,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goalLabel,
                                style: NPColors.title(size: 22),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.currentWeightKg.toStringAsFixed(1)} kg → ${widget.desiredWeightKg.toStringAsFixed(1)} kg',
                                style: NPColors.body(size: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniPlanStat(
                            label: 'Timeline',
                            value: '${widget.monthsToGoal} mo',
                            icon: Icons.calendar_month_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniPlanStat(
                            label: 'Change',
                            value: '${kgChange.toStringAsFixed(1)} kg',
                            icon: Icons.trending_up_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniPlanStat(
                            label: 'Pace',
                            value: '${widget.weeklyRateKg.toStringAsFixed(1)}/wk',
                            icon: Icons.speed_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              _GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Daily Target', style: NPColors.title(size: 22)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: NPColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${widget.calories} kcal',
                            style: GoogleFonts.outfit(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _MacroCard(
                      title: 'Protein',
                      value: '${widget.protein}g',
                      progress: 0.72,
                      color: NPColors.primary,
                      icon: Icons.egg_alt_rounded,
                    ),
                    const SizedBox(height: 12),
                    _MacroCard(
                      title: 'Carbs',
                      value: '${widget.carbs}g',
                      progress: 0.68,
                      color: NPColors.primary,
                      icon: Icons.grain_rounded,
                    ),
                    const SizedBox(height: 12),
                    _MacroCard(
                      title: 'Fats',
                      value: '${widget.fats}g',
                      progress: 0.52,
                      color: NPColors.primary,
                      icon: Icons.opacity_rounded,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              _GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan Focus', style: NPColors.title(size: 22)),
                    const SizedBox(height: 12),
                    _CleanFocusRow(
                      icon: Icons.restaurant_rounded,
                      title: widget.diet.isEmpty ? 'Balanced meals' : widget.diet,
                    ),
                    const SizedBox(height: 10),
                    _CleanFocusRow(
                      icon: Icons.fitness_center_rounded,
                      title: '${widget.workoutsPerWeek} workouts / week',
                    ),
                    const SizedBox(height: 10),
                    _CleanFocusRow(
                      icon: Icons.auto_awesome_rounded,
                      title: widget.blocker.isEmpty ? 'Consistency first' : widget.blocker,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _BottomButton(
                label: 'Create My Plan',
                enabled: true,
                onTap: widget.onCreateAccount,
              ),
              const SizedBox(height: 14),
              Center(
                child: GestureDetector(
                  onTap: widget.onSignIn,
                  child: Text(
                    'Already have an account? Sign in',
                    style: GoogleFonts.outfit(
                      color: NPColors.soft,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPlanStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MiniPlanStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: NPColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NPColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Icon(icon, color: NPColors.primary, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: NPColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: NPColors.soft,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CleanFocusRow extends StatelessWidget {
  final IconData icon;
  final String title;

  const _CleanFocusRow({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: NPColors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: NPColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: NPColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultHero extends StatefulWidget {
  const _ResultHero();

  @override
  State<_ResultHero> createState() => _ResultHeroState();
}

class _ResultHeroState extends State<_ResultHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _scale = Tween<double>(begin: 0.86, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Column(
        children: [
          ScaleTransition(
            scale: _scale,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: NPColors.primary,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: NPColors.primary.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_rounded, color: Colors.black, size: 18),
                  const SizedBox(width: 7),
                  Text(
                    'Plan ready',
                    style: GoogleFonts.outfit(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Your premium plan\nis ready',
            textAlign: TextAlign.center,
            style: NPColors.title(size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            'Simple targets. Clear progress.',
            textAlign: TextAlign.center,
            style: NPColors.body(size: 15),
          ),
        ],
      ),
    );
  }
}

class _SelectionTile extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _SelectionTile({
    required this.title,
    this.subtitle,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SelectionTile> createState() => _SelectionTileState();
}

class _SelectionTileState extends State<_SelectionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.975,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _pressController;
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      onTapDown: (_) => _pressController.reverse(),
      onTapUp: (_) => _pressController.forward(),
      onTapCancel: () => _pressController.forward(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: widget.selected
                ? NPColors.primary.withValues(alpha: 0.14)
                : NPColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: widget.selected
                  ? NPColors.primary
                  : Colors.white.withValues(alpha: 0.08),
              width: widget.selected ? 1.6 : 1,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: NPColors.primary.withValues(alpha: 0.22),
                      blurRadius: 28,
                      spreadRadius: 1,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: NPColors.primary.withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? NPColors.primary.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.selected
                          ? NPColors.primary.withValues(alpha: 0.50)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 20,
                    color: widget.selected ? NPColors.primary : NPColors.soft,
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.outfit(
                        color: NPColors.text,
                        fontSize: 17,
                        fontWeight:
                            widget.selected ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle!,
                        style: GoogleFonts.outfit(
                          color: widget.selected
                              ? NPColors.text.withValues(alpha: 0.78)
                              : NPColors.soft,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedScale(
                scale: widget.selected ? 1 : 0.72,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: widget.selected ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: NPColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.black,
                    ),
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

class _MeasureRulerCard extends StatefulWidget {
  final String title;
  final double value;
  final String unit;
  final double min;
  final double max;
  final double step;
  final Color backgroundColor;
  final Color accentColor;
  final ValueChanged<double> onChanged;

  const _MeasureRulerCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.step,
    required this.backgroundColor,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  State<_MeasureRulerCard> createState() => _MeasureRulerCardState();
}

class _MeasureRulerCardState extends State<_MeasureRulerCard> {
  static const double _pixelsPerStep = 14.0;

  late double _localValue;
  double _dragStartDx = 0;
  double _dragStartValue = 0;

  @override
  void initState() {
    super.initState();
    _localValue = _snap(widget.value.clamp(widget.min, widget.max).toDouble());
  }

  @override
  void didUpdateWidget(covariant _MeasureRulerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final boundsChanged = oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.step != widget.step ||
        oldWidget.unit != widget.unit;

    if (boundsChanged || (widget.value - oldWidget.value).abs() > 0.001) {
      _localValue = _snap(widget.value.clamp(widget.min, widget.max).toDouble());
    }
  }

  double get _clampedValue => _localValue.clamp(widget.min, widget.max).toDouble();

  double _snap(double raw) {
    final stepped = (raw / widget.step).round() * widget.step;
    final decimals = widget.step < 1 ? 1 : 0;
    final fixed = double.parse(stepped.toStringAsFixed(decimals));
    return fixed.clamp(widget.min, widget.max).toDouble();
  }

  void _commit(double raw) {
    final value = _snap(raw);
    if ((value - _localValue).abs() < 0.0001) return;
    setState(() => _localValue = value);
    widget.onChanged(value);
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartDx = details.localPosition.dx;
    _dragStartValue = _clampedValue;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final stepDelta = (_dragStartDx - details.localPosition.dx) / _pixelsPerStep;
    _commit(_dragStartValue + (stepDelta * widget.step));
  }

  void _onTapDown(TapDownDetails details, double width) {
    final center = width / 2;
    final direction = details.localPosition.dx < center ? -1 : 1;
    _commit(_clampedValue + direction * widget.step);
  }

  @override
  Widget build(BuildContext context) {
    final value = _clampedValue;
    final display = widget.step < 1
        ? value.toStringAsFixed(1)
        : value.round().toString();

    return Column(
      children: [
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: NPColors.text,
            fontSize: 22,
            height: 1.08,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.45,
          ),
        ),
        const SizedBox(height: 14),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          decoration: BoxDecoration(
            color: NPColors.surface,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: NPColors.primary.withValues(alpha: 0.16),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: NPColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: NPColors.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  widget.unit.toUpperCase(),
                  style: GoogleFonts.outfit(
                    color: NPColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 130),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  );
                },
                child: Text(
                  display,
                  key: ValueKey('${widget.unit}-$display'),
                  style: GoogleFonts.outfit(
                    color: NPColors.text,
                    fontSize: 60,
                    height: 0.95,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2.2,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: _onDragStart,
                    onHorizontalDragUpdate: _onDragUpdate,
                    onTapDown: (details) => _onTapDown(details, constraints.maxWidth),
                    child: SizedBox(
                      height: 94,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _ProfessionalRulerPainter(
                                  min: widget.min,
                                  max: widget.max,
                                  value: value,
                                  step: widget.step,
                                  accent: NPColors.primary,
                                  pixelsPerStep: _pixelsPerStep,
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Align(
                              alignment: Alignment.center,
                              child: Container(
                                width: 3,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: NPColors.primary,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(
                                      color: NPColors.primary.withValues(alpha: 0.35),
                                      blurRadius: 16,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 1,
                            child: Text(
                              'drag to adjust',
                              style: GoogleFonts.outfit(
                                color: NPColors.soft.withValues(alpha: 0.72),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfessionalRulerPainter extends CustomPainter {
  final double min;
  final double max;
  final double value;
  final double step;
  final Color accent;
  final double pixelsPerStep;

  const _ProfessionalRulerPainter({
    required this.min,
    required this.max,
    required this.value,
    required this.step,
    required this.accent,
    required this.pixelsPerStep,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final baseY = size.height * 0.50;
    final stepValueAtCenter = value / step;
    final visibleSteps = (size.width / pixelsPerStep).ceil() + 8;
    final firstStep = (stepValueAtCenter - visibleSteps / 2).floor();
    final lastStep = (stepValueAtCenter + visibleSteps / 2).ceil();

    final labelStyle = GoogleFonts.outfit(
      fontSize: 12,
      color: NPColors.soft.withValues(alpha: 0.72),
      fontWeight: FontWeight.w700,
    );

    final tickPaint = Paint()..strokeCap = StrokeCap.round;

    for (int i = firstStep; i <= lastStep; i++) {
      final actualValue = i * step;
      if (actualValue < min - step || actualValue > max + step) continue;

      final x = centerX + (i - stepValueAtCenter) * pixelsPerStep;
      if (x < -20 || x > size.width + 20) continue;

      final rounded = actualValue.round();
      final isMajor = rounded % 10 == 0;
      final isMid = rounded % 5 == 0;
      final distance = (x - centerX).abs() / centerX;
      final opacity = (1.0 - distance).clamp(0.18, 0.88).toDouble();
      final height = isMajor ? 36.0 : isMid ? 26.0 : 17.0;

      tickPaint
        ..color = isMajor
            ? NPColors.text.withValues(alpha: 0.62 * opacity)
            : NPColors.soft.withValues(alpha: 0.35 * opacity)
        ..strokeWidth = isMajor ? 1.45 : 1.0;

      canvas.drawLine(
        Offset(x, baseY - height / 2),
        Offset(x, baseY + height / 2),
        tickPaint,
      );

      if (isMajor) {
        final label = rounded.toString();
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: labelStyle.copyWith(
              color: NPColors.soft.withValues(alpha: opacity),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, baseY - 46));
      }
    }

    final glowRect = Rect.fromCenter(
      center: Offset(centerX, baseY),
      width: 92,
      height: 76,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(glowRect, const Radius.circular(24)),
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.11),
            accent.withValues(alpha: 0.00),
          ],
        ).createShader(glowRect),
    );

    final fadePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          NPColors.surface,
          NPColors.surface.withValues(alpha: 0),
          NPColors.surface.withValues(alpha: 0),
          NPColors.surface,
        ],
        stops: const [0.0, 0.16, 0.84, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), fadePaint);
  }

  @override
  bool shouldRepaint(covariant _ProfessionalRulerPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.min != min ||
        oldDelegate.max != max ||
        oldDelegate.step != step ||
        oldDelegate.accent != accent;
  }
}

class _UnitToggle extends StatelessWidget {
  final bool useMetric;
  final ValueChanged<bool> onChanged;

  const _UnitToggle({
    required this.useMetric,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Imperial',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: !useMetric ? NPColors.text : NPColors.muted,
          ),
        ),
        const SizedBox(width: 18),
        GestureDetector(
          onTap: () {
            onChanged(!useMetric);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 94,
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: NPColors.surface2,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Align(
              alignment:
                  useMetric ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: NPColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Text(
          'Metric',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: useMetric ? NPColors.text : NPColors.muted,
          ),
        ),
      ],
    );
  }
}

class _WheelPickerColumn extends StatefulWidget {
  final List<String> values;
  final int initialIndex;
  final ValueChanged<int> onChanged;

  const _WheelPickerColumn({
    required this.values,
    required this.initialIndex,
    required this.onChanged,
  });

  @override
  State<_WheelPickerColumn> createState() => _WheelPickerColumnState();
}

class _WheelPickerColumnState extends State<_WheelPickerColumn> {
  late FixedExtentScrollController _controller;
  int _lastIndex = -1;

  @override
  void initState() {
    super.initState();
    _lastIndex = widget.initialIndex;
    _controller = FixedExtentScrollController(initialItem: widget.initialIndex);
  }

  @override
  void didUpdateWidget(covariant _WheelPickerColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _controller.dispose();
      _lastIndex = widget.initialIndex;
      _controller = FixedExtentScrollController(initialItem: widget.initialIndex);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: NPColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                  color: NPColors.primary.withValues(alpha: 0.28)),
              boxShadow: [
                BoxShadow(
                  color: NPColors.primary.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
          ShaderMask(
            shaderCallback: (rect) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0.0, 0.23, 0.77, 1.0],
              ).createShader(rect);
            },
            blendMode: BlendMode.dstIn,
            child: CupertinoPicker(
              scrollController: _controller,
              itemExtent: 44,
              magnification: 1.08,
              squeeze: 1.05,
              diameterRatio: 1.7,
              useMagnifier: true,
              selectionOverlay: const SizedBox.shrink(),
              onSelectedItemChanged: (index) {
                if (_lastIndex != index) {
                  _lastIndex = index;
                            }
                widget.onChanged(index);
              },
              children: widget.values
                  .map(
                    (e) => Center(
                      child: Text(
                        e,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          color: NPColors.text,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedIcon extends StatefulWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool active;
  final Color accentColor;

  const _SpeedIcon({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.active,
    required this.accentColor,
  });

  @override
  State<_SpeedIcon> createState() => _SpeedIconState();
}

class _SpeedIconState extends State<_SpeedIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _iconScale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _iconScale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _SpeedIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      widget.active ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.scale(
          scale: _scale.value,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: 100,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
            decoration: BoxDecoration(
              color: widget.active ? widget.accentColor.withValues(alpha: 0.14) : NPColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: widget.active
                    ? widget.accentColor.withValues(alpha: 0.6)
                    : NPColors.border,
                width: widget.active ? 1.5 : 1,
              ),
              boxShadow: widget.active
                  ? [
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon circle
                Transform.scale(
                  scale: _iconScale.value,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.active
                          ? widget.accentColor.withValues(alpha: 0.12)
                          : NPColors.surface,
                    ),
                    child: Icon(
                      widget.icon,
                      size: 22,
                      color: widget.active ? widget.accentColor : NPColors.soft,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500,
                    color: widget.active ? NPColors.text : NPColors.soft,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.sublabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: widget.active
                        ? widget.accentColor
                        : NPColors.soft.withValues(alpha: 0.6),
                    fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MacroCard extends StatelessWidget {
  final String title;
  final String value;
  final double progress;
  final Color color;
  final IconData icon;

  const _MacroCard({
    required this.title,
    required this.value,
    required this.progress,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NPColors.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NPColors.border.withValues(alpha: 0.75)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: NPColors.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: NPColors.primary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.outfit(
                        color: NPColors.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.outfit(
                      color: NPColors.primary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 8,
                  color: Colors.black.withValues(alpha: 0.18),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: animated.clamp(0.0, 1.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFD6FF60), Color(0xFFBEE64A)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


class _AnimatedRing extends StatefulWidget {
  final String value;
  final double progress;
  final Color color;

  const _AnimatedRing({
    required this.value,
    required this.progress,
    required this.color,
  });

  @override
  State<_AnimatedRing> createState() => _AnimatedRingState();
}

class _AnimatedRingState extends State<_AnimatedRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progressAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _progressAnimation = Tween<double>(
      begin: 0,
      end: widget.progress,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CustomPaint(
                    painter: _RingPainter(
                      progress: _progressAnimation.value,
                      color: widget.color,
                    ),
                  ),
                ),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: NPColors.surface2,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: NPColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 7.0;
    final rect = Offset.zero & size;
    final startAngle = -math.pi / 2;
    final arcRect = Rect.fromLTWH(
      strokeWidth,
      strokeWidth,
      size.width - (strokeWidth * 2),
      size.height - (strokeWidth * 2),
    );

    final backgroundPaint = Paint()
      ..color = NPColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 3
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + (2 * math.pi),
        colors: [
          color.withValues(alpha: 0.35),
          color,
          color.withValues(alpha: 0.85),
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arcRect, 0, 2 * math.pi, false, backgroundPaint);
    canvas.drawArc(
      arcRect,
      startAngle,
      2 * math.pi * progress,
      false,
      glowPaint,
    );
    canvas.drawArc(
      arcRect,
      startAngle,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NPColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: NPColors.border.withValues(alpha: 0.75), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;

  const _InfoPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: NPColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: NPColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          color: NPColors.text,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  final double progress;

  _CelebrationPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final particles = 18;

    for (int i = 0; i < particles; i++) {
      final dx = (size.width / particles) * i + 12;
      final dy = (40 + (i % 4) * 18) + (progress * 140);
      final radius = 3 + (i % 3).toDouble();

      paint.color = [
        NPColors.primary,
        NPColors.accent,
        NPColors.protein,
        NPColors.fats,
      ][i % 4].withValues(alpha: (1 - progress).clamp(0.0, 1.0));

      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _BackCircle extends StatelessWidget {
  final VoidCallback onTap;

  const _BackCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
          onTap();
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          color: NPColors.text,
          size: 20,
        ),
      ),
    );
  }
}

class _BottomButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _BottomButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_BottomButton> createState() => _BottomButtonState();
}

class _BottomButtonState extends State<_BottomButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
      lowerBound: 0.965,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _controller;
  }

  void _fire() {
    if (!widget.enabled) return;
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: 1,
      child: GestureDetector(
        onTap: _fire,
        onTapDown: widget.enabled ? (_) => _controller.reverse() : null,
        onTapUp: widget.enabled ? (_) => _controller.forward() : null,
        onTapCancel: () => _controller.forward(),
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            height: 62,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFCBEF69),
                  NPColors.primary,
                  Color(0xFFAEDB45),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: widget.enabled
                  ? [
                      BoxShadow(
                        color: NPColors.primary.withValues(alpha: 0.30),
                        blurRadius: 28,
                        spreadRadius: 1,
                        offset: const Offset(0, 12),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : [],
            ),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.black,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height * 0.65)
      ..lineTo(0, 0)
      ..lineTo(size.width * 0.65, 0);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RulerPainter extends CustomPainter {
  final double selectedPercent;

  const _RulerPainter({required this.selectedPercent});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          NPColors.primary.withValues(alpha: 0.10),
          NPColors.primary.withValues(alpha: 0.04),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width * selectedPercent, size.height));

    final selectedX = size.width * selectedPercent;

    // Filled region behind selection
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.10, selectedX, size.height * 0.80),
        const Radius.circular(4),
      ),
      fillPaint,
    );

    // Tick marks
    const tickSpacing = 6.0;
    for (double x = 0; x <= size.width; x += tickSpacing) {
      final tickIndex = (x / tickSpacing).round();
      final isMajor = (tickIndex % 10 == 0);
      final isMid = (tickIndex % 5 == 0);
      final tickHeight = isMajor ? 38.0 : isMid ? 24.0 : 14.0;
      final isPast = x <= selectedX;
      final paint = Paint()
        ..color = isPast
            ? (isMajor ? NPColors.primary : NPColors.primary.withValues(alpha: 0.45))
            : (isMajor ? Colors.black26 : Colors.black12)
        ..strokeWidth = isMajor ? 1.8 : 1.0;

      canvas.drawLine(
        Offset(x, size.height * 0.5 - tickHeight / 2),
        Offset(x, size.height * 0.5 + tickHeight / 2),
        paint,
      );
    }

    // Selector needle
    final needlePaint = Paint()
      ..color = NPColors.primary
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(selectedX, size.height * 0.08),
      Offset(selectedX, size.height * 0.92),
      needlePaint,
    );

    // Selector top cap dot
    canvas.drawCircle(
      Offset(selectedX, size.height * 0.08),
      4,
      Paint()..color = NPColors.primary,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) {
    return oldDelegate.selectedPercent != selectedPercent;
  }
}
