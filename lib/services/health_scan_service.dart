import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/health_scan_result.dart';

class HealthScanService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>>? _scanCollection() {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('health_scans');
  }

  static Stream<List<HealthScanResult>> recentScansStream({int limit = 12}) {
    final col = _scanCollection();
    if (col == null) return Stream<List<HealthScanResult>>.value([]);

    return col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) => HealthScanResult.fromFirestore(doc))
              .toList();
        });
  }

  static Future<void> saveScan({
    required int bpm,
    required double avgBpm,
    required double minBpm,
    required double maxBpm,
    required double temperature,
    required String status,
    required String recommendation,
    required int durationSeconds,
  }) async {
    final col = _scanCollection();
    if (col == null) throw Exception('User not logged in');

    final now = DateTime.now();

    await col.add({
      'bpm': bpm,
      'avgBpm': avgBpm,
      'minBpm': minBpm,
      'maxBpm': maxBpm,
      'temperature': temperature,
      'status': status,
      'recommendation': recommendation,
      'durationSeconds': durationSeconds,
      'dateKey': dateKey(now),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static String dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String shortDay(DateTime date) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[date.weekday - 1];
  }

  static String formatTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute $suffix';
  }

  static String healthStatus({
    required int? bpm,
    required double? temperature,
  }) {
    if (bpm == null && temperature == null) return 'Waiting';

    final highBpm = bpm != null && bpm > 100;
    final lowBpm = bpm != null && bpm < 60;
    final highTemp = temperature != null && temperature >= 37.6;
    final lowTemp = temperature != null && temperature < 35.5;

    if (highTemp || highBpm) return 'Warning';
    if (lowBpm || lowTemp) return 'Monitor';
    return 'Normal';
  }

  static String recommendation({
    required int? bpm,
    required double? temperature,
  }) {
    if (bpm == null && temperature == null) {
      return 'Start a scan and place your finger on the sensor.';
    }

    if (temperature != null && temperature >= 37.6) {
      return 'Temperature is higher than normal. Rest, hydrate, and scan again.';
    }

    if (bpm != null && bpm > 100) {
      return 'Heart rate is high. Sit still for 5 minutes and scan again.';
    }

    if (bpm != null && bpm < 60) {
      return 'Heart rate is low. Monitor how you feel and scan again later.';
    }

    if (temperature != null && temperature < 35.5) {
      return 'Temperature is low. Warm up and repeat the scan.';
    }

    return 'Your latest reading looks within the normal range.';
  }
}
