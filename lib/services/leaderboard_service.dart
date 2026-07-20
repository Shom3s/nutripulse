import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LeaderboardService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Stream<QuerySnapshot<Map<String, dynamic>>> globalLeaderboardStream() {
    return _db
        .collection('leaderboards')
        .doc('global')
        .collection('users')
        .orderBy('xp', descending: true)
        .limit(50)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> groupLeaderboardStream(
    String groupId,
  ) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('leaderboard')
        .orderBy('xp', descending: true)
        .limit(50)
        .snapshots();
  }

  /// Call this when opening the leaderboard.
  /// It copies the current user's existing XP/streak/steps/calories/water data
  /// into leaderboards/global/users/{uid}.
  static Future<void> syncCurrentUserNow({String? groupId}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final today = _dateKey(DateTime.now());

    final userDoc = await _db.collection('users').doc(uid).get();
    final userData = userDoc.data() ?? {};

    final gamificationDoc = await _db
        .collection('users')
        .doc(uid)
        .collection('gamification')
        .doc('profile')
        .get();

    final gamification = gamificationDoc.data() ?? {};

    final dailyDoc = await _db
        .collection('users')
        .doc(uid)
        .collection('daily_summary')
        .doc(today)
        .get();

    final daily = dailyDoc.data() ?? {};

    final activityDoc = await _db
        .collection('users')
        .doc(uid)
        .collection('activity')
        .doc(today)
        .get();

    final activity = activityDoc.data() ?? {};

    final mealsDoc = await _db
        .collection('users')
        .doc(uid)
        .collection('meals')
        .doc(today)
        .get();

    final meals = mealsDoc.data() ?? {};

    final xp = _asInt(gamification['xp']);
    final streak = _asInt(gamification['streak']);

    final steps = _asInt(daily['steps'], fallback: _asInt(activity['steps']));

    final calories = _asDouble(
      daily['calories'],
      fallback: _asDouble(meals['calories']),
    ).toInt();

    final waterGoal = _asDouble(
      daily['waterGoal'],
      fallback: _asDouble(userData['waterGoal'], fallback: 3.0),
    );

    final waterLiters = _asDouble(
      daily['waterLiters'],
      fallback: _asDouble(userData['waterLiters']),
    );

    final waterConsistency = waterGoal <= 0
        ? 0.0
        : (waterLiters / waterGoal).clamp(0.0, 1.0).toDouble();

    await syncMyLeaderboard(
      groupId: groupId,
      xp: xp,
      steps: steps,
      streak: streak,
      caloriesTracked: calories,
      waterConsistency: waterConsistency,
    );
  }

  static Future<void> syncMyLeaderboard({
    String? groupId,
    int? xp,
    int? steps,
    int? streak,
    int? caloriesTracked,
    double? waterConsistency,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _db.collection('users').doc(user.uid).get();
    final data = doc.data() ?? {};

    final name = (data['name'] ?? user.displayName ?? 'NutriPulse User')
        .toString();

    final photo = (data['photoBase64'] ?? '').toString();

    final payload = {
      'uid': user.uid,
      'name': name,
      'photoBase64': photo,
      'xp': xp ?? 0,
      'steps': steps ?? 0,
      'streak': streak ?? 0,
      'caloriesTracked': caloriesTracked ?? 0,
      'waterConsistency': waterConsistency ?? 0,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _db
        .collection('leaderboards')
        .doc('global')
        .collection('users')
        .doc(user.uid)
        .set(payload, SetOptions(merge: true));

    if (groupId != null) {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('leaderboard')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));
    }
  }

  static String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
