import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/gamification_profile.dart';
import 'health_score_service.dart';
import 'mission_service.dart';
import 'streak_service.dart';
import 'xp_service.dart';
import 'leaderboard_service.dart';

class GamificationService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Listen to this stream from any screen/root widget to show a celebration.
  /// This keeps the service independent from BuildContext, main.dart, and navigatorKey.
  static final StreamController<Map<String, dynamic>> _rewardController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get rewardStream =>
      _rewardController.stream;

  static void _emitReward({
    required String action,
    required Map<String, dynamic> result,
  }) {
    final awardedXp = (result['awardedXp'] is num)
        ? (result['awardedXp'] as num).toInt()
        : 0;

    if (awardedXp <= 0) return;

    _rewardController.add({
      'action': action,
      'title': _titleForAction(action),
      'awardedXp': awardedXp,
      'levelUp': result['levelUp'] == true,
      'level': result['level'],
      'streak': result['streak'],
    });
  }

  static String _titleForAction(String action) {
    switch (action) {
      case 'food_logged':
        return 'Meal Logged';
      case 'ai_food_scan':
        return 'AI Food Scan';
      case 'barcode_scan':
        return 'Barcode Scanned';
      case 'manual_food':
        return 'Food Added';
      case 'water_goal':
        return 'Hydration Goal';
      case 'step_goal':
        return 'Step Goal Completed';
      case 'protein_goal':
        return 'Protein Goal Hit';
      case 'ai_coach':
        return 'AI Coach Used';
      default:
        if (action.startsWith('mission_')) return 'Mission Completed';
        return 'Reward Earned';
    }
  }

  static String dateKey([DateTime? date]) =>
      StreakService.dateKey(date ?? DateTime.now());

  static DocumentReference<Map<String, dynamic>> _profileRef(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('gamification')
        .doc('profile');
  }

  static DocumentReference<Map<String, dynamic>> _dailyRef(
    String uid,
    String date,
  ) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('daily_summary')
        .doc(date);
  }

  static CollectionReference<Map<String, dynamic>> _missionCol(
    String uid,
    String date,
  ) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('daily_missions')
        .doc(date)
        .collection('items');
  }

  static CollectionReference<Map<String, dynamic>> _achievementsCol(
    String uid,
  ) {
    return _db.collection('users').doc(uid).collection('achievements');
  }

  /// Safe initializer.
  /// IMPORTANT: this never resets XP/level/streak after the profile exists.
  static Future<void> ensureTodayReady() async {
    final uid = _uid;
    if (uid == null) return;
    final today = dateKey();

    final profileRef = _profileRef(uid);
    final profileSnap = await profileRef.get();
    if (!profileSnap.exists) {
      await profileRef.set({
        'xp': 0,
        'level': 1,
        'streak': 0,
        'lastActiveDate': '',
        'healthScore': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await profileRef.set({
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    final dailyRef = _dailyRef(uid, today);
    final dailySnap = await dailyRef.get();
    if (!dailySnap.exists) {
      await dailyRef.set({
        'date': today,
        'waterLiters': 0.0,
        'waterGoal': 3.0,
        'steps': 0,
        'stepGoal': 8000,
        'calories': 0.0,
        'protein': 0.0,
        'healthScore': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final missions = MissionService.defaultMissions();
    for (final entry in missions.entries) {
      final ref = _missionCol(uid, today).doc(entry.key);
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set(entry.value);
      }
    }

    await _seedAchievements(uid);
  }

  static Future<void> _seedAchievements(String uid) async {
    final defaults = {
      'first_meal': {
        'title': 'First Meal',
        'subtitle': 'Logged your first meal',
        'icon': '🥗',
        'unlocked': false,
      },
      'hydration_king': {
        'title': 'Hydration Hero',
        'subtitle': 'Reached water target',
        'icon': '💧',
        'unlocked': false,
      },
      'step_hero': {
        'title': 'Step Hero',
        'subtitle': 'Reached step target',
        'icon': '🔥',
        'unlocked': false,
      },
      'protein_master': {
        'title': 'Protein Master',
        'subtitle': 'Reached protein target',
        'icon': '🏆',
        'unlocked': false,
      },
      'ai_explorer': {
        'title': 'AI Explorer',
        'subtitle': 'Used AI coach',
        'icon': '🤖',
        'unlocked': false,
      },
      'barcode_pro': {
        'title': 'Barcode Pro',
        'subtitle': 'Scanned packaged food',
        'icon': '📦',
        'unlocked': false,
      },
      'streak_3': {
        'title': '3-Day Streak',
        'subtitle': 'Built early momentum',
        'icon': '⚡',
        'unlocked': false,
      },
      'streak_7': {
        'title': '7-Day Streak',
        'subtitle': 'One full week consistent',
        'icon': '🔥',
        'unlocked': false,
      },
    };

    for (final entry in defaults.entries) {
      final ref = _achievementsCol(uid).doc(entry.key);
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set(entry.value);
      }
    }
  }

  /// Adds XP without resetting previous XP.
  /// Uses a transaction so multiple rewards cannot overwrite each other.
  static Future<Map<String, dynamic>> rewardAction({
    required String action,
    int? xp,
    String? badgeId,
    bool oncePerDay = true,
  }) async {
    final uid = _uid;
    if (uid == null) return {'awardedXp': 0, 'levelUp': false};
    await ensureTodayReady();

    final today = dateKey();
    final rewardKey = 'rewarded_$action';
    final dailyRef = _dailyRef(uid, today);
    final profileRef = _profileRef(uid);
    final userRef = _db.collection('users').doc(uid);
    final awardedXp = xp ?? XpService.actionXp[action] ?? 5;

    late Map<String, dynamic> result;

    await _db.runTransaction((transaction) async {
      final dailySnap = await transaction.get(dailyRef);
      final dailyData = dailySnap.data() ?? {};

      if (oncePerDay && dailyData[rewardKey] == true) {
        result = {'awardedXp': 0, 'levelUp': false};
        return;
      }

      final profileSnap = await transaction.get(profileRef);
      final profile = GamificationProfile.fromMap(profileSnap.data());
      final newXp = profile.xp + awardedXp;
      final newLevel = XpRules.levelForXp(newXp);
      final levelUp = newLevel > profile.level;

      final newStreak = StreakService.nextStreak(
        lastActiveDate: profile.lastActiveDate,
        currentStreak: profile.streak,
      );

      transaction.set(profileRef, {
        'xp': newXp,
        'level': newLevel,
        'streak': newStreak,
        'lastActiveDate': today,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Mirror the exact same XP to the user root document too.
      // Progress reads /users/{uid}/gamification/profile, while Community Rank
      // can read /users and /leaderboards. Keeping these fields in sync makes
      // Profile Progress XP and Community Rank XP always match.
      transaction.set(userRef, {
        'xp': newXp,
        'totalXp': newXp,
        'level': newLevel,
        'streak': newStreak,
        'gamification': {
          'xp': newXp,
          'totalXp': newXp,
          'level': newLevel,
          'streak': newStreak,
        },
        'leaderboard': {
          'xp': newXp,
          'totalXp': newXp,
          'level': newLevel,
          'streak': newStreak,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(dailyRef, {
        rewardKey: true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      result = {
        'awardedXp': awardedXp,
        'levelUp': levelUp,
        'level': newLevel,
        'streak': newStreak,
      };
    });

    if ((result['awardedXp'] ?? 0) > 0) {
      if (badgeId != null) await unlockAchievement(badgeId);

      final streak = (result['streak'] is num)
          ? (result['streak'] as num).toInt()
          : 0;

      if (streak >= 3) await unlockAchievement('streak_3');
      if (streak >= 7) await unlockAchievement('streak_7');

      _emitReward(action: action, result: result);
      await _syncLeaderboardAfterReward(uid: uid, today: today);
    }

    return result;
  }

  static Future<void> _syncLeaderboardAfterReward({
    required String uid,
    required String today,
  }) async {
    try {
      final profileSnap = await _profileRef(uid).get();
      final profileData = profileSnap.data() ?? {};

      final dailySnap = await _dailyRef(uid, today).get();
      final dailyData = dailySnap.data() ?? {};

      final userRef = _db.collection('users').doc(uid);
      final userSnap = await userRef.get();
      final userData = userSnap.data() ?? {};

      final xp = _asInt(profileData['xp']);
      final level = _asInt(
        profileData['level'],
        fallback: XpRules.levelForXp(xp),
      );
      final streak = _asInt(profileData['streak']);
      final steps = _asInt(dailyData['steps']);
      final calories = _asDouble(dailyData['calories']).toInt();

      final waterGoal = _asDouble(dailyData['waterGoal'], fallback: 3.0);

      final waterLiters = _asDouble(dailyData['waterLiters']);

      final waterConsistency = waterGoal <= 0
          ? 0.0
          : (waterLiters / waterGoal).clamp(0.0, 1.0).toDouble();

      // Keep the root user document in sync with the gamification profile.
      // Community leaderboard can read this root document immediately.
      await userRef.set({
        'xp': xp,
        'totalXp': xp,
        'level': level,
        'streak': streak,
        'gamification': {
          'xp': xp,
          'totalXp': xp,
          'level': level,
          'streak': streak,
        },
        'leaderboard': {
          'xp': xp,
          'totalXp': xp,
          'level': level,
          'streak': streak,
          'steps': steps,
          'caloriesTracked': calories,
          'waterConsistency': waterConsistency,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final leaderboardPayload = <String, dynamic>{
        'uid': uid,
        'name':
            userData['name'] ??
            userData['username'] ??
            userData['displayName'] ??
            userData['fullName'] ??
            'NutriPulse User',
        'xp': xp,
        'totalXp': xp,
        'level': level,
        'streak': streak,
        'steps': steps,
        'caloriesTracked': calories,
        'waterConsistency': waterConsistency,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final batch = _db.batch();
      for (final boardId in const ['global', 'xp', 'main', 'default']) {
        batch.set(
          _db
              .collection('leaderboards')
              .doc(boardId)
              .collection('users')
              .doc(uid),
          leaderboardPayload,
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      await LeaderboardService.syncMyLeaderboard(
        xp: xp,
        steps: steps,
        streak: streak,
        caloriesTracked: calories,
        waterConsistency: waterConsistency,
      );
    } catch (_) {
      // Leaderboard sync must never break XP reward flow.
    }
  }

  /// Call this when opening Progress or Community Rank.
  /// It backfills old accounts so every screen reads the same XP value.
  static Future<void> syncMyProgressToLeaderboard() async {
    final uid = _uid;
    if (uid == null) return;
    await ensureTodayReady();
    await _syncLeaderboardAfterReward(uid: uid, today: dateKey());
  }

  static Future<void> unlockAchievement(String badgeId) async {
    final uid = _uid;
    if (uid == null) return;
    await ensureTodayReady();
    await _achievementsCol(uid).doc(badgeId).set({
      'unlocked': true,
      'unlockedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<Map<String, dynamic>> completeMission(String missionId) async {
    final uid = _uid;
    if (uid == null) return {'awardedXp': 0, 'levelUp': false};
    final today = dateKey();
    await ensureTodayReady();

    final ref = _missionCol(uid, today).doc(missionId);
    final snap = await ref.get();
    final data = snap.data() ?? {};
    if (data['done'] == true) return {'awardedXp': 0, 'levelUp': false};

    await ref.set({
      'done': true,
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return rewardAction(
      action: 'mission_$missionId',
      xp: (data['xpReward'] is num) ? (data['xpReward'] as num).toInt() : 20,
      oncePerDay: true,
    );
  }

  static Future<Map<String, dynamic>> updateWater({
    required double liters,
    double waterGoal = 3.0,
  }) async {
    final uid = _uid;
    if (uid == null) return {'awardedXp': 0, 'levelUp': false};
    await ensureTodayReady();
    final today = dateKey();

    await _dailyRef(uid, today).set({
      'waterLiters': liters,
      'waterGoal': waterGoal,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db.collection('users').doc(uid).set({
      'waterLiters': liters,
      'waterGoal': waterGoal,
    }, SetOptions(merge: true));

    Map<String, dynamic> reward = {'awardedXp': 0, 'levelUp': false};
    if (liters >= waterGoal) {
      reward = await completeMission('water_goal');
      await rewardAction(action: 'water_goal', badgeId: 'hydration_king');
    }
    await recalculateHealthScore();
    return reward;
  }

  static Future<Map<String, dynamic>> updateSteps({
    required int steps,
    int stepGoal = 8000,
  }) async {
    final uid = _uid;
    if (uid == null) return {'awardedXp': 0, 'levelUp': false};
    await ensureTodayReady();
    final today = dateKey();

    await _dailyRef(uid, today).set({
      'steps': steps,
      'stepGoal': stepGoal,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    Map<String, dynamic> reward = {'awardedXp': 0, 'levelUp': false};
    if (steps >= stepGoal) {
      reward = await completeMission('steps_goal');
      await rewardAction(action: 'step_goal', badgeId: 'step_hero');
    }
    await recalculateHealthScore();
    return reward;
  }

  static Future<Map<String, dynamic>> onMealLogged({
    required String method,
    required double calories,
    required double protein,
  }) async {
    final uid = _uid;
    if (uid == null) return {'awardedXp': 0, 'levelUp': false};
    await ensureTodayReady();
    final today = dateKey();

    final dailyRef = _dailyRef(uid, today);
    final snap = await dailyRef.get();
    final data = snap.data() ?? {};
    final totalCalories = _asDouble(data['calories']) + calories;
    final totalProtein = _asDouble(data['protein']) + protein;

    await dailyRef.set({
      'calories': totalCalories,
      'protein': totalProtein,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    var reward = await completeMission('log_meal');
    await rewardAction(
      action: 'food_logged',
      badgeId: 'first_meal',
      oncePerDay: false,
    );

    if (method == 'ai_scan') {
      await rewardAction(action: 'ai_food_scan', oncePerDay: false);
    } else if (method == 'barcode_scan') {
      await rewardAction(
        action: 'barcode_scan',
        badgeId: 'barcode_pro',
        oncePerDay: false,
      );
    } else {
      await rewardAction(action: 'manual_food', oncePerDay: false);
    }

    final userDoc = await _db.collection('users').doc(uid).get();
    final userData = userDoc.data() ?? {};
    final targetProtein = _asDouble(userData['proteinGrams'], fallback: 120);
    if (totalProtein >= targetProtein) {
      reward = await completeMission('protein_goal');
      await rewardAction(action: 'protein_goal', badgeId: 'protein_master');
    }
    await recalculateHealthScore();
    return reward;
  }

  static Future<Map<String, dynamic>> onAiCoachUsed() async {
    return rewardAction(action: 'ai_coach', badgeId: 'ai_explorer');
  }

  static Future<int> recalculateHealthScore() async {
    final uid = _uid;
    if (uid == null) return 0;
    final today = dateKey();
    final daily = (await _dailyRef(uid, today).get()).data() ?? {};
    final userData =
        (await _db.collection('users').doc(uid).get()).data() ?? {};

    final score = HealthScoreService.calculateScore(
      calories: _asDouble(daily['calories']),
      targetCalories: _asDouble(userData['targetCalories'], fallback: 2000),
      protein: _asDouble(daily['protein']),
      targetProtein: _asDouble(userData['proteinGrams'], fallback: 120),
      waterLiters: _asDouble(daily['waterLiters']),
      waterGoal: _asDouble(daily['waterGoal'], fallback: 3),
      steps: _asInt(daily['steps']),
      stepGoal: _asInt(daily['stepGoal'], fallback: 8000),
    );

    await _dailyRef(uid, today).set({
      'healthScore': score,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _profileRef(uid).set({
      'healthScore': score,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return score;
  }

  static double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
