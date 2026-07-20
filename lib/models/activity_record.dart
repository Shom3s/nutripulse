import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class ActivityRecord {
  final String id;
  final String uid;
  final String type;
  final double distanceKm;
  final int durationSeconds;
  final int averagePaceSecondsPerKm;
  final double averageSpeedKmh;
  final int caloriesBurned;
  final int xpEarned;
  final List<LatLng> route;
  final DateTime startedAt;
  final DateTime endedAt;

  const ActivityRecord({
    required this.id,
    required this.uid,
    required this.type,
    required this.distanceKm,
    required this.durationSeconds,
    required this.averagePaceSecondsPerKm,
    required this.averageSpeedKmh,
    required this.caloriesBurned,
    required this.xpEarned,
    required this.route,
    required this.startedAt,
    required this.endedAt,
  });

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'type': type,
    'distanceKm': distanceKm,
    'durationSeconds': durationSeconds,
    'averagePaceSecondsPerKm': averagePaceSecondsPerKm,
    'averageSpeedKmh': averageSpeedKmh,
    'caloriesBurned': caloriesBurned,
    'xpEarned': xpEarned,
    'route': route.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    'startedAt': Timestamp.fromDate(startedAt),
    'endedAt': Timestamp.fromDate(endedAt),
    'createdAt': FieldValue.serverTimestamp(),
  };

  factory ActivityRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final points = <LatLng>[];
    final rawRoute = data['route'];
    if (rawRoute is List) {
      for (final item in rawRoute) {
        if (item is Map) {
          final lat = _safeDouble(item['lat']);
          final lng = _safeDouble(item['lng']);
          if (lat != 0 || lng != 0) points.add(LatLng(lat, lng));
        }
      }
    }
    return ActivityRecord(
      id: doc.id,
      uid: (data['uid'] ?? '').toString(),
      type: (data['type'] ?? 'run').toString(),
      distanceKm: _safeDouble(data['distanceKm']),
      durationSeconds: _safeInt(data['durationSeconds']),
      averagePaceSecondsPerKm: _safeInt(data['averagePaceSecondsPerKm']),
      averageSpeedKmh: _safeDouble(data['averageSpeedKmh']),
      caloriesBurned: _safeInt(data['caloriesBurned']),
      xpEarned: _safeInt(data['xpEarned']),
      route: points,
      startedAt: _dateFrom(data['startedAt']),
      endedAt: _dateFrom(data['endedAt']),
    );
  }

  static DateTime _dateFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  static int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _safeDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
