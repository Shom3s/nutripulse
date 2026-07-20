import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityPost {
  final String id;
  final String uid;
  final String username;
  final String userImageBase64;
  final String type;
  final String caption;
  final String imageBase64;
  final int likesCount;
  final int commentsCount;
  final int xp;
  final int calories;
  final int steps;
  final String mealName;
  final String achievementTitle;
  final DateTime createdAt;

  const CommunityPost({
    required this.id,
    required this.uid,
    required this.username,
    required this.userImageBase64,
    required this.type,
    required this.caption,
    required this.imageBase64,
    required this.likesCount,
    required this.commentsCount,
    required this.xp,
    required this.calories,
    required this.steps,
    required this.mealName,
    required this.achievementTitle,
    required this.createdAt,
  });

  factory CommunityPost.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawDate = data['createdAt'];

    DateTime created;
    if (rawDate is Timestamp) {
      created = rawDate.toDate();
    } else {
      created = DateTime.now();
    }

    return CommunityPost(
      id: doc.id,
      uid: (data['uid'] ?? '').toString(),
      username: (data['username'] ?? 'NutriPulse User').toString(),
      userImageBase64: (data['userImageBase64'] ?? '').toString(),
      type: (data['type'] ?? 'general').toString(),
      caption: (data['caption'] ?? '').toString(),
      imageBase64: (data['imageBase64'] ?? '').toString(),
      likesCount: _safeInt(data['likesCount']),
      commentsCount: _safeInt(data['commentsCount']),
      xp: _safeInt(data['xp']),
      calories: _safeInt(data['calories']),
      steps: _safeInt(data['steps']),
      mealName: (data['mealName'] ?? '').toString(),
      achievementTitle: (data['achievementTitle'] ?? '').toString(),
      createdAt: created,
    );
  }

  static int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
