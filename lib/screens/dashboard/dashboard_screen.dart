import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../widgets/floating_bottom_nav.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  double _waterLiters = 3.0;

  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A3A18),
              Color(0xFF0F140D),
              Color(0xFF070907),
            ],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: lime));
              }

              final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

              return Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 118),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildPage(context, data),
                    ),
                  ),
                  Positioned(
                    left: 22,
                    right: 22,
                    bottom: 22,
                    child: FloatingBottomNav(
                      currentIndex: _selectedIndex,
                      onTap: (index) => setState(() => _selectedIndex = index),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, Map<String, dynamic> data) {
    switch (_selectedIndex) {
      case 1:
        return _placeholderPage(
          key: const ValueKey('nutrition'),
          title: 'Nutrition',
          subtitle: 'Scan food, log meals, and track calories.',
          icon: Icons.restaurant_rounded,
          buttonText: 'Scan Food',
        );
      case 2:
        return _placeholderPage(
          key: const ValueKey('health'),
          title: 'Health',
          subtitle: 'Connect ESP32 and monitor BPM, SpO2, and temperature.',
          icon: Icons.monitor_heart_rounded,
          buttonText: 'Start Scan',
          onTap: () => Navigator.pushNamed(context, '/health-monitor'),
        );
      case 3:
        return _placeholderPage(
          key: const ValueKey('reports'),
          title: 'Reports',
          subtitle: 'View your weekly nutrition and health progress.',
          icon: Icons.bar_chart_rounded,
          buttonText: 'View Reports',
        );
      case 4:
        return _profilePage(context, data);
      default:
        return _homePage(context, data);
    }
  }

  Widget _homePage(BuildContext context, Map<String, dynamic> data) {
    final name = data['name'] ?? 'User';
    final calories = data['targetCalories'] ?? 505;
    final protein = data['proteinGrams'] ?? '--';
    final carbs = data['carbsGrams'] ?? '--';
    final fats = data['fatsGrams'] ?? '--';
    final goal = data['goal'] ?? 'Fitness Goal';

    return SingleChildScrollView(
      key: const ValueKey('home'),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _topHeader(name),
          const SizedBox(height: 28),
          _calorieGraph(calories),
          const SizedBox(height: 28),
          _scheduleHeader(),
          const SizedBox(height: 18),
          _todayActivity(context),
          const SizedBox(height: 24),
          _waterIntakeCard(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _macroCard('Protein', '$protein g', Icons.fitness_center_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _macroCard('Carbs', '$carbs g', Icons.grain_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _macroCard('Fats', '$fats g', Icons.water_drop_rounded)),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Goal: $goal',
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _topHeader(String name) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            'Hi!,\n$name',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 32,
              height: 0.95,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ),
        Container(
          height: 64,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: lime.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(40),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFF11170F),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.search_rounded, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  color: card,
                ),
                child: const Icon(Icons.person_rounded, color: lime, size: 30),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _calorieGraph(dynamic calories) {
    return SizedBox(
      height: 215,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CalorieGraphPainter(),
            ),
          ),
          Positioned(
            left: 165,
            top: 18,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: lime,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$calories cal',
                    style: GoogleFonts.outfit(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                CustomPaint(
                  size: const Size(16, 10),
                  painter: _TrianglePainter(),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['Mon', 'Tues', 'Wed', 'Thurs', 'Fri', 'Sat', 'Sun']
                  .map(
                    (day) => Text(
                      day,
                      style: GoogleFonts.outfit(
                        color: day == 'Fri' ? Colors.white : soft.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontWeight: day == 'Fri' ? FontWeight.w800 : FontWeight.w500,
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

  Widget _scheduleHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Your\nSchedule',
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 27,
              height: 0.95,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFDDF9F5),
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(Icons.tune_rounded, color: Colors.black),
        ),
      ],
    );
  }

  Widget _todayActivity(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today’s Activity',
          style: GoogleFonts.outfit(
            color: text.withValues(alpha: 0.85),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Column(
              children: [
                _timelineDot(active: true),
                Container(width: 1, height: 42, color: soft.withValues(alpha: 0.35)),
                _timelineDot(active: false),
              ],
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WarmUp',
                    style: GoogleFonts.outfit(
                      color: text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Run 02 km',
                    style: GoogleFonts.outfit(
                      color: soft.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Muscle Up',
                    style: GoogleFonts.outfit(
                      color: soft.withValues(alpha: 0.75),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '10 reps, 3 sets with 20 sec rest',
                    style: GoogleFonts.outfit(
                      color: soft.withValues(alpha: 0.45),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/health-monitor'),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                'Start',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: lime,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _waterIntakeCard() {
    const int totalCups = 7;
    final int filledCups = _waterLiters.round().clamp(0, totalCups);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _premiumBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Water Intake',
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Recommended 7 liters',
            style: GoogleFonts.outfit(
              color: soft.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: List.generate(totalCups, (index) {
                final bool isFilled = index < filledCups;

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _waterLiters = (index + 1).toDouble();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: 34,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isFilled ? lime : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isFilled ? lime : soft.withValues(alpha: 0.35),
                          width: 1.4,
                        ),
                        boxShadow: isFilled
                            ? [
                                BoxShadow(
                                  color: lime.withValues(alpha: 0.22),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : [],
                      ),
                      child: Icon(
                        isFilled ? Icons.water_drop_rounded : Icons.add_rounded,
                        color: isFilled ? Colors.black : soft.withValues(alpha: 0.6),
                        size: 18,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              activeTrackColor: lime,
              inactiveTrackColor: soft.withValues(alpha: 0.15),
              thumbColor: lime,
              overlayColor: lime.withValues(alpha: 0.18),
              valueIndicatorColor: lime,
              valueIndicatorTextStyle: GoogleFonts.outfit(
                color: Colors.black,
                fontWeight: FontWeight.w800,
              ),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              min: 0,
              max: 7,
              divisions: 7,
              value: _waterLiters,
              label: '${_waterLiters.toStringAsFixed(0)}L',
              onChanged: (value) {
                setState(() {
                  _waterLiters = value;
                });
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_waterLiters.toStringAsFixed(0)}L completed',
                style: GoogleFonts.outfit(
                  color: lime,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '7L target',
                style: GoogleFonts.outfit(
                  color: soft.withValues(alpha: 0.65),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timelineDot({required bool active}) {
    return Container(
      width: active ? 42 : 11,
      height: active ? 42 : 11,
      decoration: BoxDecoration(
        color: active ? lime : soft.withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
      child: active
          ? const Center(
              child: CircleAvatar(radius: 5, backgroundColor: Color(0xFF171D13)),
            )
          : null,
    );
  }

  Widget _macroCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _premiumBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: lime, size: 21),
          const SizedBox(height: 12),
          Text(title, style: GoogleFonts.outfit(color: soft, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profilePage(BuildContext context, Map<String, dynamic> data) {
    return SingleChildScrollView(
      key: const ValueKey('profile'),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profile',
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(data['email'] ?? 'Logged in user', style: GoogleFonts.outfit(color: soft)),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: _premiumBox(),
            child: Column(
              children: [
                _profileRow('Goal', data['goal'] ?? '-'),
                _profileRow('Height', '${data['heightCm'] ?? '--'} cm'),
                _profileRow('Weight', '${data['weightKg'] ?? '--'} kg'),
                _profileRow('Workouts', '${data['workoutsPerWeek'] ?? '--'} / week'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton(
              onPressed: () => _logout(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: Text(
                'Logout',
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderPage({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required String buttonText,
    VoidCallback? onTap,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(color: text, fontSize: 36, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: GoogleFonts.outfit(color: soft, fontSize: 15, height: 1.45)),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: _premiumBox(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: lime, size: 42),
              const SizedBox(height: 18),
              Text(
                title,
                style: GoogleFonts.outfit(color: text, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: GoogleFonts.outfit(color: soft, fontSize: 14.5)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: lime,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                ),
                child: Text(
                  buttonText,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(label, style: GoogleFonts.outfit(color: soft, fontSize: 14)),
          const Spacer(),
          Text(value, style: GoogleFonts.outfit(color: text, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  BoxDecoration _premiumBox() {
    return BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 22,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }
}

class _CalorieGraphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFD9F6F2)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final verticalPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    final dotPaint = Paint()
      ..color = const Color(0xFFD6FF60)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 145);
    path.cubicTo(42, 116, 62, 112, 82, 125);
    path.cubicTo(112, 150, 123, 151, 145, 113);
    path.cubicTo(158, 92, 172, 111, 199, 65);
    path.cubicTo(216, 37, 233, 79, 252, 108);
    path.cubicTo(272, 112, 288, 108, 312, 108);

    canvas.drawPath(path, linePaint);

    const selectedX = 199.0;
    const selectedY = 65.0;

    canvas.drawLine(
      const Offset(selectedX, selectedY),
      Offset(selectedX, size.height - 28),
      verticalPaint,
    );

    canvas.drawCircle(const Offset(selectedX, selectedY), 7, dotPaint);
    canvas.drawCircle(
      const Offset(selectedX, selectedY),
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFD6FF60);
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}