import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StoryService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? get currentUid => _auth.currentUser?.uid;

  /// Only returns active stories.
  static Stream<QuerySnapshot<Map<String, dynamic>>> storiesStream() {
    final now = Timestamp.fromDate(DateTime.now());

    return _db
        .collection('stories')
        .where('expiresAt', isGreaterThan: now)
        .orderBy('expiresAt', descending: false)
        .limit(120)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> storyViewsStream(
    String storyId,
  ) {
    return _db
        .collection('stories')
        .doc(storyId)
        .collection('views')
        .orderBy('viewedAt', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> storyReactionsStream(
    String storyId,
  ) {
    return _db
        .collection('stories')
        .doc(storyId)
        .collection('reactions')
        .snapshots();
  }

  static Future<Map<String, dynamic>> _currentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }

    String username = user.displayName ?? 'NutriPulse User';
    String userImageBase64 = '';

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};

      final savedName = (data['name'] ?? '').toString().trim();
      if (savedName.isNotEmpty) username = savedName;

      userImageBase64 = (data['photoBase64'] ?? '').toString();
    } catch (_) {}

    return {
      'uid': user.uid,
      'username': username,
      'userImageBase64': userImageBase64,
    };
  }

  static Future<String> fileToBase64(File file) async {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  static Future<void> createStory({
    required String imageBase64,
    required String caption,
    String type = 'status',
  }) async {
    final profile = await _currentUserProfile();

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    await _db.collection('stories').add({
      'uid': profile['uid'],
      'username': profile['username'],
      'userImageBase64': profile['userImageBase64'],
      'imageBase64': imageBase64,
      'caption': caption.trim(),
      'type': type,
      'viewsCount': 0,
      'reactionsCount': 0,
      'viewedBy': <String>[],
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });
  }

  /// Marks a story as viewed.
  /// Important:
  /// - owner does NOT count as a view
  /// - same viewer only increments once
  /// - viewedBy is used by StoryBar to turn ring grey after opening
  static Future<void> markStoryViewed(String storyId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final storyRef = _db.collection('stories').doc(storyId);
    final viewRef = storyRef.collection('views').doc(user.uid);

    final storySnap = await storyRef.get();
    final storyData = storySnap.data();
    if (storyData == null) return;

    final ownerUid = (storyData['uid'] ?? '').toString();

    // Do not count your own story view.
    if (ownerUid == user.uid) {
      await storyRef.set({
        'viewedBy': FieldValue.arrayUnion([user.uid]),
      }, SetOptions(merge: true));
      return;
    }

    final profile = await _currentUserProfile();

    await _db.runTransaction((transaction) async {
      final viewSnap = await transaction.get(viewRef);

      if (!viewSnap.exists) {
        transaction.set(viewRef, {
          'uid': profile['uid'],
          'username': profile['username'],
          'userImageBase64': profile['userImageBase64'],
          'viewedAt': FieldValue.serverTimestamp(),
        });

        transaction.update(storyRef, {
          'viewsCount': FieldValue.increment(1),
          'viewedBy': FieldValue.arrayUnion([user.uid]),
        });
      } else {
        transaction.set(viewRef, {
          'viewedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.update(storyRef, {
          'viewedBy': FieldValue.arrayUnion([user.uid]),
        });
      }
    });
  }

  /// Reacts to a story.
  /// Important:
  /// - owner cannot react to own story
  /// - one reaction per user, replacing old emoji
  static Future<void> reactToStory({
    required String storyId,
    required String emoji,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final storyRef = _db.collection('stories').doc(storyId);
    final reactionRef = storyRef.collection('reactions').doc(user.uid);

    final storySnap = await storyRef.get();
    final storyData = storySnap.data();
    if (storyData == null) return;

    final ownerUid = (storyData['uid'] ?? '').toString();

    // Do not react to your own story.
    if (ownerUid == user.uid) {
      throw Exception('You cannot react to your own story.');
    }

    final profile = await _currentUserProfile();

    await _db.runTransaction((transaction) async {
      final reactionSnap = await transaction.get(reactionRef);
      final alreadyReacted = reactionSnap.exists;

      transaction.set(reactionRef, {
        'uid': profile['uid'],
        'username': profile['username'],
        'userImageBase64': profile['userImageBase64'],
        'emoji': emoji,
        'reactedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!alreadyReacted) {
        transaction.update(storyRef, {
          'reactionsCount': FieldValue.increment(1),
        });
      }
    });
  }

  static Future<void> cleanupExpiredStories() async {
    final now = Timestamp.fromDate(DateTime.now());

    final expired = await _db
        .collection('stories')
        .where('expiresAt', isLessThanOrEqualTo: now)
        .limit(50)
        .get();

    if (expired.docs.isEmpty) return;

    final batch = _db.batch();

    for (final doc in expired.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }
}
