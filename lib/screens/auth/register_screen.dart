import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isSuccess = false;
  double _buttonScale = 1.0;
  double _passwordStrength = 0.0;

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  static const Color bg = Color(0xFF0F140D);
  static const Color card = Color(0xFF262A23);
  static const Color field = Color(0xFF2F332C);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);
  static const Color lime = Color(0xFFD6FF60);
  static const Color border = Color(0xFF3C4138);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();

    _passwordController.addListener(() {
      _checkPasswordStrength(_passwordController.text);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _checkPasswordStrength(String value) {
    double strength = 0.0;

    if (value.length >= 6) strength += 0.30;
    if (value.length >= 10) strength += 0.20;
    if (RegExp(r'[A-Z]').hasMatch(value)) strength += 0.20;
    if (RegExp(r'[0-9]').hasMatch(value)) strength += 0.20;
    if (RegExp(r'[!@#\$&*~%^()_+=\-]').hasMatch(value)) strength += 0.10;

    if (mounted) {
      setState(() => _passwordStrength = strength.clamp(0.0, 1.0));
    }
  }

  String get _strengthLabel {
    if (_passwordController.text.isEmpty) return 'Password strength';
    if (_passwordStrength < 0.4) return 'Weak password';
    if (_passwordStrength < 0.7) return 'Medium password';
    return 'Strong password';
  }

  Color get _strengthColor {
    if (_passwordController.text.isEmpty) return soft.withValues(alpha: 0.45);
    if (_passwordStrength < 0.4) return const Color(0xFFFF6B6B);
    if (_passwordStrength < 0.7) return const Color(0xFFFFB84D);
    return lime;
  }

  Future<void> _handleRegister() async {
    if (_isLoading || _isSuccess) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    final onboardingData = routeArgs is Map
        ? Map<String, dynamic>.from(routeArgs)
        : <String, dynamic>{};

    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showMessage('Please fill in all fields');
      return;
    }

    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters');
      return;
    }

    if (password != confirmPassword) {
      _showMessage('Passwords do not match');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _isSuccess = false;
    });

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final uid = credential.user!.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'onboardingCompleted': onboardingData.isNotEmpty,

        'gender': onboardingData['gender'],
        'age': onboardingData['age'],
        'heightCm': onboardingData['heightCm'] ?? onboardingData['height'],
        'weightKg': onboardingData['weightKg'] ?? onboardingData['weight'],
        'workoutsPerWeek':
            onboardingData['workoutsPerWeek'] ?? onboardingData['workouts'],
        'usedOtherApps': onboardingData['usedOtherApps'],
        'goal': onboardingData['goal'],
        'desiredWeightKg': onboardingData['desiredWeightKg'],
        'weeklyRateKg': onboardingData['weeklyRateKg'],
        'monthsToGoal': onboardingData['monthsToGoal'],
        'diet': onboardingData['diet'],
        'blocker': onboardingData['blocker'],
        'targetCalories':
            onboardingData['targetCalories'] ?? onboardingData['calories'],
        'proteinGrams':
            onboardingData['proteinGrams'] ?? onboardingData['protein'],
        'carbsGrams': onboardingData['carbsGrams'] ?? onboardingData['carbs'],
        'fatsGrams': onboardingData['fatsGrams'] ?? onboardingData['fats'],

        // Also keep simple dashboard-friendly keys.
        'height': onboardingData['heightCm'] ?? onboardingData['height'],
        'weight': onboardingData['weightKg'] ?? onboardingData['weight'],
        'workouts':
            onboardingData['workoutsPerWeek'] ?? onboardingData['workouts'],
        'calories':
            onboardingData['targetCalories'] ?? onboardingData['calories'],
        'protein': onboardingData['proteinGrams'] ?? onboardingData['protein'],
        'carbs': onboardingData['carbsGrams'] ?? onboardingData['carbs'],
        'fats': onboardingData['fatsGrams'] ?? onboardingData['fats'],

        'profile': {
          'gender': onboardingData['gender'],
          'age': onboardingData['age'],
          'birthDate': onboardingData['birthDate'],
          'heightCm': onboardingData['heightCm'] ?? onboardingData['height'],
          'weightKg': onboardingData['weightKg'] ?? onboardingData['weight'],
          'workoutsPerWeek':
              onboardingData['workoutsPerWeek'] ?? onboardingData['workouts'],
          'usedOtherApps': onboardingData['usedOtherApps'],
        },
        'plan': {
          'goal': onboardingData['goal'],
          'currentWeightKg':
              onboardingData['currentWeightKg'] ??
              onboardingData['weightKg'] ??
              onboardingData['weight'],
          'desiredWeightKg': onboardingData['desiredWeightKg'],
          'weeklyRateKg': onboardingData['weeklyRateKg'],
          'monthsToGoal': onboardingData['monthsToGoal'],
          'blocker': onboardingData['blocker'],
          'diet': onboardingData['diet'],
        },
        'nutritionTargets': {
          'calories':
              onboardingData['targetCalories'] ?? onboardingData['calories'],
          'protein':
              onboardingData['proteinGrams'] ?? onboardingData['protein'],
          'carbs': onboardingData['carbsGrams'] ?? onboardingData['carbs'],
          'fats': onboardingData['fatsGrams'] ?? onboardingData['fats'],
        },
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _isSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 350));

      if (!mounted) return;
      await _showAccountReadyDialog();

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/dashboard',
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _showMessage(_firebaseRegisterMessage(e));
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSuccess = false;
          _buttonScale = 1.0;
        });
      }
    }
  }

  Future<void> _showAccountReadyDialog() async {
    if (!mounted) return;

    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Account Ready',
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 360),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final scale = Tween<double>(begin: 0.85, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        );
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);

        return FadeTransition(
          opacity: fade,
          child: Center(
            child: ScaleTransition(
              scale: scale,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 250,
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 35,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: lime,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: lime.withValues(alpha: 0.28),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.black,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Account Ready',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: text,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your profile has been saved',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: soft,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _firebaseRegisterMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered';
      case 'invalid-email':
        return 'Please enter a valid email address';
      case 'weak-password':
        return 'Password is too weak';
      case 'network-request-failed':
        return 'Network error. Check your internet connection';
      default:
        return e.message ?? 'Registration failed';
    }
  }

  void _goToLogin() {
    if (_isLoading) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: card,
        content: Text(message, style: GoogleFonts.outfit(color: text)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A3A18), Color(0xFF0F140D), Color(0xFF070907)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 22,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _isLoading ? null : () => Navigator.pop(context),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: text,
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    Center(
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 90,
                        height: 90,
                        fit: BoxFit.contain,
                      ),
                    ),

                    const SizedBox(height: 28),

                    Text(
                      'Create Your\nAccount',
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -0.8,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Save your onboarding progress and personalized nutrition plan.',
                      style: GoogleFonts.outfit(
                        color: soft,
                        fontSize: 15.5,
                        height: 1.45,
                      ),
                    ),

                    const SizedBox(height: 34),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: card.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Full Name'),
                          const SizedBox(height: 10),
                          _field(
                            controller: _nameController,
                            hint: 'Enter your full name',
                            icon: Icons.person_outline_rounded,
                          ),

                          const SizedBox(height: 18),

                          _label('Email'),
                          const SizedBox(height: 10),
                          _field(
                            controller: _emailController,
                            hint: 'example@email.com',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                          ),

                          const SizedBox(height: 18),

                          _label('Password'),
                          const SizedBox(height: 10),
                          _field(
                            controller: _passwordController,
                            hint: 'Create password',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            suffix: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: soft,
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),
                          _PasswordStrengthIndicator(
                            value: _passwordStrength,
                            label: _strengthLabel,
                            color: _strengthColor,
                          ),

                          const SizedBox(height: 18),

                          _label('Confirm Password'),
                          const SizedBox(height: 10),
                          _field(
                            controller: _confirmPasswordController,
                            hint: 'Re-enter password',
                            icon: Icons.verified_user_outlined,
                            obscureText: _obscureConfirmPassword,
                            suffix: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: soft,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: GestureDetector(
                              onTapDown: (_) {
                                if (!_isLoading && !_isSuccess) {
                                  setState(() => _buttonScale = 0.96);
                                }
                              },
                              onTapUp: (_) {
                                setState(() => _buttonScale = 1.0);
                              },
                              onTapCancel: () {
                                setState(() => _buttonScale = 1.0);
                              },
                              child: AnimatedScale(
                                scale: _buttonScale,
                                duration: const Duration(milliseconds: 120),
                                curve: Curves.easeOut,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: _handleRegister,
                                      splashColor: Colors.white.withValues(
                                        alpha: 0.25,
                                      ),
                                      highlightColor: Colors.black.withValues(
                                        alpha: 0.08,
                                      ),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 240,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        decoration: BoxDecoration(
                                          color: _isSuccess
                                              ? lime
                                              : _isLoading
                                              ? lime.withValues(alpha: 0.78)
                                              : lime,
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: lime.withValues(
                                                alpha: _isLoading ? 0.12 : 0.22,
                                              ),
                                              blurRadius: 22,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 280,
                                            ),
                                            switchInCurve: Curves.easeOutBack,
                                            switchOutCurve: Curves.easeIn,
                                            transitionBuilder:
                                                (child, animation) {
                                                  return ScaleTransition(
                                                    scale: animation,
                                                    child: FadeTransition(
                                                      opacity: animation,
                                                      child: child,
                                                    ),
                                                  );
                                                },
                                            child: _isSuccess
                                                ? const Icon(
                                                    Icons.check_rounded,
                                                    key: ValueKey('success'),
                                                    color: Colors.black,
                                                    size: 30,
                                                  )
                                                : _isLoading
                                                ? const SizedBox(
                                                    key: ValueKey('loading'),
                                                    width: 23,
                                                    height: 23,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2.5,
                                                          color: Colors.black,
                                                        ),
                                                  )
                                                : Text(
                                                    'Create Account',
                                                    key: const ValueKey('text'),
                                                    style: GoogleFonts.outfit(
                                                      color: Colors.black,
                                                      fontSize: 17,
                                                      fontWeight:
                                                          FontWeight.w800,
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
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    Center(
                      child: GestureDetector(
                        onTap: _goToLogin,
                        child: Text.rich(
                          TextSpan(
                            text: 'Already have an account? ',
                            style: GoogleFonts.outfit(
                              color: soft,
                              fontSize: 15,
                            ),
                            children: [
                              TextSpan(
                                text: 'Sign In',
                                style: GoogleFonts.outfit(
                                  color: lime,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String value) {
    return Text(
      value,
      style: GoogleFonts.outfit(
        color: text,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      cursorColor: lime,
      style: GoogleFonts.outfit(
        color: text,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(
          color: soft.withValues(alpha: 0.7),
          fontSize: 15,
        ),
        prefixIcon: Icon(icon, color: soft),
        suffixIcon: suffix,
        filled: true,
        fillColor: field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: lime, width: 1.2),
        ),
      ),
    );
  }
}

class _PasswordStrengthIndicator extends StatelessWidget {
  final double value;
  final String label;
  final Color color;

  const _PasswordStrengthIndicator({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value == 0 ? 0.02 : value,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: color,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
