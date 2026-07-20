import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/gamification_service.dart';
import '../../widgets/gamification/achievement_badges.dart';
import '../../widgets/gamification/celebration_overlay.dart';
import '../../widgets/gamification/health_score_card.dart';
import '../../widgets/gamification/level_progress_bar.dart';
import '../../widgets/gamification/mission_card.dart';
import '../../widgets/gamification/streak_card.dart';
import '../../widgets/gamification/xp_level_card.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);
  static const Color text = Colors.white;

  bool _celebratedToday = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await GamificationService.ensureTodayReady();
      await GamificationService.syncMyProgressToLeaderboard();
      if (mounted && !_celebratedToday) {
        _celebratedToday = true;
        Future.delayed(const Duration(milliseconds: 350), () {
          if (!mounted) return;
          CelebrationOverlay.show(
            context,
            title: 'Progress hub opened',
            subtitle: 'Track your XP, streak, missions and badges here',
            icon: '🏆',
          );
        });
      }
    });
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator(color: lime)),
      );
    }

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
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              final user = userSnapshot.data?.data() ?? {};
              final today = _dateKey(DateTime.now());

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('daily_summary')
                    .doc(today)
                    .snapshots(),
                builder: (context, dailySnapshot) {
                  final daily = dailySnapshot.data?.data() ?? {};
                  return CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _header(context)),
                      SliverToBoxAdapter(
                        child: _topProgressGrid(uid, user, daily),
                      ),
                      SliverToBoxAdapter(child: _weightProgressCard(user)),
                      const SliverToBoxAdapter(child: SizedBox(height: 18)),
                      const SliverToBoxAdapter(child: HealthScoreCard()),
                      const SliverToBoxAdapter(child: SizedBox(height: 18)),
                      const SliverToBoxAdapter(child: DailyMissionCard()),
                      SliverToBoxAdapter(child: _weeklyChallengeCard(daily)),
                      const SliverToBoxAdapter(child: SizedBox(height: 18)),
                      const SliverToBoxAdapter(child: AchievementBadges()),
                      const SliverToBoxAdapter(child: SizedBox(height: 30)),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 17,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Progress',
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.1,
                    height: 0.98,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your health journey, rewards and missions',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => CelebrationOverlay.show(
              context,
              title: 'Keep going',
              subtitle: 'Small wins compound into real progress',
              icon: '⚡',
            ),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: lime,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: lime.withOpacity(0.25),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.black,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topProgressGrid(
    String uid,
    Map<String, dynamic> user,
    Map<String, dynamic> daily,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('achievements')
            .snapshots(),
        builder: (context, badgeSnapshot) {
          final unlockedBadges =
              badgeSnapshot.data?.docs
                  .where((d) => d.data()['unlocked'] == true)
                  .length ??
              0;
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _miniStatCard(
                      icon: '🔥',
                      valueStreamPath: 'streak',
                      label: 'Day Streak',
                      uid: uid,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: _badgeCountCard(unlockedBadges)),
                ],
              ),
              const SizedBox(height: 14),
              const XpLevelCard(),
              const SizedBox(height: 14),
              const StreakCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _miniStatCard({
    required String icon,
    required String valueStreamPath,
    required String label,
    required String uid,
  }) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('gamification')
          .doc('profile')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};
        final value = _asInt(data[valueStreamPath]);
        return _squareSummaryCard(icon: icon, value: '$value', label: label);
      },
    );
  }

  Widget _badgeCountCard(int value) {
    return _squareSummaryCard(
      icon: '🏅',
      value: '$value',
      label: 'Badges Earned',
    );
  }

  Widget _squareSummaryCard({
    required String icon,
    required String value,
    required String label,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 16 * (1 - t)),
        child: Opacity(opacity: t, child: child),
      ),
      child: Container(
        height: 174,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        decoration: _glassBox(radius: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 38)),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.outfit(
                color: text,
                fontSize: 30,
                height: 0.95,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 12.2,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatKg(double value) {
    if (value <= 0) return '--';
    return value.toStringAsFixed(1);
  }

  int _safeNextWeighInDays(Map<String, dynamic> user) {
    final raw = _asInt(
      user['nextWeighInDays'] ??
          user['nextWeightInDays'] ??
          user['weighInDays'],
      fallback: 7,
    );
    return raw.clamp(1, 30).toInt();
  }

  Future<void> _openWeightEditor(Map<String, dynamic> user) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final currentWeight = _asDouble(
      user['weightKg'] ?? user['currentWeightKg'],
      fallback: 0,
    );
    final startWeight = _asDouble(
      user['startWeightKg'],
      fallback: currentWeight,
    );
    final goalWeight = _asDouble(
      user['targetWeightKg'] ?? user['goalWeightKg'],
      fallback: currentWeight == 0 ? 0 : currentWeight - 4.3,
    );
    final nextDays = _safeNextWeighInDays(user);

    final currentCtrl = TextEditingController(
      text: currentWeight == 0 ? '' : currentWeight.toStringAsFixed(1),
    );
    final startCtrl = TextEditingController(
      text: startWeight == 0 ? '' : startWeight.toStringAsFixed(1),
    );
    final goalCtrl = TextEditingController(
      text: goalWeight == 0 ? '' : goalWeight.toStringAsFixed(1),
    );
    final nextCtrl = TextEditingController(text: '$nextDays');

    bool saving = false;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            Future<void> save() async {
              final current = double.tryParse(currentCtrl.text.trim());
              final start = double.tryParse(startCtrl.text.trim());
              final goal = double.tryParse(goalCtrl.text.trim());
              final next = int.tryParse(nextCtrl.text.trim()) ?? 7;

              if (current == null || current <= 0) {
                setSheet(() => errorText = 'Enter your current weight.');
                return;
              }
              if (start == null || start <= 0) {
                setSheet(() => errorText = 'Enter your start weight.');
                return;
              }
              if (goal == null || goal <= 0) {
                setSheet(() => errorText = 'Enter your goal weight.');
                return;
              }

              final cleanCurrent = double.parse(current.toStringAsFixed(1));
              final cleanStart = double.parse(start.toStringAsFixed(1));
              final cleanGoal = double.parse(goal.toStringAsFixed(1));
              final cleanNextDays = next.clamp(1, 30).toInt();
              final today = _dateKey(DateTime.now());
              final nextWeighInAt = DateTime.now().add(
                Duration(days: cleanNextDays),
              );

              setSheet(() {
                saving = true;
                errorText = null;
              });

              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .set({
                      'weightKg': cleanCurrent,
                      'currentWeightKg': cleanCurrent,
                      'startWeightKg': cleanStart,
                      'targetWeightKg': cleanGoal,
                      'goalWeightKg': cleanGoal,
                      'nextWeighInDays': cleanNextDays,
                      'nextWeightInDays': cleanNextDays,
                      'nextWeighInAt': Timestamp.fromDate(nextWeighInAt),
                      'lastWeighInDate': today,
                      'weightUpdatedAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('weight_logs')
                    .doc(today)
                    .set({
                      'date': today,
                      'weightKg': cleanCurrent,
                      'startWeightKg': cleanStart,
                      'targetWeightKg': cleanGoal,
                      'nextWeighInDays': cleanNextDays,
                      'createdAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                if (!mounted) return;
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Weight updated',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
                    ),
                    backgroundColor: card,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                setSheet(() {
                  saving = false;
                  errorText = 'Could not save weight: $e';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                decoration: const BoxDecoration(
                  color: Color(0xFF12180F),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: soft.withOpacity(0.34),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Update Weight',
                        style: GoogleFonts.outfit(
                          color: text,
                          fontSize: 27,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'This updates the Progress card, Profile and weight log.',
                        style: GoogleFonts.outfit(
                          color: soft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _weightField(
                        label: 'Current weight (kg)',
                        controller: currentCtrl,
                        icon: Icons.monitor_weight_rounded,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _weightField(
                              label: 'Start kg',
                              controller: startCtrl,
                              icon: Icons.flag_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _weightField(
                              label: 'Goal kg',
                              controller: goalCtrl,
                              icon: Icons.track_changes_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _weightField(
                        label: 'Next weigh-in after days',
                        controller: nextCtrl,
                        icon: Icons.event_available_rounded,
                        decimal: false,
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: GoogleFonts.outfit(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: saving ? null : save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: lime,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: saving
                              ? const SizedBox(
                                  width: 21,
                                  height: 21,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : Text(
                                  'Save Weight',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _weightField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool decimal = true,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      style: GoogleFonts.outfit(
        color: text,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.outfit(
          color: soft.withOpacity(0.72),
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(icon, color: lime, size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: lime.withOpacity(0.55), width: 1.3),
        ),
      ),
    );
  }

  Widget _weightProgressCard(Map<String, dynamic> user) {
    final currentWeight = _asDouble(
      user['weightKg'] ?? user['currentWeightKg'],
      fallback: 0,
    );
    final goalWeight = _asDouble(
      user['targetWeightKg'] ?? user['goalWeightKg'],
      fallback: currentWeight == 0 ? 0 : currentWeight - 4.3,
    );
    final startWeight = _asDouble(
      user['startWeightKg'],
      fallback: currentWeight,
    );
    final nextWeighInDays = _safeNextWeighInDays(user);

    final total = goalWeight == 0 || startWeight == goalWeight
        ? 0.0
        : (goalWeight - startWeight);
    final progress = total == 0
        ? 0.0
        : ((currentWeight - startWeight) / total).clamp(0.0, 1.0).toDouble();

    final remainingKg = currentWeight > 0 && goalWeight > 0
        ? (goalWeight - currentWeight).abs()
        : 0.0;
    final estimatedDays = remainingKg <= 0
        ? 0
        : ((remainingKg / 0.4) * 7).round().clamp(14, 180).toInt();
    final goalDate = DateTime.now().add(
      Duration(days: estimatedDays == 0 ? 0 : estimatedDays),
    );
    final hasGoal = currentWeight > 0 && goalWeight > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: GestureDetector(
        onTap: () => _openWeightEditor(user),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: _glassBox(radius: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Weight',
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentWeight == 0
                              ? '-- kg'
                              : '${currentWeight.toStringAsFixed(1)} kg',
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_rounded, color: lime, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Next weigh-in: ${nextWeighInDays}d',
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LevelProgressBar(
                progress: progress,
                color: lime,
                backgroundColor: Colors.white.withOpacity(0.09),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Start: ${_formatKg(startWeight)} kg',
                    style: GoogleFonts.outfit(
                      color: soft,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Goal: ${_formatKg(goalWeight)} kg',
                    style: GoogleFonts.outfit(
                      color: soft,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                hasGoal
                    ? 'At your goal by ${_monthName(goalDate.month)} ${goalDate.day}, ${goalDate.year}.'
                    : 'Tap this card to set your current, start and goal weight.',
                style: GoogleFonts.outfit(
                  color: text.withOpacity(0.88),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weeklyChallengeCard(Map<String, dynamic> daily) {
    final water = _asDouble(daily['waterLiters']);
    final steps = _asInt(daily['steps']);
    final protein = _asDouble(daily['protein']);
    final completed = [
      water >= 3,
      steps >= 8000,
      protein >= 120,
    ].where((e) => e).length;
    final progress = (completed / 3).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _glassBox(radius: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: lime.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: lime,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly Challenge',
                        style: GoogleFonts.outfit(
                          color: text,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Complete 3 core goals today',
                        style: GoogleFonts.outfit(
                          color: soft,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$completed/3',
                  style: GoogleFonts.outfit(
                    color: lime,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            LevelProgressBar(
              progress: progress,
              color: lime,
              backgroundColor: Colors.white.withOpacity(0.08),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _challengeChip('Water', water >= 3),
                _challengeChip('Steps', steps >= 8000),
                _challengeChip('Protein', protein >= 120),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _challengeChip(String label, bool done) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: done ? lime : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: done ? lime : Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_rounded : Icons.circle_outlined,
            color: done ? Colors.black : soft,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: done ? Colors.black : soft,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _glassBox({double radius = 24}) => BoxDecoration(
    color: card.withOpacity(0.92),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withOpacity(0.065)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.32),
        blurRadius: 24,
        offset: const Offset(0, 14),
      ),
    ],
  );

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }
}
