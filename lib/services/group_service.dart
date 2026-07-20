import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String get currentUid => _auth.currentUser?.uid ?? '';

  static final List<Map<String, dynamic>> defaultGroups = [
    {
      'id': 'weight_loss',
      'name': 'Weight Loss',
      'description': 'Lose fat, build discipline, stay consistent.',
      'icon': '🔥',
    },
    {
      'id': 'muscle_gain',
      'name': 'Muscle Gain',
      'description': 'Protein, workouts, and strength goals.',
      'icon': '💪',
    },
    {
      'id': 'healthy_students',
      'name': 'Healthy Students',
      'description': 'Affordable healthy routines for students.',
      'icon': '🎓',
    },
    {
      'id': 'malaysia_food_lovers',
      'name': 'Malaysia Food Lovers',
      'description': 'Track local food smarter together.',
      'icon': '🍛',
    },
    {
      'id': 'nutripulse_elite',
      'name': 'NutriPulse Elite',
      'description': 'Top streaks, XP and premium challenges.',
      'icon': '⚡',
    },
  ];

  static Future<void> seedDefaultGroups() async {
    final batch = _db.batch();

    for (final group in defaultGroups) {
      final ref = _db.collection('groups').doc(group['id'].toString());

      // Do not reset membersCount here. Existing groups keep their real count.
      batch.set(ref, {
        ...group,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> groupsStream() {
    return _db.collection('groups').orderBy('name').snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> groupPostsStream(
    String groupId,
  ) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> membersStream(
    String groupId,
  ) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .snapshots();
  }

  static Stream<int> membersCountStream(String groupId) {
    return membersStream(groupId).map((snapshot) => snapshot.size);
  }

  static Future<void> repairMembersCount(String groupId) async {
    final members = await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .get();

    await _db.collection('groups').doc(groupId).set({
      'membersCount': members.size,
    }, SetOptions(merge: true));
  }

  static Future<bool> isMember(String groupId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    final doc = await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .get();

    return doc.exists;
  }

  static Stream<bool> isMemberStream(String groupId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream<bool>.value(false);

    return _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  static Stream<bool> isGroupMutedStream(String groupId) {
    final user = _auth.currentUser;
    if (user == null) return Stream<bool>.value(false);

    return _db
        .collection('users')
        .doc(user.uid)
        .collection('mutedGroups')
        .doc(groupId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  static Future<void> setGroupMuted({
    required String groupId,
    required bool muted,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final ref = _db
        .collection('users')
        .doc(user.uid)
        .collection('mutedGroups')
        .doc(groupId);

    if (muted) {
      await ref.set({
        'groupId': groupId,
        'mutedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  static Future<void> joinGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final data = userDoc.data() ?? {};
    final name = (data['name'] ?? user.displayName ?? 'NutriPulse User')
        .toString();
    final photo = (data['photoBase64'] ?? '').toString();

    final groupRef = _db.collection('groups').doc(groupId);
    final memberRef = groupRef.collection('members').doc(user.uid);

    await _db.runTransaction((tx) async {
      final member = await tx.get(memberRef);
      if (!member.exists) {
        tx.set(memberRef, {
          'uid': user.uid,
          'name': name,
          'photoBase64': photo,
          'joinedAt': FieldValue.serverTimestamp(),
        });
        tx.set(groupRef, {
          'membersCount': FieldValue.increment(1),
        }, SetOptions(merge: true));
      }
    });

    await repairMembersCount(groupId);
  }

  static Future<void> leaveGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final groupRef = _db.collection('groups').doc(groupId);
    final memberRef = groupRef.collection('members').doc(user.uid);
    final mutedRef = _db
        .collection('users')
        .doc(user.uid)
        .collection('mutedGroups')
        .doc(groupId);

    await _db.runTransaction((tx) async {
      final member = await tx.get(memberRef);

      if (member.exists) {
        tx.delete(memberRef);
        tx.set(groupRef, {
          'membersCount': FieldValue.increment(-1),
        }, SetOptions(merge: true));
      }

      tx.delete(mutedRef);
    });

    await repairMembersCount(groupId);
  }

  static Future<void> createGroupPost({
    required String groupId,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final data = userDoc.data() ?? {};
    final name = (data['name'] ?? user.displayName ?? 'NutriPulse User')
        .toString();

    await _db.collection('groups').doc(groupId).collection('posts').add({
      'uid': user.uid,
      'username': name,
      'text': text.trim(),
      'likes': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
