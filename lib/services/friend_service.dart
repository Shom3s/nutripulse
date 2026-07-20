import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String get currentUid => _auth.currentUser!.uid;

  static Stream<QuerySnapshot<Map<String, dynamic>>> usersStream() {
    return _db.collection('users').limit(80).snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> userProfileStream(
    String uid,
  ) {
    return _db.collection('users').doc(uid).snapshots();
  }

  static Future<Map<String, dynamic>> getProfileBundle(String uid) async {
    final today = _dateKey(DateTime.now());

    final userDoc = await _db.collection('users').doc(uid).get();

    final gamificationDoc = await _db
        .collection('users')
        .doc(uid)
        .collection('gamification')
        .doc('profile')
        .get();

    final dailyDoc = await _db
        .collection('users')
        .doc(uid)
        .collection('daily_summary')
        .doc(today)
        .get();

    final activityDoc = await _db
        .collection('users')
        .doc(uid)
        .collection('activity')
        .doc(today)
        .get();

    final mealsDoc = await _db
        .collection('users')
        .doc(uid)
        .collection('meals')
        .doc(today)
        .get();

    return {
      'user': userDoc.data() ?? {},
      'gamification': gamificationDoc.data() ?? {},
      'daily': dailyDoc.data() ?? {},
      'activity': activityDoc.data() ?? {},
      'meals': mealsDoc.data() ?? {},
    };
  }

  static int safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double safeDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> incomingRequestsStream() {
    return _db
        .collection('friend_requests')
        .where('toUid', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> followingStream() {
    return _db
        .collection('users')
        .doc(currentUid)
        .collection('following')
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> followersStream() {
    return _db
        .collection('users')
        .doc(currentUid)
        .collection('followers')
        .snapshots();
  }

  static Stream<bool> isFollowingStream(String otherUid) {
    return _db
        .collection('users')
        .doc(currentUid)
        .collection('following')
        .doc(otherUid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  static Future<void> followUser({
    required String otherUid,
    required String otherName,
    String otherPhoto = '',
  }) async {
    if (otherUid == currentUid) return;

    final me = await _db.collection('users').doc(currentUid).get();
    final meData = me.data() ?? {};
    final myName =
        (meData['name'] ?? _auth.currentUser?.displayName ?? 'NutriPulse User')
            .toString();
    final myPhoto = (meData['photoBase64'] ?? '').toString();

    final batch = _db.batch();

    batch.set(
      _db
          .collection('users')
          .doc(currentUid)
          .collection('following')
          .doc(otherUid),
      {
        'uid': otherUid,
        'name': otherName,
        'photoBase64': otherPhoto,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    batch.set(
      _db
          .collection('users')
          .doc(otherUid)
          .collection('followers')
          .doc(currentUid),
      {
        'uid': currentUid,
        'name': myName,
        'photoBase64': myPhoto,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    await batch.commit();
  }

  static Future<void> sendFriendRequest({
    required String toUid,
    required String toName,
  }) async {
    if (toUid == currentUid) return;

    final me = await _db.collection('users').doc(currentUid).get();
    final meData = me.data() ?? {};
    final myName =
        (meData['name'] ?? _auth.currentUser?.displayName ?? 'NutriPulse User')
            .toString();
    final myPhoto = (meData['photoBase64'] ?? '').toString();

    final existing = await _db
        .collection('friend_requests')
        .where('fromUid', isEqualTo: currentUid)
        .where('toUid', isEqualTo: toUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return;

    await _db.collection('friend_requests').add({
      'fromUid': currentUid,
      'fromName': myName,
      'fromPhotoBase64': myPhoto,
      'toUid': toUid,
      'toName': toName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> acceptRequest(
    String requestId,
    Map<String, dynamic> data,
  ) async {
    final fromUid = data['fromUid']?.toString() ?? '';
    final fromName = data['fromName']?.toString() ?? 'Friend';
    final fromPhoto = data['fromPhotoBase64']?.toString() ?? '';
    if (fromUid.isEmpty) return;

    final me = await _db.collection('users').doc(currentUid).get();
    final meData = me.data() ?? {};
    final myName =
        (meData['name'] ?? _auth.currentUser?.displayName ?? 'NutriPulse User')
            .toString();
    final myPhoto = (meData['photoBase64'] ?? '').toString();

    final batch = _db.batch();

    final requestRef = _db.collection('friend_requests').doc(requestId);
    batch.update(requestRef, {
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(
      _db
          .collection('users')
          .doc(currentUid)
          .collection('followers')
          .doc(fromUid),
      {
        'uid': fromUid,
        'name': fromName,
        'photoBase64': fromPhoto,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    batch.set(
      _db
          .collection('users')
          .doc(fromUid)
          .collection('following')
          .doc(currentUid),
      {
        'uid': currentUid,
        'name': myName,
        'photoBase64': myPhoto,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    batch.set(
      _db
          .collection('users')
          .doc(currentUid)
          .collection('following')
          .doc(fromUid),
      {
        'uid': fromUid,
        'name': fromName,
        'photoBase64': fromPhoto,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    batch.set(
      _db
          .collection('users')
          .doc(fromUid)
          .collection('followers')
          .doc(currentUid),
      {
        'uid': currentUid,
        'name': myName,
        'photoBase64': myPhoto,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    await batch.commit();
  }

  static Future<void> rejectRequest(String requestId) async {
    await _db.collection('friend_requests').doc(requestId).update({
      'status': 'rejected',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> unfollow(String otherUid) async {
    await _db
        .collection('users')
        .doc(currentUid)
        .collection('following')
        .doc(otherUid)
        .delete();
  }

  static Future<void> toggleFollow({
    required String otherUid,
    required String otherName,
    String otherPhoto = '',
  }) async {
    if (otherUid == currentUid) return;

    final doc = await _db
        .collection('users')
        .doc(currentUid)
        .collection('following')
        .doc(otherUid)
        .get();

    if (doc.exists) {
      await unfollow(otherUid);
    } else {
      await followUser(
        otherUid: otherUid,
        otherName: otherName,
        otherPhoto: otherPhoto,
      );
    }
  }

  static Future<Map<String, dynamic>> getUserStats(String uid) async {
    final user = await _db.collection('users').doc(uid).get();
    final data = user.data() ?? {};

    final today = DateTime.now();
    final key =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final activity = await _db
        .collection('users')
        .doc(uid)
        .collection('activity')
        .doc(key)
        .get();
    final meals = await _db
        .collection('users')
        .doc(uid)
        .collection('meals')
        .doc(key)
        .get();
    final gamification = await _db
        .collection('users')
        .doc(uid)
        .collection('gamification')
        .doc('profile')
        .get();

    return {
      'user': data,
      'steps': activity.data()?['steps'] ?? 0,
      'calories': meals.data()?['calories'] ?? 0,
      'streak':
          gamification.data()?['streak'] ??
          gamification.data()?['dayStreak'] ??
          0,
      'xp': gamification.data()?['xp'] ?? 0,
    };
  }
}
