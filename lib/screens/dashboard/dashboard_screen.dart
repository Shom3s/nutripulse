import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/floating_bottom_nav.dart';
import '../food/food_log_screen.dart';
import '../chat/chatbot_screen.dart';
import '../profile/progress_screen.dart';
import '../community/community_screen.dart';
import '../health/health_monitor_screen.dart';
import '../notifications/daily_report_detail_screen.dart';
import '../activity/activity_home_screen.dart';
import '../settings/app_settings_screen.dart';
import '../../services/gamification_service.dart';
import '../../theme/nutripulse_theme_controller.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _selectedNutritionDate = DateTime.now();
  int _selectedIndex = 0;
  final PageController _pageController = PageController(initialPage: 0);

  // The current page index, exposed as a notifier so the bottom nav can rebuild
  // its highlight on its own WITHOUT triggering a full-screen setState that
  // would rebuild all six pages on every swipe. This is the main thing that
  // keeps swiping buttery.
  final ValueNotifier<int> _pageIndexNotifier = ValueNotifier<int>(0);

  // Instagram-style bottom dock behaviour:
  // scroll down = slightly minimized, scroll up / nav tap = normal size.
  // A ValueNotifier keeps this animation inside the nav only, without
  // rebuilding the heavy pages while the user scrolls.
  final ValueNotifier<bool> _navCompactNotifier = ValueNotifier<bool>(false);
  DateTime _navExpandLockUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastNavCompactChangeAt;

  // Standalone screens are built once and reused. Rebuilding them on every
  // Firestore update or page change was forcing their Firestore streams,
  // charts and ESP32 health UI to spin up repeatedly — the real source of the
  // navigation lag. Holding the instances keeps them cheap to revisit.
  late final Widget _healthPage = const HealthMonitorScreen();
  late final Widget _activityPage = const ActivityHomeScreen();
  late final Widget _communityPage = const CommunityScreen();

  // Bumped each time the Dashboard becomes visible (via tap) so its card
  // entrance animation replays on each visit. Nutrition has no entrance.
  int _homeEntranceSeed = 0;
  double _waterLiters = 0.0;
  double _lastWaterGoalLiters = 3.0;
  int _todaySteps = 0;
  bool _isLoadingSteps = false;
  String? _stepsError;
  bool _usingDemoSteps = false;
  String _stepsSourceLabel = 'Phone sensor';
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<PedestrianStatus>? _pedestrianStatusSubscription;
  int? _todayBaselineSteps;
  int _rawSensorSteps = 0;
  final ValueNotifier<_StepViewState> _stepView = ValueNotifier<_StepViewState>(
    const _StepViewState(
      steps: 0,
      isLoading: false,
      error: null,
      usingDemo: false,
      sourceLabel: 'Phone sensor',
    ),
  );
  final ValueNotifier<double> _waterLitersView = ValueNotifier<double>(0.0);
  Timer? _waterSaveDebounce;
  Timer? _waterMidnightResetTimer;
  DateTime? _lastStepUiUpdateAt;
  DateTime? _lastStepFirestoreSaveAt;
  int _lastStepUiValue = -1;
  int _lastStepSavedValue = -1;
  Offset? _aiButtonOffset;
  bool _isDraggingAiButton = false;
  bool _aiFloatingButtonEnabled = true;
  bool _graphAnimationEnabled = true;
  bool _reduceAnimations = false;
  int _homeGraphAnimationSeed = 0;

  String? _weeklyGraphSignature;
  bool _weeklyGraphAnimatedOnce = false;

  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  static const String _prefAiFloatingButton = 'setting_ai_floating_button';
  static const String _prefAiResetPositionRequest =
      'setting_ai_reset_position_request';
  static const String _prefAiButtonDx = 'setting_ai_button_dx';
  static const String _prefAiButtonDy = 'setting_ai_button_dy';
  static const String _prefGraphAnimation = 'setting_graph_animation_enabled';
  static const String _prefReduceAnimations = 'setting_reduce_animations';
  static const String _prefWaterDate = 'dashboard_today_water_date';
  static const String _prefWaterLiters = 'dashboard_today_water_liters';
  static const String _prefWaterGoalLiters =
      'dashboard_today_water_goal_liters';
  static const String _prefWaterSavedAtMs = 'dashboard_today_water_saved_at_ms';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboardSettings();
      _loadTodaySteps();
      GamificationService.ensureTodayReady();
      _loadTodayWater();
      _scheduleWaterMidnightReset();
    });
  }

  Future<void> _loadDashboardSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final resetAiPosition =
          prefs.getBool(_prefAiResetPositionRequest) ?? false;
      final savedDx = prefs.getDouble(_prefAiButtonDx);
      final savedDy = prefs.getDouble(_prefAiButtonDy);

      if (!mounted) return;

      setState(() {
        _aiFloatingButtonEnabled = prefs.getBool(_prefAiFloatingButton) ?? true;
        _graphAnimationEnabled = prefs.getBool(_prefGraphAnimation) ?? true;
        _reduceAnimations = prefs.getBool(_prefReduceAnimations) ?? false;

        if (resetAiPosition) {
          _aiButtonOffset = null;
        } else if (savedDx != null && savedDy != null) {
          _aiButtonOffset = Offset(savedDx, savedDy);
        }
      });

      if (resetAiPosition) {
        await prefs.setBool(_prefAiResetPositionRequest, false);
        await prefs.remove(_prefAiButtonDx);
        await prefs.remove(_prefAiButtonDy);
      }
    } catch (_) {
      // Keep dashboard usable if local settings cannot be loaded.
    }
  }

  Future<void> _saveAiButtonOffset(Offset offset) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefAiButtonDx, offset.dx);
      await prefs.setDouble(_prefAiButtonDy, offset.dy);
    } catch (_) {}
  }

  @override
  void dispose() {
    // Do not lose the last water tap/slider value when the user closes the app
    // before the debounce timer fires. This was the reason water returned to 0L.
    _waterSaveDebounce?.cancel();
    _waterMidnightResetTimer?.cancel();
    if (_waterLitersView.value != _waterLiters) {
      _waterLiters = _waterLitersView.value;
    }
    if (_waterLiters > 0) {
      unawaited(
        _saveLocalWaterSnapshot(
          liters: _waterLiters,
          waterGoal: _lastWaterGoalLiters,
        ),
      );
      unawaited(
        _commitWaterIntake(
          liters: _waterLiters,
          waterGoal: _lastWaterGoalLiters,
          previousLiters: _waterLiters,
        ),
      );
    }

    _pageIndexNotifier.dispose();
    _navCompactNotifier.dispose();
    _pageController.dispose();
    _stepCountSubscription?.cancel();
    _pedestrianStatusSubscription?.cancel();
    _stepView.dispose();
    _waterLitersView.dispose();
    super.dispose();
  }

  void _applyWaterValue(double liters, {double? waterGoal}) {
    final goal = (waterGoal ?? _lastWaterGoalLiters) <= 0
        ? 3.0
        : (waterGoal ?? _lastWaterGoalLiters);
    _lastWaterGoalLiters = goal;

    final snapped = (liters * 2).round() / 2;
    final safeWater = snapped.clamp(0.0, goal).toDouble();
    _waterLiters = safeWater;
    _waterLitersView.value = safeWater;
  }

  String _waterUserPrefKey(String uid, String key) => '${key}_$uid';

  Future<void> _clearLegacyWaterSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Old keys were shared by every login on the same phone. Removing them
      // stops one user's 3L value from appearing on another user's dashboard.
      await prefs.remove(_prefWaterDate);
      await prefs.remove(_prefWaterLiters);
      await prefs.remove(_prefWaterGoalLiters);
      await prefs.remove(_prefWaterSavedAtMs);
    } catch (_) {}
  }

  Future<double?> _loadLocalWaterSnapshot(String uid, String today) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDate = prefs.getString(_waterUserPrefKey(uid, _prefWaterDate));
      if (savedDate != today) return null;

      final localWater = prefs.getDouble(
        _waterUserPrefKey(uid, _prefWaterLiters),
      );
      final localGoal = prefs.getDouble(
        _waterUserPrefKey(uid, _prefWaterGoalLiters),
      );
      if (localGoal != null && localGoal > 0) {
        _lastWaterGoalLiters = localGoal;
      }
      return localWater == null ? null : localWater.clamp(0.0, 20.0).toDouble();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLocalWaterSnapshot({
    required double liters,
    required double waterGoal,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final prefs = await SharedPreferences.getInstance();
      final today = _dateKey(DateTime.now());
      final cleanGoal = waterGoal <= 0 ? 3.0 : waterGoal;
      final cleanLiters = liters.clamp(0.0, cleanGoal).toDouble();

      await prefs.setString(_waterUserPrefKey(uid, _prefWaterDate), today);
      await prefs.setDouble(
        _waterUserPrefKey(uid, _prefWaterLiters),
        cleanLiters,
      );
      await prefs.setDouble(
        _waterUserPrefKey(uid, _prefWaterGoalLiters),
        cleanGoal,
      );
      await prefs.setInt(
        _waterUserPrefKey(uid, _prefWaterSavedAtMs),
        DateTime.now().millisecondsSinceEpoch,
      );

      // Clean up the old global cache so it cannot leak between accounts.
      await prefs.remove(_prefWaterDate);
      await prefs.remove(_prefWaterLiters);
      await prefs.remove(_prefWaterGoalLiters);
      await prefs.remove(_prefWaterSavedAtMs);
    } catch (_) {}
  }

  Future<void> _loadTodayWater() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _applyWaterValue(0.0);
      return;
    }

    final uid = user.uid;
    final today = _dateKey(DateTime.now());
    double? localWater;

    // Important fix: old SharedPreferences water keys were not user-specific.
    // Clear them first so a previous account's 3L value cannot be reused.
    await _clearLegacyWaterSnapshot();

    // 1) Show today's local value immediately, but only for this exact user.
    localWater = await _loadLocalWaterSnapshot(uid, today);
    if (localWater != null && mounted) {
      _applyWaterValue(localWater);
    } else if (mounted) {
      _applyWaterValue(0.0);
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('daily_summary')
          .doc(today)
          .get()
          .timeout(const Duration(seconds: 6));

      final data = doc.data() ?? {};
      final firestoreWater = _safeDouble(data['waterLiters'], fallback: 0.0);
      final firestoreGoal = _safeDouble(
        data['waterGoal'],
        fallback: _lastWaterGoalLiters,
      );

      if (!mounted) return;

      // After the old shared-cache bug is removed, local data is safe to prefer
      // because it belongs to this Firebase uid and this date only.
      final chosenWater = localWater ?? firestoreWater;
      _applyWaterValue(chosenWater, waterGoal: firestoreGoal);

      // If this user's local value was newer/not yet synced, push it back.
      if (localWater != null && (firestoreWater - localWater).abs() > 0.01) {
        unawaited(
          _commitWaterIntake(
            liters: localWater,
            waterGoal: firestoreGoal,
            previousLiters: firestoreWater,
          ),
        );
      }
    } catch (_) {
      // If Firebase is unavailable, keep this user's local value. No local value
      // means a clean new-day dashboard should stay at 0L.
      if (localWater == null && mounted) {
        _applyWaterValue(0.0);
      }
    }
  }

  void _scheduleWaterMidnightReset() {
    _waterMidnightResetTimer?.cancel();

    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final delay = nextMidnight.difference(now) + const Duration(seconds: 2);

    _waterMidnightResetTimer = Timer(delay, () {
      if (!mounted) return;
      _applyWaterValue(0.0);
      unawaited(
        _saveLocalWaterSnapshot(
          liters: 0.0,
          waterGoal: _lastWaterGoalLiters,
        ),
      );
      unawaited(_loadTodayWater());
      _scheduleWaterMidnightReset();
    });
  }

  Future<void> _updateWaterIntake(
    double liters, {
    double waterGoal = 3.0,
  }) async {
    final safeGoal = waterGoal <= 0 ? 3.0 : waterGoal;
    _lastWaterGoalLiters = safeGoal;
    final previous = _waterLiters;

    // Water is tracked in clean 0.5L steps. UI + local storage update instantly.
    // Firestore/gamification write is debounced to avoid slider jank.
    final snappedLiters = (liters * 2).round() / 2;
    final cleanLiters = snappedLiters.clamp(0.0, safeGoal).toDouble();

    if (_waterLiters == cleanLiters && _waterLitersView.value == cleanLiters) {
      return;
    }

    _waterLiters = cleanLiters;
    _waterLitersView.value = cleanLiters;
    unawaited(
      _saveLocalWaterSnapshot(liters: cleanLiters, waterGoal: safeGoal),
    );

    _waterSaveDebounce?.cancel();
    _waterSaveDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(
        _commitWaterIntake(
          liters: cleanLiters,
          waterGoal: safeGoal,
          previousLiters: previous,
        ),
      );
    });
  }

  Future<void> _commitWaterIntake({
    required double liters,
    required double waterGoal,
    required double previousLiters,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final today = _dateKey(DateTime.now());
      final safeGoal = waterGoal <= 0 ? 3.0 : waterGoal;
      final cleanLiters = (((liters * 2).round() / 2).clamp(
        0.0,
        safeGoal,
      )).toDouble();

      // Save directly first. This guarantees Dashboard reload can read the value
      // even if GamificationService is slow or throws later.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('daily_summary')
          .doc(today)
          .set({
            'date': today,
            'waterLiters': cleanLiters,
            'waterGoal': safeGoal,
            'waterDate': today,
            'waterLoggedByUid': uid,
            'waterUpdatedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 6));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'waterLiters': cleanLiters,
            'waterGoal': safeGoal,
            'waterGoalLiters': safeGoal,
            'waterDate': today,
            'waterUpdatedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 6));

      await GamificationService.updateWater(
        liters: cleanLiters,
        waterGoal: safeGoal,
      );

      if (!mounted) return;
      if (previousLiters < safeGoal && cleanLiters >= safeGoal) {
        // Existing celebration hook stays intentionally empty.
      }
    } catch (_) {
      // Local SharedPreferences already has the latest value, so the UI will not
      // fall back to 0L. Firestore can sync again on the next water change/open.
    }
  }

  /// Reads steps directly from the phone step sensor using pedometer.
  /// Android returns total steps since last reboot, so NutriPulse stores a
  /// daily baseline in Firestore and calculates: today = sensor - baseline.
  Future<void> _loadTodaySteps() async {
    if (_isLoadingSteps) return;

    _isLoadingSteps = true;
    _stepsError = null;
    _usingDemoSteps = false;
    _stepsSourceLabel = 'Phone sensor';
    _stepView.value = _stepView.value.copyWith(
      isLoading: true,
      error: null,
      clearError: true,
      usingDemo: false,
      sourceLabel: 'Phone sensor',
    );

    try {
      await _loadSavedStepsFromFirestore();
      _startPedometerStream();

      if (!mounted) return;
      _isLoadingSteps = false;
      _stepsError = _todaySteps == 0
          ? 'Walk a few steps, then this will update live.'
          : null;
      _stepView.value = _stepView.value.copyWith(
        isLoading: false,
        error: _stepsError,
      );
    } catch (e) {
      if (!mounted) return;
      _isLoadingSteps = false;
      _stepsError =
          'Step sensor unavailable. Check Physical activity permission.';
      _stepView.value = _stepView.value.copyWith(
        isLoading: false,
        error: _stepsError,
        sourceLabel: 'Sensor unavailable',
      );
    }
  }

  void _startPedometerStream() {
    _stepCountSubscription?.cancel();
    _pedestrianStatusSubscription?.cancel();

    _stepCountSubscription = Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStepCountError,
      cancelOnError: false,
    );

    _pedestrianStatusSubscription = Pedometer.pedestrianStatusStream.listen(
      (_) {},
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> _onStepCount(StepCount event) async {
    final currentRawSteps = event.steps;
    _rawSensorSteps = currentRawSteps;

    if (_todayBaselineSteps == null || currentRawSteps < _todayBaselineSteps!) {
      _todayBaselineSteps = currentRawSteps;
      await _saveStepBaselineToFirestore(currentRawSteps);
    }

    final calculatedTodaySteps =
        (currentRawSteps - (_todayBaselineSteps ?? currentRawSteps))
            .clamp(0, 100000)
            .toInt();

    final now = DateTime.now();
    final shouldUpdateUi =
        _isLoadingSteps ||
        _lastStepUiUpdateAt == null ||
        now.difference(_lastStepUiUpdateAt!).inMilliseconds >= 850 ||
        (calculatedTodaySteps - _lastStepUiValue).abs() >= 12;

    if (shouldUpdateUi && mounted) {
      _lastStepUiUpdateAt = now;
      _lastStepUiValue = calculatedTodaySteps;

      _todaySteps = calculatedTodaySteps;
      _usingDemoSteps = false;
      _stepsSourceLabel = 'Phone sensor';
      _stepsError = calculatedTodaySteps == 0
          ? 'Real sensor connected. Walk a few steps to update.'
          : null;
      _isLoadingSteps = false;
      _stepView.value = _StepViewState(
        steps: calculatedTodaySteps,
        isLoading: false,
        error: _stepsError,
        usingDemo: false,
        sourceLabel: 'Phone sensor',
      );
    }

    final shouldSave =
        _lastStepFirestoreSaveAt == null ||
        now.difference(_lastStepFirestoreSaveAt!).inSeconds >= 12 ||
        (calculatedTodaySteps - _lastStepSavedValue).abs() >= 35;

    if (shouldSave) {
      _lastStepFirestoreSaveAt = now;
      _lastStepSavedValue = calculatedTodaySteps;

      unawaited(
        _saveTodayStepsToFirestore(
          steps: calculatedTodaySteps,
          source: 'pedometer_sensor',
          isDemo: false,
          rawSensorSteps: currentRawSteps,
          baselineSteps: _todayBaselineSteps ?? currentRawSteps,
        ),
      );

      unawaited(GamificationService.updateSteps(steps: calculatedTodaySteps));
    }
  }

  void _onStepCountError(Object error) {
    if (!mounted) return;
    _stepsError = 'Unable to read step sensor: $error';
    _isLoadingSteps = false;
    _stepsSourceLabel = 'Sensor unavailable';
    _stepView.value = _stepView.value.copyWith(
      isLoading: false,
      error: _stepsError,
      sourceLabel: _stepsSourceLabel,
    );
  }

  Future<void> _loadSavedStepsFromFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final today = _dateKey(DateTime.now());
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('activity')
          .doc(today)
          .get()
          .timeout(const Duration(seconds: 6));

      final data = doc.data() ?? {};
      _todayBaselineSteps = _safeInt(data['baselineSteps'], fallback: -1);
      if (_todayBaselineSteps == -1) _todayBaselineSteps = null;

      final savedSteps = _safeInt(data['steps'], fallback: 0);
      if (mounted && savedSteps > 0) {
        _todaySteps = savedSteps;
        _stepsSourceLabel = 'Phone sensor';
        _stepView.value = _stepView.value.copyWith(
          steps: savedSteps,
          sourceLabel: 'Phone sensor',
        );
      }
    } catch (_) {
      // Pedometer stream can still work even if Firestore read fails.
    }
  }

  Future<void> _saveStepBaselineToFirestore(int baselineSteps) async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final today = _dateKey(DateTime.now());
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('activity')
          .doc(today)
          .set({
            'baselineSteps': baselineSteps,
            'date': today,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  Future<void> _saveTodayStepsToFirestore({
    required int steps,
    required String source,
    required bool isDemo,
    int? rawSensorSteps,
    int? baselineSteps,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final today = _dateKey(DateTime.now());
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('activity')
          .doc(today)
          .set({
            'steps': steps,
            'source': source,
            'isDemo': isDemo,
            'rawSensorSteps': rawSensorSteps ?? _rawSensorSteps,
            'baselineSteps': baselineSteps ?? _todayBaselineSteps,
            'date': today,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // Step display should not fail just because saving activity failed.
    }
  }

  void _showEditStepGoal(BuildContext context, Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final currentGoal = _safeInt(data['stepGoal'], fallback: 8000);
    final goalCtrl = TextEditingController(text: currentGoal.toString());
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(context).viewInsets.bottom + 28,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF141A11),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: soft.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Edit Step Goal',
                style: GoogleFonts.outfit(
                  color: text,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Set your daily walking target.',
                style: GoogleFonts.outfit(color: soft, fontSize: 13),
              ),
              const SizedBox(height: 22),
              _editField(
                'Daily steps goal',
                goalCtrl,
                icon: Icons.directions_walk_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 22),
              Row(
                children: [4000, 6000, 8000, 10000].map((goal) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          goalCtrl.text = goal.toString();
                          setSheet(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: lime.withOpacity(0.18)),
                          ),
                          child: Text(
                            '${goal ~/ 1000}k',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: lime,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final newGoal =
                              int.tryParse(goalCtrl.text.trim()) ?? currentGoal;
                          setSheet(() => isSaving = true);
                          try {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .update({
                                  'stepGoal': newGoal.clamp(1000, 50000),
                                });
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            setSheet(() => isSaving = false);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Could not save step goal: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lime,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: isSaving
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(
                          'Save Goal',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
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
  }

  String _formatNumber(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  String _safeString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final converted = value.toString().trim();
    return converted.isEmpty ? fallback : converted;
  }

  int _safeInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _safeDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _initialsFrom(dynamic value) {
    final safeName = _safeString(value, fallback: 'User');
    final parts = safeName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String e) => e.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'U';

    return parts
        .map((String e) => e.substring(0, 1))
        .take(2)
        .join()
        .toUpperCase();
  }

  Uint8List? _decodeBase64Photo(dynamic value) {
    final photo = _safeString(value);
    if (photo.isEmpty) return null;

    try {
      return base64Decode(photo);
    } catch (_) {
      return null;
    }
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (r) => false);
  }

  Future<void> _pickProfilePhoto(BuildContext context) async {
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141A11),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: soft.withOpacity(0.35),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Change Profile Photo',
              style: GoogleFonts.outfit(
                color: text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a clean photo for your NutriPulse profile.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: soft, fontSize: 13),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      final picked = await picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 65,
                        maxWidth: 600,
                      );
                      if (picked != null) {
                        await _uploadProfilePhoto(File(picked.path));
                      }
                    },
                    child: _profilePhotoOption(
                      icon: Icons.camera_alt_rounded,
                      title: 'Camera',
                      subtitle: 'Take photo',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 65,
                        maxWidth: 600,
                      );
                      if (picked != null) {
                        await _uploadProfilePhoto(File(picked.path));
                      }
                    },
                    child: _profilePhotoOption(
                      icon: Icons.photo_library_rounded,
                      title: 'Gallery',
                      subtitle: 'Pick image',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _profilePhotoOption({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.26),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: lime, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.outfit(
              color: soft.withOpacity(0.75),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadProfilePhoto(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Photo = base64Encode(bytes);
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'photoBase64': base64Photo,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile photo updated',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFF1A1F17),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo upload failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _avatarImageLayer({
    required Uint8List? photoBytes,
    required String initials,
    required double size,
    required double fontSize,
  }) {
    if (photoBytes == null) {
      return Center(
        key: ValueKey('initials-$initials'),
        child: Text(
          initials,
          style: GoogleFonts.outfit(
            color: lime,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return Container(
      key: ValueKey('profile-photo-${photoBytes.length}'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        image: DecorationImage(
          image: MemoryImage(photoBytes),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }

  Widget _animatedAvatar({
    required Map<String, dynamic> data,
    required String initials,
    required double size,
    required double fontSize,
    bool showGlow = false,
  }) {
    final photoBytes = _decodeBase64Photo(data['photoBase64']);

    return Hero(
      tag: 'profile-avatar-hero',
      flightShuttleBuilder:
          (
            flightContext,
            animation,
            flightDirection,
            fromHeroContext,
            toHeroContext,
          ) {
            return ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: toHeroContext.widget,
            );
          },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: card,
          border: Border.all(
            color: showGlow
                ? lime.withOpacity(0.92)
                : Colors.white.withOpacity(0.10),
            width: showGlow ? 2.7 : 1,
          ),
          boxShadow: const [],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
                child: child,
              ),
            );
          },
          child: _avatarImageLayer(
            photoBytes: photoBytes,
            initials: initials,
            size: size,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }

  // ── Edit profile bottom sheet ──────────────────────────────
  void _showEditProfile(BuildContext context, Map<String, dynamic> data) {
    final nameCtrl = TextEditingController(text: _safeString(data['name']));
    final heightCtrl = TextEditingController(
      text: data['heightCm']?.toString() ?? '',
    );
    final weightCtrl = TextEditingController(
      text: data['weightKg']?.toString() ?? '',
    );
    final workCtrl = TextEditingController(
      text: data['workoutsPerWeek']?.toString() ?? '',
    );
    String selectedGoal = _safeString(data['goal'], fallback: 'Lose weight');
    bool isSaving = false;

    const goals = [
      'Lose weight',
      'Gain weight',
      'Build muscle',
      'Stay fit',
      'Eat healthy',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          height:
              MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).size.height * 0.88,
          decoration: const BoxDecoration(
            color: Color(0xFF141A11),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: soft.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Profile',
                        style: GoogleFonts.outfit(
                          color: text,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Changes save to Firebase instantly',
                        style: GoogleFonts.outfit(color: soft, fontSize: 13),
                      ),
                      const SizedBox(height: 28),

                      _editField('Name', nameCtrl, icon: Icons.person_rounded),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: _editField(
                              'Height (cm)',
                              heightCtrl,
                              icon: Icons.height_rounded,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _editField(
                              'Weight (kg)',
                              weightCtrl,
                              icon: Icons.monitor_weight_rounded,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _editField(
                        'Workouts / week',
                        workCtrl,
                        icon: Icons.fitness_center_rounded,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 24),

                      Text(
                        'Fitness Goal',
                        style: GoogleFonts.outfit(
                          color: soft,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: goals.map((g) {
                          final sel = g == selectedGoal;
                          return GestureDetector(
                            onTap: () => setSheet(() => selectedGoal = g),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: sel ? lime : card,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: sel ? lime : soft.withOpacity(0.2),
                                ),
                              ),
                              child: Text(
                                g,
                                style: GoogleFonts.outfit(
                                  color: sel ? Colors.black : soft,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 36),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setSheet(() => isSaving = true);
                                  try {
                                    final uid =
                                        FirebaseAuth.instance.currentUser!.uid;
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .update({
                                          'name': nameCtrl.text.trim(),
                                          'heightCm':
                                              double.tryParse(
                                                heightCtrl.text,
                                              ) ??
                                              0,
                                          'weightKg':
                                              double.tryParse(
                                                weightCtrl.text,
                                              ) ??
                                              0,
                                          'workoutsPerWeek':
                                              int.tryParse(workCtrl.text) ?? 0,
                                          'goal': selectedGoal,
                                        });
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  } catch (e) {
                                    setSheet(() => isSaving = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: lime,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: isSaving
                              ? const CircularProgressIndicator(
                                  color: Colors.black,
                                )
                              : Text(
                                  'Save Changes',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editField(
    String label,
    TextEditingController ctrl, {
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: soft,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: GoogleFonts.outfit(color: text, fontSize: 15),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: lime, size: 20),
            filled: true,
            fillColor: card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: lime.withOpacity(0.5), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _openGlobalAiCoach() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: const ChatbotScreen(),
          );
        },
      ),
    );
  }

  Widget _globalAiFloatingButton(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    const buttonSize = 50.0;
    final defaultOffset = Offset(
      screen.width - buttonSize - 16,
      screen.height - bottomSafe - 178,
    );

    _aiButtonOffset ??= defaultOffset;

    final left = _aiButtonOffset!.dx.clamp(
      10.0,
      screen.width - buttonSize - 10,
    );
    final top = _aiButtonOffset!.dy.clamp(
      72.0,
      screen.height - bottomSafe - 126.0,
    );

    return AnimatedPositioned(
      duration: _isDraggingAiButton || _reduceAnimations
          ? Duration.zero
          : const Duration(milliseconds: 210),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          setState(() => _isDraggingAiButton = true);
        },
        onPanUpdate: (details) {
          final next = Offset(
            (left + details.delta.dx).clamp(
              10.0,
              screen.width - buttonSize - 10,
            ),
            (top + details.delta.dy).clamp(
              72.0,
              screen.height - bottomSafe - 126.0,
            ),
          );
          setState(() => _aiButtonOffset = next);
        },
        onPanEnd: (_) {
          final current = _aiButtonOffset ?? Offset(left, top);
          final snapX = current.dx < screen.width / 2
              ? 14.0
              : screen.width - buttonSize - 14.0;

          final snappedOffset = Offset(
            snapX,
            current.dy.clamp(72.0, screen.height - bottomSafe - 126.0),
          );

          setState(() {
            _isDraggingAiButton = false;
            _aiButtonOffset = snappedOffset;
          });

          _saveAiButtonOffset(snappedOffset);
        },
        onPanCancel: () {
          setState(() => _isDraggingAiButton = false);
        },
        onTap: _openGlobalAiCoach,
        child: RepaintBoundary(
          child: AnimatedScale(
            scale: _isDraggingAiButton ? 1.06 : 1.0,
            duration: _reduceAnimations
                ? Duration.zero
                : const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE9FF8E),
                    Color(0xFFD6FF60),
                    Color(0xFFAEEA32),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.28),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: lime.withOpacity(_isDraggingAiButton ? 0.24 : 0.34),
                    blurRadius: _isDraggingAiButton ? 14 : 24,
                    offset: const Offset(0, 3),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.32),
                    blurRadius: _isDraggingAiButton ? 10 : 18,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.06),
                    ),
                  ),
                  const Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.black,
                    size: 24,
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Color(0xFFD6FF60),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setNavCompact(bool compact, {bool force = false}) {
    final now = DateTime.now();

    // After the user taps any dock button, keep the dock expanded briefly.
    // Otherwise the current scroll position can immediately send another
    // ScrollNotification and shrink it again before the user sees it restore.
    if (!force && compact && now.isBefore(_navExpandLockUntil)) return;

    if (_navCompactNotifier.value == compact) return;

    // Hysteresis: prevents tiny bounce / nested scroll notifications from
    // toggling the dock rapidly, which caused the neon selected circle to shake.
    if (!force && _lastNavCompactChangeAt != null) {
      final gap = now.difference(_lastNavCompactChangeAt!).inMilliseconds;
      if (gap < 220) return;
    }

    _lastNavCompactChangeAt = now;
    _navCompactNotifier.value = compact;
  }

  void _expandBottomNavFromUserAction() {
    _navExpandLockUntil = DateTime.now().add(const Duration(milliseconds: 750));
    _setNavCompact(false, force: true);
  }

  bool _handleBottomNavScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      final pixels = notification.metrics.pixels;

      // Scroll down: minimize only after a clear movement.
      if (delta > 8 && pixels > 28) {
        _setNavCompact(true);
      }

      // Scroll up: restore only after a clear upward movement.
      if (delta < -8) {
        _setNavCompact(false);
      }
    }

    if (notification is ScrollEndNotification &&
        notification.metrics.pixels <= 8) {
      _setNavCompact(false, force: true);
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final topInset = MediaQuery.of(context).padding.top;

    return AnimatedBuilder(
      animation: nutriThemeController,
      builder: (context, _) {
        final palette = nutriThemeController.palette;
        final gradientColors = nutriThemeController.isPremiumDark
            ? [palette.topGradient, palette.bg, palette.bottomGradient]
            : const [Color(0xFF2A3A18), Color(0xFF0F140D), Color(0xFF070907)];

        // Match the status bar / notification panel to the green background so
        // there's no separate band at the top. Transparent bar + light icons
        // lets the gradient's top colour show straight through, and setting the
        // Scaffold background to that same top colour fills the area behind the
        // status bar cleanly (the SafeArea inset no longer shows a dark strip).
        final topColor = gradientColors.first;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: palette.bg,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: Scaffold(
            backgroundColor: topColor,
            body: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: gradientColors,
                ),
              ),
              child: SafeArea(
                // Don't inset the top: we want content to scroll up cleanly
                // behind the status bar (Instagram-style), with the gradient
                // filling that area. Each page adds `topInset` of top padding so
                // its content still starts just below the status bar at rest.
                top: false,
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(color: palette.lime),
                      );
                    }
                    final data =
                        snapshot.data!.data() as Map<String, dynamic>? ?? {};

                    return Stack(
                      children: [
                        // Content fills full screen, edge-to-edge.
                        // The PageView slides screen-edge to screen-edge like
                        // Instagram — no horizontal margin travels with the page,
                        // so there's no grey gap on the side mid-swipe. The 24px
                        // content inset is applied per-page inside _buildPageAt
                        // (only for pages built here), so standalone screens stay
                        // full-bleed as designed.
                        Positioned.fill(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _handleBottomNavScroll,
                            child: PageView.builder(
                              controller: _pageController,
                              physics: const BouncingScrollPhysics(),
                              itemCount: 6,
                              clipBehavior: Clip.none,
                              pageSnapping: true,
                              onPageChanged: (i) {
                                // Update the lightweight notifier (nav highlight)
                                // Lightweight: update the nav highlight + index
                                // tracker only. No setState that rebuilds the page,
                                // so swiping stays perfectly smooth. The card
                                // entrance is NOT replayed on swipe — the page is
                                // already on screen from the slide, so replaying it
                                // would just rebuild every card mid-slide and cause
                                // the lag. The dashboard graph seed still bumps, but
                                // without a heavy full rebuild.
                                _selectedIndex = i;
                                _pageIndexNotifier.value = i;
                                _expandBottomNavFromUserAction();
                                _replayScreenTitleAnimation(i);
                                if (i == 0) {
                                  _homeGraphAnimationSeed++;
                                }
                              },
                              itemBuilder: (context, index) =>
                                  _buildPageAt(context, data, index, topInset),
                            ),
                          ),
                        ),

                        // Floating nav — transparent. Rebuilds ONLY itself when
                        // the page index changes (via the notifier), so updating
                        // the highlight never rebuilds the pages behind it.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: RepaintBoundary(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _navCompactNotifier,
                              builder: (context, isCompact, _) {
                                return AnimatedPadding(
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutCubic,
                                  padding: EdgeInsets.only(
                                    bottom: isCompact ? 16 : 24,
                                  ),
                                  child: ValueListenableBuilder<int>(
                                    valueListenable: _pageIndexNotifier,
                                    builder: (context, currentIndex, _) {
                                      return FloatingBottomNav(
                                        currentIndex: currentIndex,
                                        isCompact: isCompact,
                                        onTap: (i) {
                                          // Pressing any bottom button restores the
                                          // full-size dock, just like Instagram.
                                          _expandBottomNavFromUserAction();
                                          _goToPage(i);
                                        },
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Premium movable AI button — available from every tab.
                        // Keep AnimatedPositioned out of the tree when the setting is off.
                        // This prevents a blank/failed rebuild when returning from App Settings.
                        if (_aiFloatingButtonEnabled)
                          _globalAiFloatingButton(context),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _replayScreenTitleAnimation(int index) {
    if (index == 2) {
      healthTitleReplayTrigger.value++;
    } else if (index == 4) {
      communityTitleReplayTrigger.value++;
    }
  }

  /// Navigates the PageView to [i] instantly (no slide). Used by the bottom nav
  /// and the in-content shortcuts. Tab taps always cut straight to the target —
  /// like switching tabs in Instagram/Facebook — so there's never an animation
  /// to stutter. The slide animation is reserved purely for finger swipes.
  void _goToPage(int i) {
    _expandBottomNavFromUserAction();
    if (i == _selectedIndex) return;
    _pageController.jumpToPage(i);
    // Keep the highlight perfectly in step with the tap.
    _selectedIndex = i;
    _pageIndexNotifier.value = i;
    _replayScreenTitleAnimation(i);
    // Replay the card entrance ONLY on tap navigation to the Dashboard, where
    // the page appears fresh. Swipes intentionally skip this — the page is
    // already visible from the slide, so replaying would cause lag.
    if (i == 0) {
      setState(() => _homeEntranceSeed++);
    }
  }

  Widget _buildPageAt(
    BuildContext context,
    Map<String, dynamic> data,
    int index,
    double topInset,
  ) {
    // Horizontal 24px keeps every page aligned like the Nutrition screen.
    // The top inset is the status-bar height plus a small 14px breathing gap,
    // so content begins just below the status bar with the gradient filling
    // the area behind it — no colour band or dead strip at the top. Because
    // SafeArea no longer reserves the top, this is the single source of the
    // top spacing for all six pages.
    final localInset = EdgeInsets.fromLTRB(24, topInset + 14, 24, 0);
    switch (index) {
      case 1:
        return Padding(
          padding: localInset,
          child: _nutritionPage(context, data),
        );
      case 2:
        return Padding(padding: localInset, child: _healthPage);
      case 3:
        return Padding(padding: localInset, child: _activityPage);
      case 4:
        return Padding(padding: localInset, child: _communityPage);
      case 5:
        return Padding(padding: localInset, child: _profilePage(context, data));
      default:
        return Padding(padding: localInset, child: _homePage(context, data));
    }
  }

  // ── HOME PAGE ────────────────────────────────────────────────
  Widget _homePage(BuildContext context, Map<String, dynamic> data) {
    final name = _safeString(data['name'], fallback: 'User');
    final calories = _safeInt(data['targetCalories'], fallback: 505);
    final protein = _safeString(data['proteinGrams'], fallback: '--');
    final carbs = _safeString(data['carbsGrams'], fallback: '--');
    final fats = _safeString(data['fatsGrams'], fallback: '--');
    final goal = _safeString(data['goal'], fallback: 'Fitness Goal');
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return SingleChildScrollView(
      // Key tied to the entrance seed: changing it on each visit rebuilds the
      // staggered items so the cascade replays on open and on swipe.
      key: ValueKey<String>('home-scroll-$_homeEntranceSeed'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StaggeredItem(
            index: 0,
            enabled: !_reduceAnimations,
            child: RepaintBoundary(child: _topHeader(context, name, data)),
          ),
          const SizedBox(height: 22),
          _StaggeredItem(
            index: 1,
            enabled: !_reduceAnimations,
            child: RepaintBoundary(
              child: _todayCaloriesOverviewCard(
                uid: uid,
                targetCalories: calories,
              ),
            ),
          ),
          const SizedBox(height: 22),
          _StaggeredItem(
            index: 2,
            enabled: !_reduceAnimations,
            child: RepaintBoundary(
              child: _UltraSmoothWeeklyCaloriesCard(
                uid: uid,
                targetCalories: calories,
                animationSeed: _homeGraphAnimationSeed,
                graphAnimationEnabled: _graphAnimationEnabled,
                reduceAnimations: _reduceAnimations,
              ),
            ),
          ),
          const SizedBox(height: 22),
          _StaggeredItem(
            index: 3,
            enabled: !_reduceAnimations,
            child: RepaintBoundary(
              child: _UltraSmoothDashboardCalendarCard(
                uid: uid,
                targetCalories: calories,
                todaySteps: _stepView.value.steps,
                waterLiters: _waterLitersView.value,
                formatNumber: _formatNumber,
                dateKey: _dateKey,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _StaggeredItem(
            index: 4,
            enabled: !_reduceAnimations,
            child: RepaintBoundary(child: _stepsCard(context, data)),
          ),
          const SizedBox(height: 24),
          _StaggeredItem(
            index: 5,
            enabled: !_reduceAnimations,
            child: RepaintBoundary(
              child: ValueListenableBuilder<double>(
                valueListenable: _waterLitersView,
                builder: (context, waterLiters, _) {
                  return _waterIntakeCard(
                    waterGoalLiters: _safeDouble(
                      data['waterGoalLiters'],
                      fallback: 3.0,
                    ),
                    currentWaterLiters: waterLiters,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          _StaggeredItem(
            index: 6,
            enabled: !_reduceAnimations,
            child: RepaintBoundary(
              child: Row(
                children: [
                  Expanded(
                    child: _macroCard(
                      'Protein',
                      '$protein g',
                      Icons.fitness_center_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _macroCard('Carbs', '$carbs g', Icons.grain_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _macroCard(
                      'Fats',
                      '$fats g',
                      Icons.water_drop_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _StaggeredItem(
            index: 7,
            enabled: !_reduceAnimations,
            child: Text(
              'Goal: $goal',
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _todayCaloriesOverviewCard({
    required String uid,
    required int targetCalories,
  }) {
    return _UltraSmoothTodayCaloriesCard(
      uid: uid,
      targetCalories: targetCalories,
      dateKey: _dateKey,
      reduceAnimations: _reduceAnimations,
      onTap: () => _goToPage(1),
    );
  }

  Widget _todayCalorieMiniChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.055),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.045)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: lime, size: 13),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '$label $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 10.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _healthCalendarDiaryCard({
    required String uid,
    required int targetCalories,
  }) {
    // Keep this card fully cached while scrolling. Do not listen directly to
    // live step/water notifiers here, because they can repaint this expensive
    // dashboard section while the user scrolls past it.
    return _DashboardCalendarDiaryCard(
      uid: uid,
      targetCalories: targetCalories,
      todaySteps: _todaySteps,
      waterLiters: _waterLiters,
      reduceAnimations: _reduceAnimations,
      formatNumber: _formatNumber,
      safeInt: _safeInt,
      safeDouble: _safeDouble,
      safeString: _safeString,
      dateKey: _dateKey,
    );
  }

  Widget _calendarMiniMetric({
    required String label,
    required String value,
    required IconData icon,
    required bool active,
    required double progress,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.052),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? lime.withOpacity(0.18)
              : Colors.white.withOpacity(0.045),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: active ? lime : soft.withOpacity(0.62),
                size: 16,
              ),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active ? lime : Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _animatedMetricValue(
            value,
            GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: soft.withOpacity(0.66),
              fontSize: 10.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                active ? lime : soft.withOpacity(0.32),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── TOP HEADER with clickable avatar ────────────────────────
  Widget _topHeader(
    BuildContext context,
    String name,
    Map<String, dynamic> data,
  ) {
    final safeName = _safeString(name, fallback: 'User');
    final initials = _initialsFrom(safeName);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            'Hi!,\n$safeName',
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
        GestureDetector(
          onTap: () => _goToPage(5),
          child: RepaintBoundary(
            child: _animatedAvatar(
              data: data,
              initials: initials,
              size: 56,
              fontSize: 18,
              showGlow: true,
            ),
          ),
        ),
      ],
    );
  }

  Stream<int> _todayRunTrackerBurnedCaloriesStream(String uid) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('activities')
        .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startedAt', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((snapshot) {
          var total = 0;
          for (final doc in snapshot.docs) {
            total += _safeInt(doc.data()['caloriesBurned']);
          }
          return total;
        });
  }

  // ── NUTRITION PAGE ───────────────────────────────────────────
  Widget _nutritionPage(BuildContext context, Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    void openFoodLog() {
      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 340),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: const FoodLogScreen(),
          ),
        ),
      ).then((_) => setState(() {}));
    }

    return SingleChildScrollView(
      key: const ValueKey('nutrition'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 118),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Transform.translate(
              offset: Offset(0, 18 * (1 - t)),
              child: Opacity(opacity: t, child: child),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nutrition',
                        style: GoogleFonts.outfit(
                          color: text,
                          fontSize: 36,
                          height: 0.95,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Track today\'s meals and macros',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: soft.withOpacity(0.76),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 0),
                  child: _cleanNutritionAddButton(openFoodLog),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('meals')
                .doc(today)
                .snapshots(),
            builder: (context, snapshot) {
              final totals =
                  snapshot.data?.data() as Map<String, dynamic>? ?? {};
              final cal = (totals['calories'] as num?)?.toInt() ?? 0;
              final prot = (totals['protein'] as num?)?.toDouble() ?? 0.0;
              final carb = (totals['carbs'] as num?)?.toDouble() ?? 0.0;
              final fat = (totals['fat'] as num?)?.toDouble() ?? 0.0;
              final savedBurned = _safeInt(totals['activityBurnedCalories']);
              final targetCal = _safeInt(
                data['targetCalories'],
                fallback: 2000,
              ).clamp(1, 10000);

              return StreamBuilder<int>(
                stream: _todayRunTrackerBurnedCaloriesStream(uid),
                builder: (context, burnedSnap) {
                  final liveBurned = burnedSnap.data ?? 0;
                  final activityBurned = liveBurned > 0
                      ? liveBurned
                      : savedBurned;
                  final netCalories = (cal - activityBurned).clamp(0, 99999);
                  final progress = (netCalories / targetCal).clamp(0.0, 1.0);
                  final remaining = (targetCal - netCalories).clamp(
                    0,
                    targetCal,
                  );

                  return Column(
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 780),
                        curve: Curves.easeOutCubic,
                        builder: (context, animatedProgress, _) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: _premiumBox(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 92,
                                      height: 92,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox.expand(
                                            child: CircularProgressIndicator(
                                              value: animatedProgress,
                                              strokeWidth: 9,
                                              strokeCap: StrokeCap.round,
                                              backgroundColor: Colors.white
                                                  .withOpacity(0.08),
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                    Color
                                                  >(lime),
                                            ),
                                          ),
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                '$netCalories',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.outfit(
                                                  color: text,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w900,
                                                  height: 1,
                                                ),
                                              ),
                                              Text(
                                                'kcal',
                                                style: GoogleFonts.outfit(
                                                  color: soft.withOpacity(0.82),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Daily Calories',
                                            style: GoogleFonts.outfit(
                                              color: text,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.35,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$remaining kcal remaining',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(
                                              color: lime,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: animatedProgress,
                                              minHeight: 7,
                                              backgroundColor: Colors.white
                                                  .withOpacity(0.08),
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                    Color
                                                  >(lime),
                                            ),
                                          ),
                                          const SizedBox(height: 7),
                                          Text(
                                            activityBurned > 0
                                                ? 'Goal: $targetCal kcal • Burned: $activityBurned kcal'
                                                : 'Goal: $targetCal kcal',
                                            style: GoogleFonts.outfit(
                                              color: soft.withOpacity(0.72),
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    _compactMacroTile(
                                      'Protein',
                                      '${prot.toStringAsFixed(0)}g',
                                      Icons.fitness_center_rounded,
                                    ),
                                    const SizedBox(width: 10),
                                    _compactMacroTile(
                                      'Carbs',
                                      '${carb.toStringAsFixed(0)}g',
                                      Icons.grain_rounded,
                                    ),
                                    const SizedBox(width: 10),
                                    _compactMacroTile(
                                      'Fat',
                                      '${fat.toStringAsFixed(0)}g',
                                      Icons.opacity_rounded,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      if (activityBurned > 0) ...[
                        _activityBurnedCaloriesCard(activityBurned),
                        const SizedBox(height: 14),
                      ],
                      _scanOrLogFoodCard(openFoodLog),
                      const SizedBox(height: 16),
                      _nutritionCalendarHistory(
                        uid: uid,
                        openFoodLog: openFoodLog,
                      ),
                      const SizedBox(height: 18),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('meals')
                            .doc(today)
                            .collection('entries')
                            .orderBy('timestamp', descending: true)
                            .snapshots(),
                        builder: (context, entrySnap) {
                          if (!entrySnap.hasData ||
                              entrySnap.data!.docs.isEmpty) {
                            return _emptyMealState(openFoodLog);
                          }

                          final docs = entrySnap.data!.docs;
                          final sugar = docs.fold<double>(0, (sum, doc) {
                            final m = doc.data() as Map<String, dynamic>;
                            return sum + _safeDouble(m['sugar']);
                          });
                          final fibre = docs.fold<double>(0, (sum, doc) {
                            final m = doc.data() as Map<String, dynamic>;
                            return sum + _safeDouble(m['fibre']);
                          });

                          final goal = _safeString(
                            data['goal'],
                            fallback: 'Eat healthy',
                          );
                          final proteinGoal = _safeDouble(
                            data['proteinGoal'],
                            fallback: 120,
                          );
                          final carbsGoal = _safeDouble(
                            data['carbsGoal'],
                            fallback: 250,
                          );
                          final fatGoal = _safeDouble(
                            data['fatGoal'],
                            fallback: 70,
                          );
                          const sugarLimit = 50.0;
                          const fibreGoal = 25.0;
                          final burned = activityBurned;

                          final warnings = <String>[];
                          if (prot < proteinGoal * 0.55) {
                            warnings.add(
                              'Protein is still low. Add eggs, fish, chicken, tofu or dhal.',
                            );
                          }
                          if (sugar > sugarLimit) {
                            warnings.add(
                              'Sugar is high today. Reduce sweet drinks and desserts.',
                            );
                          }
                          if (remaining < 250) {
                            warnings.add(
                              'Calories are almost full. Choose a lighter next meal.',
                            );
                          }
                          if (fibre < 10 && docs.length >= 2) {
                            warnings.add(
                              'Fibre is low. Add vegetables, fruits, oats or beans.',
                            );
                          }

                          final checklist = <String>[
                            docs.isNotEmpty
                                ? '✓ Logged at least one meal'
                                : '○ Logged at least one meal',
                            prot >= proteinGoal * 0.75
                                ? '✓ Hit protein target'
                                : '○ Hit protein target',
                            sugar <= sugarLimit
                                ? '✓ Sugar within limit'
                                : '○ Sugar within limit',
                            fibre >= fibreGoal * 0.6
                                ? '✓ Good fibre intake'
                                : '○ Good fibre intake',
                          ];

                          var score = 45;
                          if (docs.isNotEmpty) score += 12;
                          if (prot >= proteinGoal * 0.75) score += 18;
                          if (cal <= targetCal) score += 12;
                          if (sugar <= sugarLimit) score += 7;
                          if (fibre >= fibreGoal * 0.6) score += 6;
                          score = score.clamp(0, 100);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _calorieBreakdownCard(
                                target: targetCal,
                                eaten: cal,
                                remaining: remaining,
                                burned: burned,
                              ),
                              const SizedBox(height: 16),
                              _aiMealSuggestionCard(
                                protein: prot,
                                proteinGoal: proteinGoal,
                                remaining: remaining,
                                goal: goal,
                              ),
                              const SizedBox(height: 16),
                              _macroProgressCard(
                                protein: prot,
                                carbs: carb,
                                fat: fat,
                                sugar: sugar,
                                fibre: fibre,
                                proteinGoal: proteinGoal,
                                carbsGoal: carbsGoal,
                                fatGoal: fatGoal,
                                sugarLimit: sugarLimit,
                                fibreGoal: fibreGoal,
                              ),
                              const SizedBox(height: 16),
                              _nutritionScoreCard(
                                score: score,
                                checklist: checklist,
                                warnings: warnings,
                              ),
                              const SizedBox(height: 16),
                              _nextBestMealCard(
                                remaining: remaining,
                                protein: prot,
                                proteinGoal: proteinGoal,
                                goal: goal,
                              ),
                              const SizedBox(height: 16),
                              _mealStreakCard(docs.length),
                              const SizedBox(height: 16),
                              _mealTimelineSection(docs),
                              const SizedBox(height: 16),
                              _recentFoodsSection(docs, openFoodLog),
                              const SizedBox(height: 16),
                              _weeklyNutritionChart(
                                uid: uid,
                                targetCalories: targetCal,
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Today\'s Meals',
                                      style: GoogleFonts.outfit(
                                        color: text,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${docs.length} logged',
                                    style: GoogleFonts.outfit(
                                      color: soft.withOpacity(0.72),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...docs.map(
                                (doc) => _mealEntryCard(
                                  doc.data() as Map<String, dynamic>,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _compactMacroTile(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.055)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: lime, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: text,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.72),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanOrLogFoodCard(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Transform.scale(
          scale: 0.96 + (0.04 * t),
          child: Opacity(opacity: t, child: child),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: lime.withOpacity(0.09),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: lime.withOpacity(0.14), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: lime.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: lime,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.black,
                  size: 23,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan or Log Food',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Track every meal with AI, barcode or manual search',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.74),
                        fontSize: 11.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: lime,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyMealState(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: _premiumBox(),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.restaurant_rounded,
                color: lime,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No meals logged yet',
              style: GoogleFonts.outfit(
                color: text,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap here to add your first meal today',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.72),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macroBarItem(String label, String value, String unit, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              '$value$unit',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: soft, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mealEntryCard(Map<String, dynamic> m) {
    final mealType = _safeString(m['mealType'], fallback: 'meal');
    final name = _safeString(m['name'], fallback: 'Unknown');
    final cal = _safeInt(m['calories']);
    final portionG = _safeInt(m['portionG']);
    final method = _safeString(m['method'], fallback: 'manual');

    IconData icon;
    String methodLabel;
    if (method == 'ai_scan') {
      icon = Icons.camera_alt_rounded;
      methodLabel = 'AI Scan';
    } else if (method == 'barcode_scan') {
      icon = Icons.qr_code_scanner_rounded;
      methodLabel = 'Barcode';
    } else {
      icon = Icons.edit_rounded;
      methodLabel = 'Manual';
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 12 * (1 - t)),
        child: Opacity(opacity: t, child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: _premiumBox(),
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.13),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: lime, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: text,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${mealType[0].toUpperCase()}${mealType.substring(1)} • ${portionG}g • $methodLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: soft.withOpacity(0.76),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: lime.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$cal kcal',
                style: GoogleFonts.outfit(
                  color: lime,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityBurnedCaloriesCard(int burnedCalories) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _premiumBox(),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.13),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.directions_run_rounded,
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
                  'Activity Burned',
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Run Tracker calories reduce today’s net calories',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.74),
                    fontSize: 11.6,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$burnedCalories kcal',
            style: GoogleFonts.outfit(
              color: lime,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cleanNutritionAddButton(VoidCallback openFoodLog) {
    return GestureDetector(
      onTap: openFoodLog,
      child: RepaintBoundary(
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: lime,
            borderRadius: BorderRadius.circular(19),
            boxShadow: const [],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.black, size: 28),
        ),
      ),
    );
  }

  Widget _nutritionQuickActions(VoidCallback openFoodLog) {
    final actions = [
      _NutritionAction(
        Icons.camera_alt_rounded,
        'AI Scan',
        'Photo food',
        openFoodLog,
      ),
      _NutritionAction(
        Icons.qr_code_scanner_rounded,
        'Barcode',
        'Packaged food',
        openFoodLog,
      ),
      _NutritionAction(
        Icons.edit_note_rounded,
        'Manual',
        'Search & add',
        openFoodLog,
      ),
    ];

    return Row(
      children: actions.map((a) {
        final isLast = a == actions.last;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 10),
            child: GestureDetector(
              onTap: a.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.055),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: lime.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(a.icon, color: lime, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.68),
                        fontSize: 9.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _calorieBreakdownCard({
    required int target,
    required int eaten,
    required int remaining,
    required int burned,
  }) {
    final adjustedRemaining = (target - eaten + burned).clamp(0, 99999);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _premiumBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.local_fire_department_rounded,
            title: 'Calories Breakdown',
            subtitle: 'Goal, eaten, burned and remaining',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniMetric('Goal', '$target', 'kcal'),
              const SizedBox(width: 10),
              _miniMetric('Eaten', '$eaten', 'kcal'),
              const SizedBox(width: 10),
              _miniMetric('Burned', '$burned', 'kcal'),
              const SizedBox(width: 10),
              _miniMetric(
                'Left',
                '$adjustedRemaining',
                'kcal',
                highlight: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aiMealSuggestionCard({
    required double protein,
    required double proteinGoal,
    required int remaining,
    required String goal,
  }) {
    final proteinLeft = (proteinGoal - protein).clamp(0, 999).round();
    String title;
    String advice;
    IconData icon;

    if (proteinLeft > 25) {
      title = 'Protein is low';
      advice =
          'Try eggs, chicken breast, tuna, tofu, dhal, tempeh or Greek yogurt today.';
      icon = Icons.fitness_center_rounded;
    } else if (remaining < 350) {
      title = 'Calories almost full';
      advice =
          'Choose a lighter meal next, such as soup, fruit, eggs or grilled protein.';
      icon = Icons.warning_amber_rounded;
    } else if (goal.toLowerCase().contains('muscle')) {
      title = 'Muscle gain tip';
      advice =
          'Your next meal should include lean protein and slow carbs for recovery.';
      icon = Icons.bolt_rounded;
    } else {
      title = 'Balanced choice';
      advice =
          'Add vegetables and a clean protein source to improve today’s nutrition score.';
      icon = Icons.auto_awesome_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: lime.withOpacity(0.09),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: lime.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: lime,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(icon, color: Colors.black, size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Suggestion • $title',
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  advice,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.82),
                    fontSize: 12.3,
                    height: 1.32,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _macroProgressCard({
    required double protein,
    required double carbs,
    required double fat,
    required double sugar,
    required double fibre,
    required double proteinGoal,
    required double carbsGoal,
    required double fatGoal,
    required double sugarLimit,
    required double fibreGoal,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _premiumBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.donut_large_rounded,
            title: 'Macro Progress',
            subtitle: 'Protein, carbs, fat, sugar and fibre',
          ),
          const SizedBox(height: 16),
          _nutritionProgressLine(
            'Protein',
            protein,
            proteinGoal,
            'g',
            Icons.fitness_center_rounded,
          ),
          const SizedBox(height: 12),
          _nutritionProgressLine(
            'Carbs',
            carbs,
            carbsGoal,
            'g',
            Icons.grain_rounded,
          ),
          const SizedBox(height: 12),
          _nutritionProgressLine(
            'Fat',
            fat,
            fatGoal,
            'g',
            Icons.opacity_rounded,
          ),
          const SizedBox(height: 12),
          _nutritionProgressLine(
            'Sugar',
            sugar,
            sugarLimit,
            'g',
            Icons.cookie_rounded,
            warnWhenHigh: true,
          ),
          const SizedBox(height: 12),
          _nutritionProgressLine(
            'Fibre',
            fibre,
            fibreGoal,
            'g',
            Icons.eco_rounded,
          ),
        ],
      ),
    );
  }

  Widget _nutritionProgressLine(
    String label,
    double value,
    double goal,
    String unit,
    IconData icon, {
    bool warnWhenHigh = false,
  }) {
    final safeGoal = goal <= 0 ? 1.0 : goal;
    final progress = (value / safeGoal).clamp(0.0, 1.0);
    final isWarning = warnWhenHigh && value > goal;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: (isWarning ? Colors.orangeAccent : lime).withOpacity(0.13),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: isWarning ? Colors.orangeAccent : lime,
            size: 18,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${value.toStringAsFixed(0)} / ${goal.toStringAsFixed(0)}$unit',
                    style: GoogleFonts.outfit(
                      color: isWarning ? Colors.orangeAccent : soft,
                      fontSize: 11.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: Colors.white.withOpacity(0.075),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isWarning ? Colors.orangeAccent : lime,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nutritionScoreCard({
    required int score,
    required List<String> checklist,
    required List<String> warnings,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _premiumBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.verified_rounded,
            title: 'Nutrition Score',
            subtitle: '$score / 100 daily balance',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (score / 100).clamp(0.0, 1.0),
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(lime),
                      ),
                    ),
                    Text(
                      '$score',
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: checklist.take(4).map((item) {
                    final done = item.startsWith('✓');
                    final label = item
                        .replaceFirst('✓ ', '')
                        .replaceFirst('○ ', '');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        children: [
                          Icon(
                            done
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: done ? lime : soft.withOpacity(0.55),
                            size: 17,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: done ? text : soft.withOpacity(0.78),
                                fontSize: 11.8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...warnings.take(2).map((warning) => _smartWarningChip(warning)),
          ],
        ],
      ),
    );
  }

  Widget _smartWarningChip(String warning) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.tips_and_updates_rounded,
            color: Colors.orangeAccent,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warning,
              style: GoogleFonts.outfit(
                color: text,
                fontSize: 11.8,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mealTimelineSection(List<QueryDocumentSnapshot> docs) {
    final mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final type in mealTypes) {
      grouped[type] = [];
    }

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final type = _safeString(
        data['mealType'],
        fallback: 'snack',
      ).toLowerCase();
      grouped.putIfAbsent(type, () => []);
      grouped[type]!.add(data);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _premiumBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.timeline_rounded,
            title: 'Today’s Meal Timeline',
            subtitle: 'Breakfast, lunch, dinner and snacks',
          ),
          const SizedBox(height: 14),
          ...mealTypes.map((type) {
            final meals = grouped[type] ?? [];
            return _timelineMealGroup(type, meals);
          }),
        ],
      ),
    );
  }

  Widget _timelineMealGroup(String type, List<Map<String, dynamic>> meals) {
    final totalCal = meals.fold<int>(
      0,
      (sum, m) => sum + _safeInt(m['calories']),
    );
    IconData icon;
    if (type == 'breakfast') {
      icon = Icons.wb_sunny_rounded;
    } else if (type == 'lunch') {
      icon = Icons.restaurant_rounded;
    } else if (type == 'dinner') {
      icon = Icons.nights_stay_rounded;
    } else {
      icon = Icons.cookie_rounded;
    }

    final display = '${type[0].toUpperCase()}${type.substring(1)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, color: lime, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              meals.isEmpty
                  ? '$display not logged'
                  : '$display • ${meals.length} item${meals.length == 1 ? '' : 's'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: meals.isEmpty ? soft.withOpacity(0.72) : text,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${totalCal} kcal',
            style: GoogleFonts.outfit(
              color: meals.isEmpty ? soft.withOpacity(0.55) : lime,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentFoodsSection(
    List<QueryDocumentSnapshot> docs,
    VoidCallback onTap,
  ) {
    final names = <String>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final name = _safeString(data['name']);
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
      if (names.length >= 8) break;
    }

    final fallback = ['Nasi Lemak', 'Chicken Rice', 'Roti Canai', 'Eggs'];
    final foods = names.isEmpty ? fallback : names;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _premiumBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.history_rounded,
            title: 'Recent & Favourite Foods',
            subtitle: 'Quick add your common meals',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: foods.map((food) {
              return GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: lime.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: lime.withOpacity(0.18)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, color: lime, size: 15),
                      const SizedBox(width: 5),
                      Text(
                        food,
                        style: GoogleFonts.outfit(
                          color: text,
                          fontSize: 11.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _weeklyNutritionChart({
    required String uid,
    required int targetCalories,
  }) {
    final today = DateTime.now();
    final keys = List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return _dateKey(d);
    });

    return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
      future: Future.wait(
        keys.map((key) {
          return FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('meals')
              .doc(key)
              .get();
        }),
      ),
      builder: (context, snap) {
        final docs = snap.data ?? [];
        final values = docs.map((d) {
          final data = d.data() ?? {};
          return _safeInt(data['calories']);
        }).toList();

        final maxValue = [
          targetCalories,
          ...values,
        ].fold<int>(1, (a, b) => a > b ? a : b);
        final avgCal = values.isEmpty
            ? 0
            : (values.fold<int>(0, (a, b) => a + b) / values.length).round();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: _premiumBox(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                icon: Icons.bar_chart_rounded,
                title: 'Weekly Calories',
                subtitle: 'Average $avgCal kcal/day',
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 118,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (i) {
                    final value = i < values.length ? values[i] : 0;
                    final height = (value / maxValue).clamp(0.08, 1.0) * 88;
                    final d = today.subtract(Duration(days: 6 - i));
                    final label = [
                      'M',
                      'T',
                      'W',
                      'T',
                      'F',
                      'S',
                      'S',
                    ][d.weekday - 1];

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 420),
                              curve: Curves.easeOutCubic,
                              height: height,
                              decoration: BoxDecoration(
                                color: value >= targetCalories
                                    ? Colors.orangeAccent
                                    : lime,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              label,
                              style: GoogleFonts.outfit(
                                color: soft,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _nextBestMealCard({
    required int remaining,
    required double protein,
    required double proteinGoal,
    required String goal,
  }) {
    String meal;
    String reason;
    IconData icon;

    if ((proteinGoal - protein) > 30) {
      meal = 'Chicken rice + extra egg';
      reason = 'Higher protein option for today';
      icon = Icons.egg_alt_rounded;
    } else if (remaining < 450) {
      meal = 'Mee hoon soup';
      reason = 'Light meal with controlled calories';
      icon = Icons.ramen_dining_rounded;
    } else if (goal.toLowerCase().contains('weight')) {
      meal = 'Grilled fish + vegetables';
      reason = 'Good for calorie control';
      icon = Icons.set_meal_rounded;
    } else {
      meal = 'Nasi campur with fish';
      reason = 'Balanced carbs, protein and fats';
      icon = Icons.restaurant_menu_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _premiumBox(),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.13),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: lime, size: 25),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next Best Meal',
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  meal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.76),
                    fontSize: 11.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mealStreakCard(int loggedCount) {
    final streak = loggedCount > 0 ? 1 : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _premiumBox(),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.13),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: lime,
              size: 27,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Meal Logging Streak',
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  streak > 0
                      ? 'You logged meals today. Keep the streak alive.'
                      : 'Log your first meal today to start a streak.',
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.76),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${streak}d',
            style: GoogleFonts.outfit(
              color: lime,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, color: lime, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: text,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.72),
                  fontSize: 11.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniMetric(
    String label,
    String value,
    String unit, {
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: highlight
              ? lime.withOpacity(0.12)
              : Colors.white.withOpacity(0.045),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: highlight
                ? lime.withOpacity(0.22)
                : Colors.white.withOpacity(0.05),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: highlight ? lime : text,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              unit,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.72),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.75),
                fontSize: 10.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _nutritionCalendarHistory({
    required String uid,
    required VoidCallback openFoodLog,
  }) {
    final today = DateTime.now();
    final days = List.generate(14, (i) {
      return DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: 13 - i));
    });

    final selectedKey = _dateKey(_selectedNutritionDate);
    final isToday = _isSameDay(_selectedNutritionDate, today);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _premiumBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.calendar_month_rounded,
            title: 'Nutrition Calendar',
            subtitle: isToday
                ? 'Viewing today’s food log'
                : 'Viewing ${_shortDate(_selectedNutritionDate)} food log',
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final d = days[index];
                final selected = _isSameDay(d, _selectedNutritionDate);
                final dayKey = _dateKey(d);

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('meals')
                      .doc(dayKey)
                      .snapshots(),
                  builder: (context, snap) {
                    final data = snap.data?.data() ?? {};
                    final calories = _safeInt(data['calories']);
                    final hasData = calories > 0;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedNutritionDate = d;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: 58,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? lime
                              : Colors.white.withOpacity(
                                  hasData ? 0.075 : 0.045,
                                ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? lime
                                : hasData
                                ? lime.withOpacity(0.22)
                                : Colors.white.withOpacity(0.05),
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: lime.withOpacity(0.18),
                                    blurRadius: 16,
                                    spreadRadius: -4,
                                    offset: const Offset(0, 6),
                                  ),
                                ]
                              : [],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _weekdayShort(d),
                              style: GoogleFonts.outfit(
                                color: selected ? Colors.black : soft,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${d.day}',
                              style: GoogleFonts.outfit(
                                color: selected ? Colors.black : text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.black
                                    : hasData
                                    ? lime
                                    : Colors.white.withOpacity(0.18),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _selectedNutritionDaySummary(
            uid: uid,
            dateKey: selectedKey,
            isToday: isToday,
            openFoodLog: openFoodLog,
          ),
        ],
      ),
    );
  }

  Widget _selectedNutritionDaySummary({
    required String uid,
    required String dateKey,
    required bool isToday,
    required VoidCallback openFoodLog,
  }) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('meals')
          .doc(dateKey)
          .snapshots(),
      builder: (context, daySnap) {
        final day = daySnap.data?.data() ?? {};
        final calories = _safeInt(day['calories']);
        final protein = _safeDouble(day['protein']);
        final carbs = _safeDouble(day['carbs']);
        final fat = _safeDouble(day['fat']);
        final sugar = _safeDouble(day['sugar']);

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('meals')
              .doc(dateKey)
              .collection('entries')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, entriesSnap) {
            final entries = entriesSnap.data?.docs ?? [];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.045),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.055)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _historyMetric('Calories', '$calories', 'kcal'),
                          const SizedBox(width: 10),
                          _historyMetric(
                            'Protein',
                            protein.toStringAsFixed(0),
                            'g',
                          ),
                          const SizedBox(width: 10),
                          _historyMetric(
                            'Carbs',
                            carbs.toStringAsFixed(0),
                            'g',
                          ),
                          const SizedBox(width: 10),
                          _historyMetric('Fat', fat.toStringAsFixed(0), 'g'),
                        ],
                      ),
                      if (sugar > 0) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.cookie_rounded,
                              color: lime,
                              size: 17,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Sugar ${sugar.toStringAsFixed(0)}g',
                              style: GoogleFonts.outfit(
                                color: soft,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isToday ? 'Today’s logged foods' : 'Logged foods',
                        style: GoogleFonts.outfit(
                          color: text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${entries.length} item${entries.length == 1 ? '' : 's'}',
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.72),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (entries.isEmpty)
                  _emptyNutritionHistory(openFoodLog, isToday)
                else
                  ...entries.take(5).map((doc) {
                    return _historyFoodTile(doc.data() as Map<String, dynamic>);
                  }),
                if (entries.length > 5) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '+${entries.length - 5} more foods logged',
                      style: GoogleFonts.outfit(
                        color: lime,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _historyMetric(String label, String value, String unit) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: GoogleFonts.outfit(
              color: soft.withOpacity(0.68),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: soft.withOpacity(0.72),
              fontSize: 10.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyFoodTile(Map<String, dynamic> data) {
    final name = _safeString(data['name'], fallback: 'Food');
    final mealType = _safeString(data['mealType'], fallback: 'Meal');
    final calories = _safeInt(data['calories']);
    final protein = _safeDouble(data['protein']);
    final method = _safeString(data['method'], fallback: 'manual');
    final time = _formatFoodTime(data['timestamp']);

    IconData icon;
    if (method.contains('ai')) {
      icon = Icons.camera_alt_rounded;
    } else if (method.contains('barcode')) {
      icon = Icons.qr_code_scanner_rounded;
    } else {
      icon = Icons.edit_note_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: lime, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_capitalize(mealType)} • $time • ${protein.toStringAsFixed(0)}g protein',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.72),
                    fontSize: 10.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$calories kcal',
            style: GoogleFonts.outfit(
              color: lime,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyNutritionHistory(VoidCallback openFoodLog, bool isToday) {
    return GestureDetector(
      onTap: isToday ? openFoodLog : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.no_food_rounded,
              color: soft.withOpacity(0.70),
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              isToday ? 'No food logged yet' : 'No food was logged on this day',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: text,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (isToday) ...[
              const SizedBox(height: 4),
              Text(
                'Tap here to add your first meal today',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.70),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _weekdayShort(DateTime d) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[d.weekday - 1];
  }

  String _shortDate(DateTime d) {
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
    return '${d.day} ${months[d.month - 1]}';
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  String _formatFoodTime(dynamic timestamp) {
    DateTime? dt;

    if (timestamp is Timestamp) {
      dt = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dt = timestamp;
    }

    if (dt == null) return '--:--';

    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    return '$h12:$minute $period';
  }

  // ── PROFILE PAGE ─────────────────────────────────────────────
  Widget _profilePage(BuildContext context, Map<String, dynamic> data) {
    final name = data['name'] ?? 'User';
    final safeName = _safeString(name, fallback: 'User');
    final initials = _initialsFrom(safeName);

    return SingleChildScrollView(
      key: const ValueKey('profile'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 18 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Profile',
                    style: GoogleFonts.outfit(
                      color: text,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showEditProfile(context, data),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: lime.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, color: lime, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Edit',
                          style: GoogleFonts.outfit(
                            color: lime,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 680),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.88 + (0.12 * value),
                child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
              );
            },
            child: Center(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  GestureDetector(
                    onTap: () => _pickProfilePhoto(context),
                    child: _animatedAvatar(
                      data: data,
                      initials: initials,
                      size: 106,
                      fontSize: 34,
                      showGlow: true,
                    ),
                  ),
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: GestureDetector(
                      onTap: () => _pickProfilePhoto(context),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: lime,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF0F140D),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: lime.withOpacity(0.32),
                              blurRadius: 16,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.black,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              name,
              style: GoogleFonts.outfit(
                color: text,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Center(
            child: Text(
              _safeString(data['email']),
              style: GoogleFonts.outfit(color: soft, fontSize: 13),
            ),
          ),
          const SizedBox(height: 5),
          Center(
            child: Text(
              'Tap photo to change',
              style: GoogleFonts.outfit(
                color: lime.withOpacity(0.68),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 28),

          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 720),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 24 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: _premiumBox(),
              child: Column(
                children: [
                  _profileRow('Goal', _safeString(data['goal'], fallback: '-')),
                  _profileRow(
                    'Height',
                    '${_safeString(data['heightCm'], fallback: '--')} cm',
                  ),
                  _profileRow(
                    'Weight',
                    '${_safeString(data['weightKg'], fallback: '--')} kg',
                  ),
                  _profileRow(
                    'Workouts',
                    '${_safeString(data['workoutsPerWeek'], fallback: '--')} / week',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          GestureDetector(
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 360),
                reverseTransitionDuration: const Duration(milliseconds: 260),
                pageBuilder: (_, animation, __) => FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                  child: const ProgressScreen(),
                ),
              ),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: _premiumBox(),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: lime,
                      size: 23,
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
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'XP, streaks, badges and missions',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: lime,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          GestureDetector(
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 360),
                reverseTransitionDuration: const Duration(milliseconds: 260),
                pageBuilder: (_, animation, __) => FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                  child: const DailyReportDetailScreen(),
                ),
              ),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: _premiumBox(),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.insert_chart_rounded,
                      color: lime,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Report',
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Today’s calories, activity, health and PDF export',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: lime,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          GestureDetector(
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder(
                transitionDuration: _reduceAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 360),
                reverseTransitionDuration: _reduceAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                pageBuilder: (_, animation, __) => FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                  child: const AppSettingsScreen(),
                ),
              ),
            ).then((_) => _loadDashboardSettings()),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: _premiumBox(),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.settings_rounded,
                      color: lime,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'App Settings',
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Notifications, goals, AI coach, privacy and data',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: lime,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton(
              onPressed: () => _logout(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.08),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text(
                'Logout',
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
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
          style: GoogleFonts.outfit(
            color: text,
            fontSize: 36,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: GoogleFonts.outfit(color: soft, fontSize: 15, height: 1.45),
        ),
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
                style: GoogleFonts.outfit(
                  color: text,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: GoogleFonts.outfit(color: soft, fontSize: 14.5),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: lime,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
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

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _dayLabel(DateTime date) {
    const days = ['Mon', 'Tues', 'Wed', 'Thurs', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  Widget _weeklyCalorieGraph({
    required String uid,
    required int targetCalories,
    required int animationSeed,
  }) {
    final today = DateTime.now();
    final startDate = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 6));
    final weekKeys = List<String>.generate(
      7,
      (i) => _dateKey(startDate.add(Duration(days: i))),
    );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('meals')
          .where(FieldPath.documentId, whereIn: weekKeys)
          .snapshots(),
      builder: (context, snapshot) {
        final totalsByDate = <String, double>{
          for (final key in weekKeys) key: 0.0,
        };

        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            totalsByDate[doc.id] = _safeDouble(doc.data()['calories']);
          }
        }

        final points = List<_DailyCalories>.generate(7, (i) {
          final date = startDate.add(Duration(days: i));
          final key = _dateKey(date);
          return _DailyCalories(
            dateKey: key,
            label: _dayLabel(date),
            calories: totalsByDate[key] ?? 0.0,
            isToday: key == _dateKey(today),
          );
        });

        final nonZero = points.where((p) => p.calories > 0).toList();
        final todayCalories = points.last.calories.toInt();
        final avgCalories = nonZero.isEmpty
            ? 0
            : (nonZero.fold<double>(0, (sum, p) => sum + p.calories) /
                      nonZero.length)
                  .round();
        final highestCalories = points
            .fold<double>(
              0,
              (maxValue, p) => p.calories > maxValue ? p.calories : maxValue,
            )
            .round();

        final onTargetDays = points.where((p) {
          if (p.calories <= 0) return false;
          final diff = (p.calories - targetCalories).abs();
          return diff <= 250;
        }).length;

        final highestScale =
            [
              targetCalories.toDouble(),
              ...points.map((p) => p.calories),
            ].fold<double>(1, (maxValue, v) => v > maxValue ? v : maxValue) *
            1.16;

        final signature = points
            .map((p) => '${p.dateKey}:${p.calories.toInt()}')
            .join('|');

        final shouldAnimate =
            _graphAnimationEnabled &&
            !_reduceAnimations &&
            (_weeklyGraphSignature != signature ||
                !_weeklyGraphAnimatedOnce ||
                animationSeed > 0);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_weeklyGraphSignature == signature && _weeklyGraphAnimatedOnce) {
            return;
          }
          _weeklyGraphSignature = signature;
          _weeklyGraphAnimatedOnce = true;
        });

        return RepaintBoundary(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: card.withOpacity(0.92),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(0.055)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: lime.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: lime.withOpacity(0.16)),
                      ),
                      child: const Icon(
                        Icons.show_chart_rounded,
                        color: lime,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Weekly Calories',
                            style: GoogleFonts.outfit(
                              color: text,
                              fontSize: 21,
                              height: 1.0,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.45,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Food log trend',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: soft.withOpacity(0.72),
                              fontSize: 11.8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    RepaintBoundary(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: Container(
                          key: ValueKey(todayCalories),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: lime,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: lime.withOpacity(0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Text(
                            '$todayCalories kcal',
                            style: GoogleFonts.outfit(
                              color: Colors.black,
                              fontSize: 12.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _graphDetailPill(
                      icon: Icons.stacked_line_chart_rounded,
                      label: 'Average',
                      value: '$avgCalories',
                      unit: 'kcal/day',
                    ),
                    const SizedBox(width: 9),
                    _graphDetailPill(
                      icon: Icons.arrow_upward_rounded,
                      label: 'Highest',
                      value: '$highestCalories',
                      unit: 'kcal',
                    ),
                    const SizedBox(width: 9),
                    _graphDetailPill(
                      icon: Icons.flag_rounded,
                      label: 'On track',
                      value: '$onTargetDays',
                      unit: 'days',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  height: 210,
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10160E).withOpacity(0.78),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white.withOpacity(0.045)),
                    // gradient removed for smoother scrolling over graph
                  ),
                  child: _InteractiveCaloriesGraph(
                    key: ValueKey('weekly-graph-$animationSeed-$signature'),
                    points: points,
                    maxCalories: highestScale <= 0 ? 1 : highestScale,
                    targetCalories: targetCalories.toDouble(),
                    shouldAnimate: shouldAnimate,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _legendDot(lime, 'Target'),
                    const SizedBox(width: 14),
                    _legendDot(Colors.white, 'Calories'),
                    const Spacer(),
                    Text(
                      '7-day trend',
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.55),
                        fontSize: 10.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _graphDetailPill({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.045)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: lime, size: 18),
            const SizedBox(height: 9),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: text,
                fontSize: 16,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              unit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.72),
                fontSize: 9.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.62),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _animatedMetricValue(String value, TextStyle style) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9.-]'), '');
    final number = double.tryParse(cleaned);

    if (number == null) {
      return Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return _DashboardNumberTicker(value: number, style: style, maxLines: 1);
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: color == lime
                ? [BoxShadow(color: lime.withOpacity(0.35), blurRadius: 8)]
                : [],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: soft.withOpacity(0.68),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _stepsCard(BuildContext context, Map<String, dynamic> data) {
    final stepGoal = _safeInt(
      data['stepGoal'],
      fallback: 8000,
    ).clamp(1000, 50000);

    return ValueListenableBuilder<_StepViewState>(
      valueListenable: _stepView,
      builder: (context, stepState, _) {
        final progress = (stepState.steps / stepGoal).clamp(0.0, 1.0);
        final remaining = (stepGoal - stepState.steps).clamp(0, stepGoal);

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: progress),
          duration: _reduceAnimations
              ? Duration.zero
              : const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          builder: (context, animatedProgress, _) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: _premiumBox(),
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
                              'Steps Today',
                              style: GoogleFonts.outfit(
                                color: text,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              stepState.usingDemo
                                  ? 'Fallback mode'
                                  : 'Live from phone step sensor',
                              style: GoogleFonts.outfit(
                                color: soft.withOpacity(0.72),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _loadTodaySteps,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: stepState.isLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        color: lime,
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.refresh_rounded,
                                      color: lime,
                                      size: 22,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => _showEditStepGoal(context, data),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: lime,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                color: Colors.black,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 106,
                        height: 106,
                        child: Stack(
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: animatedProgress,
                                strokeWidth: 10,
                                backgroundColor: Colors.white.withOpacity(0.08),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  lime,
                                ),
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Center(
                              child: Icon(
                                Icons.directions_walk_rounded,
                                color: lime,
                                size: 34,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatNumber(stepState.steps),
                              style: GoogleFonts.outfit(
                                color: text,
                                fontSize: 34,
                                height: 0.95,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'steps completed',
                              style: GoogleFonts.outfit(
                                color: soft,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${_formatNumber(remaining)} left • Goal ${_formatNumber(stepGoal)} • ${stepState.sourceLabel}',
                              style: GoogleFonts.outfit(
                                color: lime,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (stepState.error != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                stepState.error!,
                                style: GoogleFonts.outfit(
                                  color: Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: animatedProgress,
                      minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(lime),
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

  Widget _waterIntakeCard({
    required double waterGoalLiters,
    required double currentWaterLiters,
  }) {
    final safeWaterGoal = waterGoalLiters <= 0 ? 3.0 : waterGoalLiters;
    final displayWater = currentWaterLiters
        .clamp(0.0, safeWaterGoal)
        .toDouble();
    final waterProgress = (displayWater / safeWaterGoal)
        .clamp(0.0, 1.0)
        .toDouble();
    final totalWaterBoxes = (safeWaterGoal * 2).round().clamp(1, 20).toInt();
    final filledWaterBoxes = (displayWater * 2)
        .round()
        .clamp(0, totalWaterBoxes)
        .toInt();
    final waterGoalLabel = safeWaterGoal % 1 == 0
        ? safeWaterGoal.toStringAsFixed(0)
        : safeWaterGoal.toStringAsFixed(1);
    final waterValueLabel = displayWater % 1 == 0
        ? displayWater.toStringAsFixed(0)
        : displayWater.toStringAsFixed(1);

    // Fix old saved values like 5L when the user's goal is only 3L.
    if (currentWaterLiters > safeWaterGoal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _waterLiters = safeWaterGoal;
        _waterLitersView.value = safeWaterGoal;
      });
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: waterProgress),
      duration: _reduceAnimations
          ? Duration.zero
          : const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, animatedProgress, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: _premiumBox(),
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
                          'Water Intake',
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Daily target: $waterGoalLabel liters • 1 box = 0.5L',
                          style: GoogleFonts.outfit(
                            color: soft.withOpacity(0.75),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedScale(
                    scale: displayWater >= safeWaterGoal ? 1.08 : 1.0,
                    duration: _reduceAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: lime.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: lime.withOpacity(0.22)),
                      ),
                      child: AnimatedSwitcher(
                        duration: _reduceAnimations
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        child: Text(
                          '$waterValueLabel/$waterGoalLabel L',
                          key: ValueKey('$waterValueLabel-$waterGoalLabel'),
                          style: GoogleFonts.outfit(
                            color: lime,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: List.generate(totalWaterBoxes, (i) {
                    final filled = i < filledWaterBoxes;
                    final boxLiters = ((i + 1) * 0.5)
                        .clamp(0.0, safeWaterGoal)
                        .toDouble();
                    final boxLabel = boxLiters % 1 == 0
                        ? boxLiters.toStringAsFixed(0)
                        : boxLiters.toStringAsFixed(1);

                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => _updateWaterIntake(
                          boxLiters,
                          waterGoal: safeWaterGoal,
                        ),
                        child: AnimatedScale(
                          // Clean style: no glowing scale jump around water boxes.
                          scale: filled ? 1.0 : 0.98,
                          duration: _reduceAnimations
                              ? Duration.zero
                              : Duration(milliseconds: 150 + (i * 14)),
                          curve: Curves.easeOutCubic,
                          child: AnimatedContainer(
                            duration: _reduceAnimations
                                ? Duration.zero
                                : const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            width: 38,
                            height: 52,
                            decoration: BoxDecoration(
                              color: filled
                                  ? lime.withOpacity(0.92)
                                  : Colors.white.withOpacity(0.025),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: filled
                                    ? Colors.transparent
                                    : Colors.white.withOpacity(0.16),
                                width: 1.0,
                              ),
                              // Removed glow shadow to keep the box outline clean.
                              boxShadow: const [],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  filled
                                      ? Icons.water_drop_rounded
                                      : Icons.add_rounded,
                                  color: filled
                                      ? Colors.black
                                      : soft.withOpacity(0.6),
                                  size: 18,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${boxLabel}L',
                                  style: GoogleFonts.outfit(
                                    color: filled
                                        ? Colors.black.withOpacity(0.72)
                                        : soft.withOpacity(0.58),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: animatedProgress,
                  minHeight: 6,
                  backgroundColor: soft.withOpacity(0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(lime),
                ),
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 5,
                  activeTrackColor: lime,
                  inactiveTrackColor: soft.withOpacity(0.15),
                  thumbColor: lime,
                  overlayColor: lime.withOpacity(0.18),
                  valueIndicatorColor: lime,
                  valueIndicatorTextStyle: GoogleFonts.outfit(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                  ),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                ),
                child: Slider(
                  min: 0,
                  max: safeWaterGoal,
                  divisions: (safeWaterGoal * 2).round().clamp(1, 20).toInt(),
                  value: displayWater,
                  label: '$waterValueLabel L',
                  onChanged: (v) =>
                      _updateWaterIntake(v, waterGoal: safeWaterGoal),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AnimatedSwitcher(
                    duration: _reduceAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    child: Text(
                      '$waterValueLabel L completed',
                      key: ValueKey('water-completed-$waterValueLabel'),
                      style: GoogleFonts.outfit(
                        color: lime,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '$waterGoalLabel L target',
                    style: GoogleFonts.outfit(
                      color: soft.withOpacity(0.65),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _timelineDot({required bool active}) {
    return Container(
      width: active ? 42 : 11,
      height: active ? 42 : 11,
      decoration: BoxDecoration(
        color: active ? lime : soft.withOpacity(0.7),
        shape: BoxShape.circle,
      ),
      child: active
          ? const Center(
              child: CircleAvatar(
                radius: 5,
                backgroundColor: Color(0xFF171D13),
              ),
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

  Widget _profileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(label, style: GoogleFonts.outfit(color: soft, fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.outfit(color: text, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  BoxDecoration _premiumBox() {
    return BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withOpacity(0.05)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.35),
          blurRadius: 12,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }
}

class _UltraSmoothTodayCaloriesCard extends StatefulWidget {
  const _UltraSmoothTodayCaloriesCard({
    required this.uid,
    required this.targetCalories,
    required this.dateKey,
    required this.reduceAnimations,
    required this.onTap,
  });

  final String uid;
  final int targetCalories;
  final String Function(DateTime date) dateKey;
  final bool reduceAnimations;
  final VoidCallback onTap;

  @override
  State<_UltraSmoothTodayCaloriesCard> createState() =>
      _UltraSmoothTodayCaloriesCardState();
}

class _UltraSmoothTodayCaloriesCardState
    extends State<_UltraSmoothTodayCaloriesCard>
    with AutomaticKeepAliveClientMixin {
  int _eaten = 0;
  int _burned = 0;
  bool _loading = true;
  String? _loadedKey;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _todayMealSub;

  static const Color lime = Color(0xFFD6FF60);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _startTodayCaloriesListener();
  }

  @override
  void didUpdateWidget(covariant _UltraSmoothTodayCaloriesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.targetCalories != widget.targetCalories) {
      _startTodayCaloriesListener();
    }
  }

  @override
  void dispose() {
    _todayMealSub?.cancel();
    super.dispose();
  }

  int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _startTodayCaloriesListener() {
    final today = widget.dateKey(DateTime.now());
    _loadedKey = today;
    _todayMealSub?.cancel();

    if (!_loading && mounted) {
      setState(() => _loading = true);
    }

    _todayMealSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('meals')
        .doc(today)
        .snapshots()
        .listen(
          (doc) {
            if (!mounted || _loadedKey != today) return;

            final totals = doc.data() ?? <String, dynamic>{};
            setState(() {
              _eaten = _safeInt(totals['calories']);
              _burned = _safeInt(totals['activityBurnedCalories']);
              _loading = false;
            });
          },
          onError: (_) {
            if (!mounted || _loadedKey != today) return;
            setState(() => _loading = false);
          },
        );
  }

  String _formatNumber(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final safeTarget = widget.targetCalories <= 0
        ? 2000
        : widget.targetCalories;
    final netCalories = (_eaten - _burned).clamp(0, 99999).toInt();
    final remaining = (safeTarget - netCalories).clamp(0, safeTarget).toInt();
    final progress = (netCalories / safeTarget).clamp(0.0, 1.0).toDouble();
    final overLimit = netCalories > safeTarget;
    final progressColor = overLimit ? Colors.orangeAccent : lime;

    // This card is intentionally static: no TweenAnimationBuilder, no
    // CircularProgressIndicator, no animated number ticker. That keeps it
    // cheap to paint while scrolling on real Android devices.
    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: card.withOpacity(0.96),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.055)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              _StaticCaloriesRing(progress: progress, color: progressColor),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Calories",
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 19,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatNumber(netCalories),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 27,
                            height: 0.95,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 5, bottom: 2),
                          child: Text(
                            'kcal',
                            style: GoogleFonts.outfit(
                              color: soft.withOpacity(0.74),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _loading
                          ? 'Checking food log'
                          : overLimit
                          ? 'Over daily goal'
                          : '${_formatNumber(remaining)} kcal left today',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: GoogleFonts.outfit(
                        color: progressColor,
                        fontSize: 12.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _StaticLinearProgress(
                      value: progress,
                      color: progressColor,
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

class _StaticLinearProgress extends StatelessWidget {
  const _StaticLinearProgress({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withOpacity(0.08)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: safeValue,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaticCaloriesRing extends StatelessWidget {
  const _StaticCaloriesRing({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: CustomPaint(
        painter: _StaticCaloriesRingPainter(progress: progress, color: color),
        child: Center(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.14),
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              color: color,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticCaloriesRingPainter extends CustomPainter {
  const _StaticCaloriesRingPainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 8) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final safeProgress = progress.clamp(0.0, 1.0).toDouble();

    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    final foregroundPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);
    canvas.drawArc(
      rect,
      -1.5708,
      6.28318 * safeProgress,
      false,
      foregroundPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _StaticCaloriesRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _DailyCalories {
  const _DailyCalories({
    required this.dateKey,
    required this.label,
    required this.calories,
    required this.isToday,
  });

  final String dateKey;
  final String label;
  final double calories;
  final bool isToday;
}

class _DashboardNumberTicker extends StatefulWidget {
  const _DashboardNumberTicker({
    required this.value,
    required this.style,
    this.suffix = '',
    this.maxLines = 1,
    this.fixedWidth,
  });

  final num value;
  final String suffix;
  final TextStyle style;
  final int maxLines;
  final double? fixedWidth;

  @override
  State<_DashboardNumberTicker> createState() => _DashboardNumberTickerState();
}

class _DashboardNumberTickerState extends State<_DashboardNumberTicker> {
  bool _hasAnimatedOnce = false;

  void _markAnimatedOnceIfNeeded(bool shouldAnimate) {
    if (!shouldAnimate || _hasAnimatedOnce) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasAnimatedOnce) return;
      setState(() => _hasAnimatedOnce = true);
    });
  }

  String _format(num value) {
    final isWhole = (value - value.round()).abs() < 0.01;
    if (!isWhole) {
      return value.toStringAsFixed(1);
    }

    final raw = value.round().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) buffer.write(',');
      buffer.write(raw[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = widget.style.copyWith(height: 1.0);
    final fontSize =
        effectiveStyle.fontSize ??
        DefaultTextStyle.of(context).style.fontSize ??
        14.0;

    final numberText = _format(widget.value);
    final digitWidth = (fontSize * 0.64).clamp(7.0, 22.0);
    final lineHeight = (fontSize * 1.10).clamp(10.0, 32.0);
    final shouldAnimate = !_hasAnimatedOnce && widget.value != 0;
    _markAnimatedOnceIfNeeded(shouldAnimate);

    final counter = Semantics(
      label: '$numberText${widget.suffix}',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: SizedBox(
          height: lineHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ...List.generate(numberText.length, (index) {
                final char = numberText[index];
                final digit = int.tryParse(char);

                if (digit == null) {
                  return _StaticTickerCharacter(
                    char: char,
                    style: effectiveStyle,
                    height: lineHeight,
                  );
                }

                return _LotteryDigitWheel(
                  key: ValueKey('digit-$index'),
                  digit: digit,
                  style: effectiveStyle,
                  width: digitWidth,
                  height: lineHeight,
                  animate: shouldAnimate,
                );
              }),
              if (widget.suffix.isNotEmpty)
                Text(
                  widget.suffix,
                  maxLines: widget.maxLines,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: effectiveStyle,
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.fixedWidth != null) {
      return SizedBox(
        width: widget.fixedWidth,
        child: Center(child: counter),
      );
    }

    return counter;
  }
}

class _StaticTickerCharacter extends StatelessWidget {
  const _StaticTickerCharacter({
    required this.char,
    required this.style,
    required this.height,
  });

  final String char;
  final TextStyle style;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          char,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: style,
        ),
      ),
    );
  }
}

class _LotteryDigitWheel extends StatelessWidget {
  const _LotteryDigitWheel({
    super.key,
    required this.digit,
    required this.style,
    required this.width,
    required this.height,
    required this.animate,
  });

  final int digit;
  final TextStyle style;
  final double width;
  final double height;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    // One-time short, soft lottery roll: starts from 0 only on first load, then
    // stays stable during scrolling/rebuilds. Short enough to feel premium,
    // smooth enough to avoid harsh digit jumps.
    final beginValue = animate ? 0.0 : digit.toDouble();
    final endValue = digit.toDouble();

    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRect(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: beginValue, end: endValue),
            duration: animate
                ? const Duration(milliseconds: 780)
                : Duration.zero,
            curve: Curves.easeOutQuart,
            builder: (context, value, _) {
              final clamped = value.clamp(0.0, 9.0);
              final currentDigit = clamped.floor().clamp(0, 9);
              final nextDigit = (currentDigit + 1).clamp(0, 9);
              final fraction = (clamped - currentDigit).clamp(0.0, 1.0);

              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    top: -fraction * height,
                    left: 0,
                    width: width,
                    height: height,
                    child: _digitText(currentDigit),
                  ),
                  Positioned(
                    top: (1 - fraction) * height,
                    left: 0,
                    width: width,
                    height: height,
                    child: _digitText(nextDigit),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _digitText(int value) {
    return Center(
      child: Text(
        '$value',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}

class _UltraSmoothWeeklyCaloriesCard extends StatefulWidget {
  const _UltraSmoothWeeklyCaloriesCard({
    required this.uid,
    required this.targetCalories,
    required this.animationSeed,
    required this.graphAnimationEnabled,
    required this.reduceAnimations,
  });

  final String uid;
  final int targetCalories;
  final int animationSeed;
  final bool graphAnimationEnabled;
  final bool reduceAnimations;

  @override
  State<_UltraSmoothWeeklyCaloriesCard> createState() =>
      _UltraSmoothWeeklyCaloriesCardState();
}

class _UltraSmoothWeeklyCaloriesCardState
    extends State<_UltraSmoothWeeklyCaloriesCard>
    with AutomaticKeepAliveClientMixin {
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  bool _loading = true;
  List<_DailyCalories> _points = const [];
  int _todayCalories = 0;
  int _avgCalories = 0;
  int _highestCalories = 0;
  int _onTargetDays = 0;
  double _maxCalories = 1;
  String _signature = '';
  String _lastGraphAnimationToken = '';
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _weeklyMealsSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _startWeeklyCaloriesListener();
  }

  @override
  void didUpdateWidget(covariant _UltraSmoothWeeklyCaloriesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.targetCalories != widget.targetCalories ||
        oldWidget.animationSeed != widget.animationSeed) {
      _startWeeklyCaloriesListener();
    }
  }

  @override
  void dispose() {
    _weeklyMealsSub?.cancel();
    super.dispose();
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _dayLabel(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  double _safeDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  void _startWeeklyCaloriesListener() {
    final today = DateTime.now();
    final startDate = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 6));
    final weekKeys = List<String>.generate(
      7,
      (i) => _dateKey(startDate.add(Duration(days: i))),
    );

    _weeklyMealsSub?.cancel();
    if (mounted && !_loading) setState(() => _loading = true);

    _weeklyMealsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('meals')
        .where(FieldPath.documentId, whereIn: weekKeys)
        .snapshots()
        .listen(
          (snap) {
            final totalsByDate = <String, double>{
              for (final key in weekKeys) key: 0.0,
            };

            for (final doc in snap.docs) {
              totalsByDate[doc.id] = _safeDouble(doc.data()['calories']);
            }

            final points = List<_DailyCalories>.generate(7, (i) {
              final date = startDate.add(Duration(days: i));
              final key = _dateKey(date);
              return _DailyCalories(
                dateKey: key,
                label: _dayLabel(date),
                calories: totalsByDate[key] ?? 0.0,
                isToday: key == _dateKey(today),
              );
            });

            final nonZero = points.where((p) => p.calories > 0).toList();
            final todayCalories = points.last.calories.toInt();
            final avgCalories = nonZero.isEmpty
                ? 0
                : (nonZero.fold<double>(0, (sum, p) => sum + p.calories) /
                          nonZero.length)
                      .round();
            final highestCalories = points
                .fold<double>(
                  0,
                  (maxValue, p) =>
                      p.calories > maxValue ? p.calories : maxValue,
                )
                .round();
            final onTargetDays = points.where((p) {
              if (p.calories <= 0) return false;
              return (p.calories - widget.targetCalories).abs() <= 250;
            }).length;
            final highestScale =
                [
                  widget.targetCalories.toDouble(),
                  ...points.map((p) => p.calories),
                ].fold<double>(
                  1,
                  (maxValue, v) => v > maxValue ? v : maxValue,
                ) *
                1.12;
            final signature = points
                .map((p) => '${p.dateKey}:${p.calories.toInt()}')
                .join('|');

            if (!mounted) return;
            setState(() {
              _points = points;
              _todayCalories = todayCalories;
              _avgCalories = avgCalories;
              _highestCalories = highestCalories;
              _onTargetDays = onTargetDays;
              _maxCalories = highestScale <= 0 ? 1 : highestScale;
              _signature = signature;
              _loading = false;
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Animate only when the real weekly data is ready. Previously the empty
    // loading graph consumed the animation, so the final graph appeared static.
    final graphAnimationToken = '${_signature}:${widget.animationSeed}';
    final shouldAnimate =
        widget.graphAnimationEnabled &&
        !widget.reduceAnimations &&
        !_loading &&
        _signature.isNotEmpty &&
        _lastGraphAnimationToken != graphAnimationToken;

    if (shouldAnimate) {
      _lastGraphAnimationToken = graphAnimationToken;
    }

    final points = _points.isEmpty
        ? List<_DailyCalories>.generate(7, (i) {
            final date = DateTime.now().subtract(Duration(days: 6 - i));
            return _DailyCalories(
              dateKey: _dateKey(date),
              label: _dayLabel(date),
              calories: 0,
              isToday: i == 6,
            );
          })
        : _points;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: card.withOpacity(0.96),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: lime.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: lime.withOpacity(0.14)),
                ),
                child: const Icon(
                  Icons.show_chart_rounded,
                  color: lime,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Weekly Calories',
                          maxLines: 1,
                          softWrap: false,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 20.5,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.35,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Food log trend',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.68),
                        fontSize: 12.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _miniPill(
                Icons.stacked_line_chart_rounded,
                'Average',
                '$_avgCalories',
                'kcal/day',
              ),
              const SizedBox(width: 9),
              _miniPill(
                Icons.arrow_upward_rounded,
                'Highest',
                '$_highestCalories',
                'kcal',
              ),
              const SizedBox(width: 9),
              _miniPill(
                Icons.flag_rounded,
                'On track',
                '$_onTargetDays',
                'days',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 188,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF10160E).withOpacity(0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.045)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: _UltraSmoothCaloriesGraph(
                  key: ValueKey(
                    'ultra-graph-${widget.uid}-${widget.targetCalories}-$_signature-${widget.animationSeed}',
                  ),
                  points: points,
                  maxCalories: _maxCalories,
                  targetCalories: widget.targetCalories.toDouble(),
                  shouldAnimate: shouldAnimate,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legendDot(lime, 'Target'),
              const SizedBox(width: 14),
              _legendDot(Colors.white, 'Calories'),
              const Spacer(),
              Text(
                '7-day trend',
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.55),
                  fontSize: 10.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniPill(IconData icon, String label, String value, String unit) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.044),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.040)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: lime, size: 17),
            const SizedBox(height: 8),
            _animatedMetricValue(
              value,
              GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 15.5,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              unit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.70),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.60),
                fontSize: 10.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _animatedMetricValue(String value, TextStyle style) {
    final cleaned = value
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.-]'), '');
    final number = double.tryParse(cleaned);
    final suffix = value.replaceAll(RegExp(r'[0-9.,\s-]'), '');

    if (number == null) {
      return Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return _DashboardNumberTicker(
      value: number,
      suffix: suffix,
      style: style,
      maxLines: 1,
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: soft.withOpacity(0.68),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _UltraSmoothCaloriesGraph extends StatefulWidget {
  const _UltraSmoothCaloriesGraph({
    super.key,
    required this.points,
    required this.maxCalories,
    required this.targetCalories,
    required this.shouldAnimate,
  });

  final List<_DailyCalories> points;
  final double maxCalories;
  final double targetCalories;
  final bool shouldAnimate;

  @override
  State<_UltraSmoothCaloriesGraph> createState() =>
      _UltraSmoothCaloriesGraphState();
}

class _UltraSmoothCaloriesGraphState extends State<_UltraSmoothCaloriesGraph> {
  static const Color soft = Color(0xFFB7C2A8);

  int? _activeIndex;

  int _indexFromDx(double dx, double width) {
    if (widget.points.length <= 1) return 0;

    const sideInset = 10.0;
    final usableWidth = (width - sideInset * 2).clamp(1.0, double.infinity);
    final normalized = ((dx - sideInset) / usableWidth).clamp(0.0, 1.0);
    return (normalized * (widget.points.length - 1)).round().clamp(
      0,
      widget.points.length - 1,
    );
  }

  void _showPoint(double dx, double width) {
    if (widget.points.isEmpty || width <= 0) return;
    final nextIndex = _indexFromDx(dx, width);
    if (_activeIndex == nextIndex) return;
    setState(() => _activeIndex = nextIndex);
  }

  void _hidePoint() {
    if (_activeIndex == null || !mounted) return;
    setState(() => _activeIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final graphWidth = constraints.maxWidth;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: widget.shouldAnimate ? 0 : 1,
                          end: 1,
                        ),
                        duration: widget.shouldAnimate
                            ? const Duration(milliseconds: 920)
                            : Duration.zero,
                        curve: Curves.easeOutQuart,
                        builder: (_, progress, __) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPressStart: (details) {
                              _showPoint(details.localPosition.dx, graphWidth);
                            },
                            onLongPressMoveUpdate: (details) {
                              _showPoint(details.localPosition.dx, graphWidth);
                            },
                            onLongPressEnd: (_) => _hidePoint(),
                            onLongPressCancel: _hidePoint,
                            child: CustomPaint(
                              isComplex: false,
                              willChange: _activeIndex != null,
                              painter: _UltraSmoothCaloriesPainter(
                                points: widget.points,
                                maxCalories: widget.maxCalories,
                                targetCalories: widget.targetCalories,
                                progress: progress,
                                activeIndex: _activeIndex,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_activeIndex != null)
                      _UltraSmoothCaloriesTooltip(
                        key: ValueKey(_activeIndex),
                        point: widget.points[_activeIndex!],
                        activeIndex: _activeIndex!,
                        totalPoints: widget.points.length,
                        width: graphWidth,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: widget.points.map((point) {
            final selected = widget.points.indexOf(point) == _activeIndex;
            return Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : point.isToday
                      ? Colors.white.withOpacity(0.90)
                      : soft.withOpacity(0.58),
                  fontSize: selected ? 11.4 : 10.8,
                  fontWeight: selected
                      ? FontWeight.w900
                      : point.isToday
                      ? FontWeight.w800
                      : FontWeight.w600,
                  height: 1,
                ),
                child: Text(
                  point.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _UltraSmoothCaloriesTooltip extends StatelessWidget {
  const _UltraSmoothCaloriesTooltip({
    super.key,
    required this.point,
    required this.activeIndex,
    required this.totalPoints,
    required this.width,
  });

  final _DailyCalories point;
  final int activeIndex;
  final int totalPoints;
  final double width;

  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFB7C2A8);

  @override
  Widget build(BuildContext context) {
    const sideInset = 10.0;
    const tooltipWidth = 118.0;
    final usableWidth = (width - sideInset * 2).clamp(1.0, double.infinity);
    final pointX = totalPoints <= 1
        ? width / 2
        : sideInset + (usableWidth / (totalPoints - 1)) * activeIndex;

    final left = (pointX - tooltipWidth / 2).clamp(0.0, width - tooltipWidth);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      left: left,
      top: 0,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Container(
              key: ValueKey('${point.dateKey}-${point.calories.toInt()}'),
              width: tooltipWidth,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF151A12).withOpacity(0.96),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: lime.withOpacity(0.22)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: point.isToday ? lime : Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          point.isToday
                              ? '${point.label} • Today'
                              : point.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${point.calories.round()} kcal',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1,
                            fontWeight: FontWeight.w900,
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
    );
  }
}

class _UltraSmoothCaloriesPainter extends CustomPainter {
  _UltraSmoothCaloriesPainter({
    required this.points,
    required this.maxCalories,
    required this.targetCalories,
    required this.progress,
    this.activeIndex,
  });

  final List<_DailyCalories> points;
  final double maxCalories;
  final double targetCalories;
  final double progress;
  final int? activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    const lime = Color(0xFFD6FF60);
    const graphLine = Color(0xFFF3FFF7);
    const softLine = Color(0xFFB7C2A8);

    const topPadding = 18.0;
    const bottomPadding = 12.0;
    const sideInset = 10.0;
    final usableHeight = size.height - topPadding - bottomPadding;
    final usableWidth = size.width - (sideInset * 2);
    final yMax = maxCalories <= 0 ? 1.0 : maxCalories;
    final reveal = progress.clamp(0.0, 1.0).toDouble();

    Offset pointOffset(int index, double calories) {
      final x = points.length == 1
          ? size.width / 2
          : sideInset + (usableWidth / (points.length - 1)) * index;
      final normalized = (calories / yMax).clamp(0.0, 1.0);
      final y = topPadding + usableHeight - (normalized * usableHeight);
      return Offset(x, y);
    }

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.035)
      ..strokeWidth = 1;

    for (int i = 0; i < 4; i++) {
      final y = topPadding + (usableHeight / 3) * i;
      canvas.drawLine(Offset(6, y), Offset(size.width - 6, y), gridPaint);
    }

    if (targetCalories > 0) {
      final targetY =
          topPadding +
          usableHeight -
          ((targetCalories / yMax).clamp(0.0, 1.0) * usableHeight);
      final dashPaint = Paint()
        ..color = lime.withOpacity(0.34)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      var x = 8.0;
      while (x < size.width - 8) {
        canvas.drawLine(
          Offset(x, targetY),
          Offset((x + 9).clamp(8, size.width - 8).toDouble(), targetY),
          dashPaint,
        );
        x += 16;
      }
    }

    final offsets = List<Offset>.generate(
      points.length,
      (i) => pointOffset(i, points[i].calories),
    );

    if (activeIndex != null &&
        activeIndex! >= 0 &&
        activeIndex! < offsets.length) {
      final active = offsets[activeIndex!];
      canvas.drawLine(
        Offset(active.dx, topPadding - 4),
        Offset(active.dx, topPadding + usableHeight + 5),
        Paint()
          ..color = Colors.white.withOpacity(0.10)
          ..strokeWidth = 1,
      );
    }

    final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 1; i < offsets.length; i++) {
      linePath.lineTo(offsets[i].dx, offsets[i].dy);
    }

    final fillPath = Path()
      ..moveTo(offsets.first.dx, topPadding + usableHeight)
      ..lineTo(offsets.first.dx, offsets.first.dy);
    fillPath.addPath(linePath, Offset.zero);
    fillPath.lineTo(offsets.last.dx, topPadding + usableHeight);
    fillPath.close();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));

    canvas.drawPath(fillPath, Paint()..color = lime.withOpacity(0.050));
    canvas.drawPath(
      linePath,
      Paint()
        ..color = graphLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.restore();

    final pointPaint = Paint()..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (int i = 0; i < offsets.length; i++) {
      final pointReveal = ((reveal * (offsets.length + 0.75)) - i)
          .clamp(0.0, 1.0)
          .toDouble();
      if (pointReveal <= 0) continue;

      final hasData = points[i].calories > 0;
      final isToday = points[i].isToday;
      final isActive = i == activeIndex;
      final radius = hasData
          ? (isActive
                ? 7.0
                : isToday
                ? 5.8
                : 4.5)
          : (isActive ? 5.2 : 3.0);

      if (isActive) {
        canvas.drawCircle(
          offsets[i],
          11.0 * pointReveal,
          Paint()..color = lime.withOpacity(0.13 * pointReveal),
        );
      }

      pointPaint.color = hasData
          ? ((isToday || isActive) ? lime : graphLine).withOpacity(pointReveal)
          : softLine.withOpacity(0.25 * pointReveal);
      canvas.drawCircle(offsets[i], radius * pointReveal, pointPaint);

      if (hasData || isActive) {
        ringPaint.color = Colors.black.withOpacity(0.30 * pointReveal);
        canvas.drawCircle(offsets[i], radius * pointReveal, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UltraSmoothCaloriesPainter oldDelegate) {
    if (oldDelegate.activeIndex != activeIndex) return true;
    if (oldDelegate.progress != progress) return true;
    if (oldDelegate.maxCalories != maxCalories) return true;
    if (oldDelegate.targetCalories != targetCalories) return true;
    if (oldDelegate.points.length != points.length) return true;
    for (int i = 0; i < points.length; i++) {
      if (oldDelegate.points[i].calories != points[i].calories ||
          oldDelegate.points[i].isToday != points[i].isToday) {
        return true;
      }
    }
    return false;
  }
}

class _UltraSmoothDashboardCalendarCard extends StatefulWidget {
  const _UltraSmoothDashboardCalendarCard({
    required this.uid,
    required this.targetCalories,
    required this.todaySteps,
    required this.waterLiters,
    required this.formatNumber,
    required this.dateKey,
  });

  final String uid;
  final int targetCalories;
  final int todaySteps;
  final double waterLiters;
  final String Function(int value) formatNumber;
  final String Function(DateTime date) dateKey;

  @override
  State<_UltraSmoothDashboardCalendarCard> createState() =>
      _UltraSmoothDashboardCalendarCardState();
}

class _UltraSmoothDashboardCalendarCardState
    extends State<_UltraSmoothDashboardCalendarCard>
    with AutomaticKeepAliveClientMixin {
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  String? _loadedKey;
  int _calories = 0;
  int _steps = 0;
  double _water = 0;
  bool _hasActivityData = false;
  bool _hasWaterData = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _mealSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _journalSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _activitySub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _summarySub;
  String _mood = 'No diary';
  String _energy = 'Tap to add';
  bool _hasJournal = false;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _steps = widget.todaySteps;
    _water = widget.waterLiters;
    _startLiveData();
  }

  @override
  void didUpdateWidget(covariant _UltraSmoothDashboardCalendarCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _startLiveData();
      return;
    }

    if (oldWidget.todaySteps != widget.todaySteps ||
        oldWidget.waterLiters != widget.waterLiters) {
      _syncFallbackValuesFromParent();
    }
  }

  @override
  void dispose() {
    _cancelLiveData();
    super.dispose();
  }

  int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _safeDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _safeString(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  void _cancelLiveData() {
    _mealSub?.cancel();
    _journalSub?.cancel();
    _activitySub?.cancel();
    _summarySub?.cancel();
  }

  void _setLoadedOnError() {
    if (!mounted) return;
    if (_loading) setState(() => _loading = false);
  }

  void _syncFallbackValuesFromParent() {
    if (!mounted) return;

    final nextSteps = _hasActivityData ? _steps : widget.todaySteps;
    final nextWater = _hasWaterData ? _water : widget.waterLiters;

    if (nextSteps == _steps && nextWater == _water) return;

    setState(() {
      _steps = nextSteps;
      _water = nextWater;
    });
  }

  void _startLiveData() {
    final todayKey = widget.dateKey(DateTime.now());
    _loadedKey = todayKey;

    _cancelLiveData();

    _steps = widget.todaySteps;
    _water = widget.waterLiters;
    _hasActivityData = false;
    _hasWaterData = false;

    if (mounted && !_loading) {
      setState(() => _loading = true);
    }

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid);

    _mealSub = userRef.collection('meals').doc(todayKey).snapshots().listen((
      doc,
    ) {
      if (!mounted || _loadedKey != todayKey) return;
      final meal = doc.data() ?? <String, dynamic>{};
      setState(() {
        _calories = _safeInt(meal['calories']);
        _loading = false;
      });
    }, onError: (_) => _setLoadedOnError());

    _journalSub = userRef
        .collection('daily_journal')
        .doc(todayKey)
        .snapshots()
        .listen((doc) {
          if (!mounted || _loadedKey != todayKey) return;
          final journal = doc.data() ?? <String, dynamic>{};
          setState(() {
            _hasJournal = journal.isNotEmpty;
            _mood = _safeString(journal['mood'], 'No diary');
            _energy = _safeString(journal['energy'], 'Tap to add');
            _loading = false;
          });
        }, onError: (_) => _setLoadedOnError());

    _activitySub = userRef
        .collection('activity')
        .doc(todayKey)
        .snapshots()
        .listen((doc) {
          if (!mounted || _loadedKey != todayKey) return;
          final activity = doc.data() ?? <String, dynamic>{};
          final savedSteps = _safeInt(activity['steps']);
          setState(() {
            _hasActivityData = savedSteps > 0;
            _steps = savedSteps > 0 ? savedSteps : widget.todaySteps;
            _loading = false;
          });
        }, onError: (_) => _setLoadedOnError());

    _summarySub = userRef
        .collection('daily_summary')
        .doc(todayKey)
        .snapshots()
        .listen((doc) {
          if (!mounted || _loadedKey != todayKey) return;
          final summary = doc.data() ?? <String, dynamic>{};
          final savedWater = _safeDouble(summary['waterLiters']);
          setState(() {
            _hasWaterData = savedWater > 0;
            _water = savedWater > 0 ? savedWater : widget.waterLiters;
            _loading = false;
          });
        }, onError: (_) => _setLoadedOnError());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final safeTarget = widget.targetCalories <= 0
        ? 2000
        : widget.targetCalories;
    final calorieProgress = (_calories / safeTarget).clamp(0.0, 1.0).toDouble();
    final stepsProgress = (_steps / 8000).clamp(0.0, 1.0).toDouble();
    final waterProgress = (_water / 3.0).clamp(0.0, 1.0).toDouble();
    final foodLogged = _calories > 0;
    final stepsGood = _steps >= 8000;
    final waterGood = _water >= 3.0;
    final completedCount = [
      foodLogged,
      stepsGood,
      waterGood,
      _hasJournal,
    ].where((done) => done).length;

    return GestureDetector(
      onTap: () async {
        await Navigator.pushNamed(context, '/health-calendar');
        if (mounted) _startLiveData();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: card.withOpacity(0.96),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(0.055)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: lime.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: lime.withOpacity(0.14)),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: lime,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Health Calendar',
                            maxLines: 1,
                            softWrap: false,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.35,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _loading
                            ? 'Loading diary'
                            : _hasJournal
                            ? '$_mood • $_energy'
                            : 'Add mood and energy',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: soft.withOpacity(0.72),
                          fontSize: 12.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: lime.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: lime,
                    size: 19,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _metric(
                    label: 'Calories',
                    value: '${_calories.clamp(0, 99999)}',
                    icon: Icons.local_fire_department_rounded,
                    active: foodLogged,
                    progress: calorieProgress,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric(
                    label: 'Steps',
                    value: widget.formatNumber(_steps),
                    icon: Icons.directions_walk_rounded,
                    active: stepsGood,
                    progress: stepsProgress,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric(
                    label: 'Water',
                    value:
                        '${_water.toStringAsFixed(_water % 1 == 0 ? 0 : 1)}L',
                    icon: Icons.water_drop_rounded,
                    active: waterGood,
                    progress: waterProgress,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _flatProgress(completedCount / 4, 7)),
                const SizedBox(width: 10),
                Text(
                  '$completedCount/4 today',
                  style: GoogleFonts.outfit(
                    color: lime,
                    fontSize: 11.8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric({
    required String label,
    required String value,
    required IconData icon,
    required bool active,
    required double progress,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.050),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? lime.withOpacity(0.16)
              : Colors.white.withOpacity(0.040),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: active ? lime : soft.withOpacity(0.62),
                size: 16,
              ),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active ? lime : Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _animatedMetricValue(
            value,
            GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: soft.withOpacity(0.66),
              fontSize: 10.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _flatProgress(progress, 4),
        ],
      ),
    );
  }

  Widget _animatedMetricValue(String value, TextStyle style) {
    final cleaned = value
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.-]'), '');
    final number = double.tryParse(cleaned);
    final suffix = value.replaceAll(RegExp(r'[0-9.,\s-]'), '');

    if (number == null) {
      return Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return _DashboardNumberTicker(
      value: number,
      suffix: suffix,
      style: style,
      maxLines: 1,
    );
  }

  Widget _flatProgress(double value, double height) {
    final safeValue = value.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withOpacity(0.075)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: safeValue,
              child: const ColoredBox(color: lime),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveCaloriesGraph extends StatefulWidget {
  const _InteractiveCaloriesGraph({
    super.key,
    required this.points,
    required this.maxCalories,
    required this.targetCalories,
    this.shouldAnimate = false,
  });

  final List<_DailyCalories> points;
  final double maxCalories;
  final double targetCalories;
  final bool shouldAnimate;

  @override
  State<_InteractiveCaloriesGraph> createState() =>
      _InteractiveCaloriesGraphState();
}

class _InteractiveCaloriesGraphState extends State<_InteractiveCaloriesGraph> {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: widget.shouldAnimate ? 0.0 : 1.0, end: 1.0),
        duration: widget.shouldAnimate
            ? const Duration(milliseconds: 720)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (_, progress, __) {
          return CustomPaint(
            isComplex: false,
            willChange: progress < 1.0,
            painter: _CalorieGraphPainter(
              points: widget.points,
              maxCalories: widget.maxCalories,
              targetCalories: widget.targetCalories,
              touchedIndex: null,
              animationProgress: progress,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _GraphTooltip extends StatelessWidget {
  const _GraphTooltip({
    required this.activeIndex,
    required this.points,
    required this.width,
  });

  final int activeIndex;
  final List<_DailyCalories> points;
  final double width;

  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFB7C2A8);

  @override
  Widget build(BuildContext context) {
    const tooltipWidth = 94.0;

    final spacing = points.length <= 1 ? width : width / (points.length - 1);
    var tooltipLeft = (spacing * activeIndex) - (tooltipWidth / 2);
    tooltipLeft = tooltipLeft.clamp(0.0, width - tooltipWidth);

    final point = points[activeIndex];

    return Positioned(
      left: tooltipLeft,
      top: 2,
      child: RepaintBoundary(
        child: Container(
          width: tooltipWidth,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF151A12),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: lime.withOpacity(0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                point.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${point.calories.toInt()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'kcal',
                style: GoogleFonts.outfit(
                  color: lime,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalorieGraphPainter extends CustomPainter {
  _CalorieGraphPainter({
    required this.points,
    required this.maxCalories,
    required this.targetCalories,
    this.touchedIndex,
    this.animationProgress = 1.0,
  });

  final List<_DailyCalories> points;
  final double maxCalories;
  final double targetCalories;
  final int? touchedIndex;
  final double animationProgress;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    const lime = Color(0xFFD6FF60);
    const graphLine = Color(0xFFF3FFF7);
    const softLine = Color(0xFFB7C2A8);

    const labelHeight = 27.0;
    final chartHeight = size.height - labelHeight;
    final chartWidth = size.width;
    const topPadding = 28.0;
    const bottomPadding = 18.0;
    final usableHeight = chartHeight - topPadding - bottomPadding;
    final yMax = maxCalories <= 0 ? 1.0 : maxCalories;
    final reveal = animationProgress.clamp(0.0, 1.0).toDouble();

    Offset pointOffset(int index, double calories) {
      const sideInset = 12.0;
      final usableWidth = chartWidth - (sideInset * 2);
      final x = points.length == 1
          ? chartWidth / 2
          : sideInset + (usableWidth / (points.length - 1)) * index;
      final normalized = (calories / yMax).clamp(0.0, 1.0);
      final y = topPadding + usableHeight - (normalized * usableHeight);
      return Offset(x, y);
    }

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.035)
      ..strokeWidth = 1;

    for (int i = 0; i < 4; i++) {
      final y = topPadding + (usableHeight / 3) * i;
      canvas.drawLine(Offset(8, y), Offset(chartWidth - 8, y), gridPaint);
    }

    final baselinePaint = Paint()
      ..color = Colors.white.withOpacity(0.055)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(8, topPadding + usableHeight),
      Offset(chartWidth - 8, topPadding + usableHeight),
      baselinePaint,
    );

    if (targetCalories > 0) {
      final targetY =
          topPadding +
          usableHeight -
          ((targetCalories / yMax).clamp(0.0, 1.0) * usableHeight);

      final dashPaint = Paint()
        ..color = lime.withOpacity(0.34)
        ..strokeWidth = 1.15
        ..strokeCap = StrokeCap.round;

      double x = 10;
      final targetRevealEnd = 10 + ((chartWidth - 20) * reveal);
      while (x < targetRevealEnd) {
        canvas.drawLine(
          Offset(x, targetY),
          Offset((x + 9).clamp(0.0, targetRevealEnd).toDouble(), targetY),
          dashPaint,
        );
        x += 16;
      }
    }

    final offsets = List<Offset>.generate(
      points.length,
      (i) => pointOffset(i, points[i].calories),
    );

    if (touchedIndex != null &&
        touchedIndex! >= 0 &&
        touchedIndex! < offsets.length) {
      final active = offsets[touchedIndex!];
      canvas.drawLine(
        Offset(active.dx, topPadding - 4),
        Offset(active.dx, topPadding + usableHeight + 2),
        Paint()
          ..color = Colors.white.withOpacity(0.10)
          ..strokeWidth = 1,
      );
    }

    final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 0; i < offsets.length - 1; i++) {
      final p0 = offsets[i];
      final p1 = offsets[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path()
      ..moveTo(offsets.first.dx, topPadding + usableHeight)
      ..lineTo(offsets.first.dx, offsets.first.dy);
    fillPath.addPath(linePath, Offset.zero);
    fillPath.lineTo(offsets.last.dx, topPadding + usableHeight);
    fillPath.close();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, chartWidth * reveal, chartHeight));

    // Lightweight fill: solid translucent color instead of shader gradient.
    canvas.drawPath(
      fillPath,
      Paint()..color = lime.withOpacity(0.055 * reveal),
    );

    // Lightweight shadow + line. No blur mask/shader.
    canvas.drawPath(
      linePath,
      Paint()
        ..color = Colors.black.withOpacity(0.18 * reveal)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = graphLine.withOpacity(reveal)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.restore();

    for (int i = 0; i < offsets.length; i++) {
      final pointProgress = ((reveal * (offsets.length + 0.75)) - i)
          .clamp(0.0, 1.0)
          .toDouble();
      if (pointProgress <= 0) continue;

      final p = offsets[i];
      final isToday = points[i].isToday;
      final isTouched = i == touchedIndex;
      final hasData = points[i].calories > 0;

      if (!hasData) {
        canvas.drawCircle(
          p,
          3.0 * pointProgress,
          Paint()
            ..color = softLine.withOpacity(0.26 * pointProgress)
            ..style = PaintingStyle.fill,
        );
        continue;
      }

      if (isToday || isTouched) {
        canvas.drawCircle(
          p,
          (isTouched ? 10.2 : 8.8) * pointProgress,
          Paint()..color = lime.withOpacity(0.13 * pointProgress),
        );
      }

      final pointRadius =
          (isTouched
              ? 6.8
              : isToday
              ? 6.0
              : 4.6) *
          pointProgress;

      canvas.drawCircle(
        p,
        pointRadius,
        Paint()
          ..color = (isToday || isTouched ? lime : graphLine).withOpacity(
            pointProgress,
          )
          ..style = PaintingStyle.fill,
      );

      canvas.drawCircle(
        p,
        pointRadius,
        Paint()
          ..color = Colors.black.withOpacity(0.32 * pointProgress)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // Use default TextStyle instead of GoogleFonts inside painter.
    // This avoids expensive font layout during paint.
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (int i = 0; i < points.length; i++) {
      final p = pointOffset(i, 0);
      textPainter.text = TextSpan(
        text: points[i].label.length > 3
            ? points[i].label.substring(0, 3)
            : points[i].label,
        style: TextStyle(
          color: points[i].isToday
              ? Colors.white.withOpacity(reveal)
              : softLine.withOpacity(0.55 * reveal),
          fontSize: 11.3,
          fontWeight: points[i].isToday ? FontWeight.w900 : FontWeight.w600,
          height: 1.0,
        ),
      );
      textPainter.layout(minWidth: 0, maxWidth: 42);
      textPainter.paint(
        canvas,
        Offset(p.dx - (textPainter.width / 2), size.height - labelHeight + 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CalorieGraphPainter oldDelegate) {
    if (oldDelegate.touchedIndex != touchedIndex) return true;
    if (oldDelegate.animationProgress != animationProgress) return true;
    if (oldDelegate.points.length != points.length) return true;
    for (int i = 0; i < points.length; i++) {
      if (oldDelegate.points[i].calories != points[i].calories ||
          oldDelegate.points[i].isToday != points[i].isToday) {
        return true;
      }
    }
    return oldDelegate.maxCalories != maxCalories ||
        oldDelegate.targetCalories != targetCalories;
  }
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width / 2, size.height)
        ..lineTo(0, 0)
        ..lineTo(size.width, 0)
        ..close(),
      Paint()..color = const Color(0xFFD6FF60),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _NutritionAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NutritionAction(this.icon, this.title, this.subtitle, this.onTap);
}

class _StepViewState {
  const _StepViewState({
    required this.steps,
    required this.isLoading,
    required this.error,
    required this.usingDemo,
    required this.sourceLabel,
  });

  final int steps;
  final bool isLoading;
  final String? error;
  final bool usingDemo;
  final String sourceLabel;

  _StepViewState copyWith({
    int? steps,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? usingDemo,
    String? sourceLabel,
  }) {
    return _StepViewState(
      steps: steps ?? this.steps,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      usingDemo: usingDemo ?? this.usingDemo,
      sourceLabel: sourceLabel ?? this.sourceLabel,
    );
  }
}

class _DashboardCalendarDiaryCard extends StatefulWidget {
  const _DashboardCalendarDiaryCard({
    required this.uid,
    required this.targetCalories,
    required this.todaySteps,
    required this.waterLiters,
    required this.reduceAnimations,
    required this.formatNumber,
    required this.safeInt,
    required this.safeDouble,
    required this.safeString,
    required this.dateKey,
  });

  final String uid;
  final int targetCalories;
  final int todaySteps;
  final double waterLiters;
  final bool reduceAnimations;
  final String Function(int value) formatNumber;
  final int Function(dynamic value, {int fallback}) safeInt;
  final double Function(dynamic value, {double fallback}) safeDouble;
  final String Function(dynamic value, {String fallback}) safeString;
  final String Function(DateTime date) dateKey;

  @override
  State<_DashboardCalendarDiaryCard> createState() =>
      _DashboardCalendarDiaryCardState();
}

class _DashboardCalendarDiaryCardState
    extends State<_DashboardCalendarDiaryCard>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const Color lime = Color(0xFFD6FF60);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);

  late final AnimationController _entryController;
  late final Animation<double> _entryOpacity;
  late final Animation<Offset> _entrySlide;

  String? _loadedDayKey;
  int _calories = 0;
  String _mood = 'No diary';
  String _energy = 'Tap to add';
  bool _hasJournal = false;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _entryOpacity = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );

    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
        );

    if (widget.reduceAnimations) {
      _entryController.value = 1;
    } else {
      _entryController.forward();
    }

    _loadCardData();
  }

  @override
  void didUpdateWidget(covariant _DashboardCalendarDiaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.reduceAnimations && _entryController.value != 1) {
      _entryController.value = 1;
    }

    final todayKey = widget.dateKey(DateTime.now());
    if (oldWidget.uid != widget.uid || _loadedDayKey != todayKey) {
      _loadCardData();
    }
  }

  Future<void> _loadCardData() async {
    final todayKey = widget.dateKey(DateTime.now());
    _loadedDayKey = todayKey;

    if (mounted && !_loading) {
      setState(() => _loading = true);
    }

    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid);
      final docs = await Future.wait([
        userRef.collection('meals').doc(todayKey).get(),
        userRef.collection('daily_journal').doc(todayKey).get(),
      ]).timeout(const Duration(seconds: 5));

      final mealData = docs[0].data() ?? <String, dynamic>{};
      final journalData = docs[1].data() ?? <String, dynamic>{};

      if (!mounted || _loadedDayKey != todayKey) return;

      setState(() {
        _calories = widget.safeInt(mealData['calories']);
        _hasJournal = journalData.isNotEmpty;
        _mood = widget.safeString(journalData['mood'], fallback: 'No diary');
        _energy = widget.safeString(
          journalData['energy'],
          fallback: 'Tap to add',
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted || _loadedDayKey != todayKey) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final safeTarget = widget.targetCalories <= 0
        ? 2000
        : widget.targetCalories;
    final calorieProgress = (_calories / safeTarget).clamp(0.0, 1.0);
    final stepsGood = widget.todaySteps >= 8000;
    final waterGood = widget.waterLiters >= 3.0;
    final foodLogged = _calories > 0;
    final completedCount = [
      foodLogged,
      stepsGood,
      waterGood,
      _hasJournal,
    ].where((done) => done).length;

    final card = GestureDetector(
      onTap: () async {
        await Navigator.pushNamed(context, '/health-calendar');
        if (mounted) _loadCardData();
      },
      child: RepaintBoundary(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF202A18).withOpacity(0.96),
                const Color(0xFF141A11).withOpacity(0.96),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.060)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: lime.withOpacity(0.14)),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: lime,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Health Calendar',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _loading
                              ? 'Loading today\'s diary...'
                              : _hasJournal
                              ? '$_mood mood • $_energy energy'
                              : 'Add mood, energy and today\'s notes',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: soft.withOpacity(0.72),
                            fontSize: 12.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.052),
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: lime,
                      size: 19,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      label: 'Calories',
                      value: '${_calories.clamp(0, 99999)}',
                      icon: Icons.local_fire_department_rounded,
                      active: foodLogged,
                      progress: calorieProgress,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _metric(
                      label: 'Steps',
                      value: widget.formatNumber(widget.todaySteps),
                      icon: Icons.directions_walk_rounded,
                      active: stepsGood,
                      progress: (widget.todaySteps / 8000).clamp(0.0, 1.0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _metric(
                      label: 'Water',
                      value:
                          '${widget.waterLiters.toStringAsFixed(widget.waterLiters % 1 == 0 ? 0 : 1)}L',
                      icon: Icons.water_drop_rounded,
                      active: waterGood,
                      progress: (widget.waterLiters / 3.0).clamp(0.0, 1.0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _flatProgressBar(
                      value: completedCount / 4,
                      height: 7,
                      color: lime,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$completedCount/4 today',
                    style: GoogleFonts.outfit(
                      color: lime,
                      fontSize: 11.8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.reduceAnimations || _entryController.value >= 0.999) {
      return card;
    }

    return FadeTransition(
      opacity: _entryOpacity,
      child: SlideTransition(position: _entrySlide, child: card),
    );
  }

  Widget _flatProgressBar({
    required double value,
    required double height,
    required Color color,
  }) {
    final safeValue = value.clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withOpacity(0.075)),
            FractionallySizedBox(
              widthFactor: safeValue,
              alignment: Alignment.centerLeft,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric({
    required String label,
    required String value,
    required IconData icon,
    required bool active,
    required double progress,
  }) {
    final safeProgress = progress.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.050),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? lime.withOpacity(0.16)
              : Colors.white.withOpacity(0.040),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: active ? lime : soft.withOpacity(0.62),
                size: 16,
              ),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active ? lime : Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: soft.withOpacity(0.66),
              fontSize: 10.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _flatProgressBar(
            value: safeProgress,
            height: 4,
            color: active ? lime : soft.withOpacity(0.32),
          ),
        ],
      ),
    );
  }
}

/// A staggered fade + slide-up entrance for a single item in a list/column.
///
/// Each item animates in slightly after the one before it (controlled by
/// [index] and [interval]), producing the polished "cards cascade in" effect
/// used by high-end apps. The motion matches the rest of NutriPulse: an 18px
/// upward slide with a soft fade on Curves.easeOutCubic.
///
/// Because the whole page is given a fresh [PageStorageKey]-style ValueKey via
/// the [replayKey] counter whenever it becomes visible, these widgets are
/// rebuilt from scratch on each visit, so the entrance replays every time the
/// user opens OR swipes to the screen — not just on first build.
class _StaggeredItem extends StatefulWidget {
  const _StaggeredItem({
    required this.index,
    required this.child,
    this.interval = const Duration(milliseconds: 70),
    this.duration = const Duration(milliseconds: 480),
    this.offsetY = 18,
    this.enabled = true,
  });

  /// Position in the list — used to delay each successive item.
  final int index;

  /// Gap between consecutive items' start times.
  final Duration interval;

  /// How long each item's entrance takes.
  final Duration duration;

  /// How far (in logical px) the item slides up from.
  final double offsetY;

  /// When false, the child is shown immediately with no animation
  /// (respects a user's "reduce animations" preference).
  final bool enabled;

  final Widget child;

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    if (!widget.enabled) {
      _controller.value = 1.0;
    } else {
      // Stagger: start this item's entrance after index * interval.
      final delay = widget.interval * widget.index;
      Future.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
