import 'package:cloud_firestore/cloud_firestore.dart';

class HealthScanResult {
  final String id;
  final int bpm;
  final double avgBpm;
  final double minBpm;
  final double maxBpm;
  final double temperature;
  final String status;
  final String recommendation;
  final int durationSeconds;
  final String dateKey;
  final DateTime createdAt;

  const HealthScanResult({
    required this.id,
    required this.bpm,
    required this.avgBpm,
    required this.minBpm,
    required this.maxBpm,
    required this.temperature,
    required this.status,
    required this.recommendation,
    required this.durationSeconds,
    required this.dateKey,
    required this.createdAt,
  });

  factory HealthScanResult.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawCreated = data['createdAt'];

    return HealthScanResult(
      id: doc.id,
      bpm: _safeInt(data['bpm']),
      avgBpm: _safeDouble(data['avgBpm']),
      minBpm: _safeDouble(data['minBpm']),
      maxBpm: _safeDouble(data['maxBpm']),
      temperature: _safeDouble(data['temperature']),
      status: (data['status'] ?? 'Unknown').toString(),
      recommendation: (data['recommendation'] ?? '').toString(),
      durationSeconds: _safeInt(data['durationSeconds']),
      dateKey: (data['dateKey'] ?? '').toString(),
      createdAt: rawCreated is Timestamp ? rawCreated.toDate() : DateTime.now(),
    );
  }

  static int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _safeDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
