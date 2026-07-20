import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

import '../models/activity_record.dart';

class ActivityService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String _dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> recentActivitiesStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    return _db
        .collection('users')
        .doc(uid)
        .collection('activities')
        .orderBy('startedAt', descending: true)
        .limit(20)
        .snapshots();
  }

  static Future<String> saveActivity(ActivityRecord record) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    final userRef = _db.collection('users').doc(uid);
    final activityRef = userRef.collection('activities').doc();
    final payload = _activityPayload(record, uid);

    await _commitActivity(
      activityRef: activityRef,
      userRef: userRef,
      payload: payload,
      record: record,
    );

    return activityRef.id;
  }

  /// Returns an activity id immediately and queues the Firestore write in the
  /// background. This is used by the live tracker so the UI never gets stuck on
  /// "Saving..." when the network is weak. Firestore mobile persistence will
  /// sync the write when the connection is available.
  static String queueActivitySave(ActivityRecord record) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    final userRef = _db.collection('users').doc(uid);
    final activityRef = userRef.collection('activities').doc();
    final payload = _activityPayload(record, uid);

    unawaited(
      _commitActivity(
        activityRef: activityRef,
        userRef: userRef,
        payload: payload,
        record: record,
      ).catchError((_) {
        // Keep the tracker UI non-blocking. The user can still see the summary.
        // Firestore may also complete later from the local pending-write queue.
      }),
    );

    return activityRef.id;
  }

  static Map<String, dynamic> _activityPayload(
    ActivityRecord record,
    String uid,
  ) {
    final routeForSave = compactRouteForSave(
      record.route,
      maxPoints: 80,
      minDistanceMeters: 8,
    );

    return <String, dynamic>{
      'uid': uid,
      'type': record.type,
      'distanceKm': record.distanceKm,
      'durationSeconds': record.durationSeconds,
      'averagePaceSecondsPerKm': record.averagePaceSecondsPerKm,
      'averageSpeedKmh': record.averageSpeedKmh,
      'caloriesBurned': record.caloriesBurned,
      'xpEarned': record.xpEarned,
      'route': _routeToMap(routeForSave),
      'routePointCount': record.route.length,
      'savedRoutePointCount': routeForSave.length,
      'dateKey': _dateKey(record.startedAt),
      'startedAt': Timestamp.fromDate(record.startedAt),
      'endedAt': Timestamp.fromDate(record.endedAt),
      'createdAt': FieldValue.serverTimestamp(),
      'saveMode': 'queued',
    };
  }

  static Future<void> _commitActivity({
    required DocumentReference<Map<String, dynamic>> activityRef,
    required DocumentReference<Map<String, dynamic>> userRef,
    required Map<String, dynamic> payload,
    required ActivityRecord record,
  }) async {
    // Two small writes only. No waiting/timeout is used by queueActivitySave.
    final batch = _db.batch()
      ..set(activityRef, payload)
      ..set(userRef, {
        'lastActivityAt': FieldValue.serverTimestamp(),
        'activityStats': {
          'lastDistanceKm': record.distanceKm,
          'lastCaloriesBurned': record.caloriesBurned,
          'lastXpEarned': record.xpEarned,
        },
        'xp': FieldValue.increment(record.xpEarned),
      }, SetOptions(merge: true));

    await batch.commit();
  }

  static List<Map<String, double>> _routeToMap(List<LatLng> route) {
    return route
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList(growable: false);
  }

  static List<LatLng> compactRouteForSave(
    List<LatLng> route, {
    int maxPoints = 80,
    double minDistanceMeters = 8,
  }) {
    if (route.length <= 2) return List<LatLng>.from(route);

    final distance = const Distance();
    final filtered = <LatLng>[route.first];

    for (var i = 1; i < route.length - 1; i++) {
      final point = route[i];
      if (distance(filtered.last, point) >= minDistanceMeters) {
        filtered.add(point);
      }
    }

    if (filtered.last != route.last) filtered.add(route.last);
    if (filtered.length <= maxPoints) return filtered;

    final sampled = <LatLng>[filtered.first];
    final step = (filtered.length - 1) / (maxPoints - 1);

    for (var i = 1; i < maxPoints - 1; i++) {
      final index = (i * step).round().clamp(1, filtered.length - 2).toInt();
      sampled.add(filtered[index]);
    }

    sampled.add(filtered.last);
    return sampled;
  }

  static int estimateCalories({
    required double distanceKm,
    required int durationSeconds,
    double weightKg = 70,
  }) {
    final durationHours = durationSeconds / 3600.0;
    if (durationHours <= 0) return 0;
    final speedKmh = distanceKm / durationHours;
    final met = speedKmh >= 9
        ? 9.8
        : speedKmh >= 7
        ? 8.3
        : speedKmh >= 5
        ? 5.0
        : 3.5;
    return (met * weightKg * durationHours).round().clamp(0, 5000);
  }

  static int calculateXp(double distanceKm, int durationSeconds) {
    final distanceXp = (distanceKm * 10).round();
    final durationXp = (durationSeconds / 300).round();
    return (distanceXp + durationXp).clamp(5, 250);
  }

  static int paceSecondsPerKm(double distanceKm, int durationSeconds) {
    if (distanceKm <= 0) return 0;
    return (durationSeconds / distanceKm).round();
  }

  static double averageSpeedKmh(double distanceKm, int durationSeconds) {
    if (durationSeconds <= 0) return 0;
    return distanceKm / (durationSeconds / 3600.0);
  }

  static double routeDistanceKm(List<LatLng> route) {
    if (route.length < 2) return 0;
    final distance = const Distance();
    double meters = 0;
    for (var i = 1; i < route.length; i++) {
      meters += distance(route[i - 1], route[i]);
    }
    return meters / 1000.0;
  }
}
