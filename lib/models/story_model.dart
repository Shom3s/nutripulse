import 'package:cloud_firestore/cloud_firestore.dart';

class StoryModel {
  final String id;
  final String uid;
  final String username;
  final String userImageBase64;
  final String imageBase64;
  final String caption;
  final String type;
  final int viewsCount;
  final int reactionsCount;
  final List<String> viewedBy;
  final DateTime createdAt;
  final DateTime expiresAt;

  const StoryModel({
    required this.id,
    required this.uid,
    required this.username,
    required this.userImageBase64,
    required this.imageBase64,
    required this.caption,
    required this.type,
    required this.viewsCount,
    required this.reactionsCount,
    required this.viewedBy,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired {
    final now = DateTime.now();
    return now.isAtSameMomentAs(expiresAt) || now.isAfter(expiresAt);
  }

  bool viewedByUser(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return viewedBy.contains(uid);
  }

  factory StoryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawCreated = data['createdAt'];
    final rawExpires = data['expiresAt'];
    final rawViewedBy = data['viewedBy'];

    final createdAt = rawCreated is Timestamp
        ? rawCreated.toDate()
        : DateTime.now();

    final expiresAt = rawExpires is Timestamp
        ? rawExpires.toDate()
        : createdAt.add(const Duration(hours: 24));

    final viewedBy = rawViewedBy is List
        ? rawViewedBy.map((e) => e.toString()).toList()
        : <String>[];

    return StoryModel(
      id: doc.id,
      uid: (data['uid'] ?? '').toString(),
      username: (data['username'] ?? 'User').toString(),
      userImageBase64: (data['userImageBase64'] ?? '').toString(),
      imageBase64: (data['imageBase64'] ?? '').toString(),
      caption: (data['caption'] ?? '').toString(),
      type: (data['type'] ?? 'status').toString(),
      viewsCount: _safeInt(data['viewsCount']),
      reactionsCount: _safeInt(data['reactionsCount']),
      viewedBy: viewedBy,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  static int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
