import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CommunityService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Stream<QuerySnapshot<Map<String, dynamic>>> postsStream() {
    return _db
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> userPostsStream(
    String uid,
  ) {
    return _db
        .collection('posts')
        .where('uid', isEqualTo: uid)
        .limit(80)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>>
  followingFeedStream() async* {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      yield* const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
      return;
    }

    final followingSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('following')
        .get();

    final followingIds = followingSnap.docs.map((e) => e.id).toList();
    if (!followingIds.contains(uid)) followingIds.add(uid);

    if (followingIds.isEmpty) {
      yield* const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
      return;
    }

    // No orderBy here:
    // whereIn(uid) + orderBy(createdAt) needs a Firestore composite index.
    // We sort newest-to-oldest inside community_screen.dart instead.
    yield* _db
        .collection('posts')
        .where('uid', whereIn: followingIds.take(10).toList())
        .limit(80)
        .snapshots();
  }

  static Future<bool> isPostLiked(String postId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    final postRef = _db.collection('posts').doc(postId);
    final doc = await postRef.collection('likes').doc(uid).get();

    if (doc.exists) return true;

    // Fallback for posts created/liked by older versions that used a likedBy
    // array on the post document. The likes subcollection is still the main
    // source of truth.
    final postSnap = await postRef.get();
    final postData = postSnap.data() ?? {};
    final likedBy = List<String>.from(postData['likedBy'] ?? const <String>[]);
    return likedBy.contains(uid);
  }

  static Stream<bool> isPostLikedStream(String postId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream<bool>.value(false);

    final postRef = _db.collection('posts').doc(postId);
    final likeRef = postRef.collection('likes').doc(uid);

    return likeRef.snapshots().asyncMap((doc) async {
      if (doc.exists) return true;

      // Fallback for older writes that may only have likedBy on the post doc.
      final postSnap = await postRef.get();
      final postData = postSnap.data() ?? {};
      final likedBy = List<String>.from(
        postData['likedBy'] ?? const <String>[],
      );
      return likedBy.contains(uid);
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> commentsStream(
    String postId,
  ) {
    return _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
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

  static Future<void> _createUserNotification({
    required String ownerUid,
    required String type,
    required String title,
    required String body,
    required String actorUid,
    required String actorName,
    String actorImageBase64 = '',
    String postId = '',
    String commentText = '',
  }) async {
    if (ownerUid.isEmpty || ownerUid == actorUid) return;

    String notificationId;

    if (type == 'like') {
      notificationId = 'post_${postId}_like_$actorUid';
    } else {
      notificationId =
          '${type}_${DateTime.now().millisecondsSinceEpoch}_$actorUid';
    }

    await _db
        .collection('users')
        .doc(ownerUid)
        .collection('notifications')
        .doc(notificationId)
        .set({
          'type': type,
          'title': title,
          'body': body,
          'actorUid': actorUid,
          'actorName': actorName,
          'actorImageBase64': actorImageBase64,
          // Firestore rules need senderId + receiverId when another user creates
          // a notification inside the owner's notification center.
          'senderId': actorUid,
          'receiverId': ownerUid,
          'postId': postId,
          'commentText': commentText,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
          'screen': 'community',
        }, SetOptions(merge: true));
  }

  static bool _safeBool(dynamic value, {bool fallback = true}) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return fallback;
  }

  static Future<void> createStoryReactionNotification({
    required String storyOwnerUid,
    required String storyId,
    required String reaction,
  }) async {
    final profile = await _currentUserProfile();
    final ownerUid = storyOwnerUid.trim();

    if (ownerUid.isEmpty || ownerUid == profile['uid']) return;

    // Respect the receiver's App Settings. If the field does not exist yet,
    // notifications stay enabled by default so old users still receive them.
    try {
      final ownerDoc = await _db.collection('users').doc(ownerUid).get();
      final ownerData = ownerDoc.data() ?? {};
      final privacy = ownerData['privacy'];
      final notificationSettings = ownerData['notificationSettings'];

      final storyReactionEnabled = _safeBool(
        privacy is Map ? privacy['storyReactionNotifications'] : null,
      );
      final communityPushEnabled = _safeBool(
        notificationSettings is Map
            ? notificationSettings['communityPush']
            : null,
      );

      if (!storyReactionEnabled || !communityPushEnabled) return;
    } catch (_) {
      // If settings cannot be read, continue and create the notification.
      // The reaction should not fail only because settings read failed.
    }

    await _db
        .collection('users')
        .doc(ownerUid)
        .collection('notifications')
        .doc('story_${storyId}_reaction_${profile['uid']}')
        .set({
          'type': 'story_reaction',
          'title': '${profile['username']} reacted to your story',
          'body': '${profile['username']} reacted $reaction to your story.',
          'actorUid': profile['uid'],
          'actorName': profile['username'],
          'actorImageBase64': profile['userImageBase64'],
          // Firestore rules need senderId + receiverId when another user creates
          // a notification inside the owner's notification center.
          'senderId': profile['uid'],
          'receiverId': ownerUid,
          'storyId': storyId,
          'reaction': reaction,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
          'screen': 'story',
        }, SetOptions(merge: true));
  }

  static Future<String> fileToBase64(File file) async {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  static Future<void> createPost({
    required String type,
    required String caption,
    String imageBase64 = '',
    int xp = 0,
    int calories = 0,
    int steps = 0,
    String mealName = '',
    String achievementTitle = '',
  }) async {
    final profile = await _currentUserProfile();

    await _db.collection('posts').add({
      'uid': profile['uid'],
      'username': profile['username'],
      'userImageBase64': profile['userImageBase64'],
      'type': type,
      'caption': caption.trim(),
      'imageBase64': imageBase64,
      'xp': xp,
      'calories': calories,
      'steps': steps,
      'mealName': mealName,
      'achievementTitle': achievementTitle,
      'likesCount': 0,
      'likedBy': const <String>[],
      'commentsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> createActivityPost({
    required String caption,
    required String posterBase64,
    required double distanceKm,
    required int durationSeconds,
    required int paceSecondsPerKm,
    required int caloriesBurned,
    required int xp,
    String activityId = '',
  }) async {
    final profile = await _currentUserProfile();

    await _db.collection('posts').add({
      'uid': profile['uid'],
      'username': profile['username'],
      'userImageBase64': profile['userImageBase64'],
      'type': 'activity',
      'caption': caption.trim(),
      'imageBase64': posterBase64,
      'activityId': activityId,
      'distanceKm': distanceKm,
      'durationSeconds': durationSeconds,
      'paceSecondsPerKm': paceSecondsPerKm,
      'caloriesBurned': caloriesBurned,
      'xp': xp,
      'calories': caloriesBurned,
      'steps': 0,
      'mealName': '',
      'achievementTitle': 'Run Tracker',
      'likesCount': 0,
      'likedBy': const <String>[],
      'commentsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> toggleLike(String postId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final profile = await _currentUserProfile();
    final postRef = _db.collection('posts').doc(postId);
    final likeRef = postRef.collection('likes').doc(user.uid);

    bool createdLike = false;
    String ownerUid = '';
    String postCaption = '';

    await _db.runTransaction((transaction) async {
      final postSnap = await transaction.get(postRef);
      final postData = postSnap.data();

      if (postData == null) return;

      ownerUid = (postData['uid'] ?? '').toString();
      postCaption = (postData['caption'] ?? '').toString();

      final likeSnap = await transaction.get(likeRef);

      if (likeSnap.exists) {
        transaction.delete(likeRef);
        transaction.update(postRef, {
          'likesCount': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove([user.uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        createdLike = true;

        transaction.set(likeRef, {
          'uid': user.uid,
          'username': profile['username'],
          'userImageBase64': profile['userImageBase64'],
          'likedAt': FieldValue.serverTimestamp(),
        });

        transaction.update(postRef, {
          'likesCount': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([user.uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    if (createdLike && ownerUid.isNotEmpty && ownerUid != user.uid) {
      await _createUserNotification(
        ownerUid: ownerUid,
        type: 'like',
        title: '${profile['username']} liked your post',
        body: '${profile['username']} liked your post.',
        actorUid: profile['uid'],
        actorName: profile['username'],
        actorImageBase64: profile['userImageBase64'],
        postId: postId,
      );
    } else if (!createdLike && ownerUid.isNotEmpty && ownerUid != user.uid) {
      await _db
          .collection('users')
          .doc(ownerUid)
          .collection('notifications')
          .doc('post_${postId}_like_${user.uid}')
          .delete()
          .catchError((_) {});
    }
  }

  static Future<void> addComment({
    required String postId,
    required String text,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    final profile = await _currentUserProfile();
    final postRef = _db.collection('posts').doc(postId);
    final postSnap = await postRef.get();
    final postData = postSnap.data();

    if (postData == null) return;

    final ownerUid = (postData['uid'] ?? '').toString();

    await postRef.collection('comments').add({
      'uid': profile['uid'],
      'username': profile['username'],
      'userImageBase64': profile['userImageBase64'],
      'text': cleaned,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await postRef.update({'commentsCount': FieldValue.increment(1)});

    if (ownerUid.isNotEmpty && ownerUid != profile['uid']) {
      await _createUserNotification(
        ownerUid: ownerUid,
        type: 'comment',
        title: '${profile['username']} commented on your post',
        body: '${profile['username']}: $cleaned',
        actorUid: profile['uid'],
        actorName: profile['username'],
        actorImageBase64: profile['userImageBase64'],
        postId: postId,
        commentText: cleaned,
      );
    }
  }

  static Future<void> updatePost({
    required String postId,
    required String caption,
    required String type,
    String? imageBase64,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final postRef = _db.collection('posts').doc(postId);
    final post = await postRef.get();
    final data = post.data();

    if (data == null || data['uid'] != uid) {
      throw Exception('You can only edit your own post.');
    }

    final updateData = <String, dynamic>{
      'caption': caption.trim(),
      'type': type,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (imageBase64 != null) {
      updateData['imageBase64'] = imageBase64;
    }

    await postRef.update(updateData);
  }

  static Future<void> deletePost(String postId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final postRef = _db.collection('posts').doc(postId);
    final post = await postRef.get();
    final data = post.data();

    if (data == null || data['uid'] != uid) return;

    await postRef.delete();
  }
}
