import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupChatService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String get uid => _auth.currentUser!.uid;

  static Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(
    String groupId,
  ) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> pinnedMessagesStream(
    String groupId,
  ) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('pinned')
        .orderBy('pinnedAt', descending: true)
        .limit(1)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> typingStream(
    String groupId,
  ) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('typing')
        .snapshots();
  }

  static Future<Map<String, dynamic>> _profile() async {
    final user = _auth.currentUser!;
    final doc = await _db.collection('users').doc(user.uid).get();
    final data = doc.data() ?? {};
    return {
      'uid': user.uid,
      'name': (data['name'] ?? user.displayName ?? 'NutriPulse User')
          .toString(),
      'photoBase64': (data['photoBase64'] ?? '').toString(),
    };
  }

  static Future<String> fileToBase64(File file) async {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  static Future<void> sendMessage({
    required String groupId,
    required String text,
    String imageBase64 = '',
    bool isAiTip = false,
  }) async {
    if (text.trim().isEmpty && imageBase64.isEmpty) return;

    final profile = await _profile();

    await _db.collection('groups').doc(groupId).collection('messages').add({
      'uid': profile['uid'],
      'username': profile['name'],
      'photoBase64': profile['photoBase64'],
      'text': text.trim(),
      'imageBase64': imageBase64,
      'isAiTip': isAiTip,
      'reactions': {},
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> addReaction({
    required String groupId,
    required String messageId,
    required String emoji,
  }) async {
    final ref = _db
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId);
    await ref.set({
      'reactions': {emoji: FieldValue.increment(1)},
    }, SetOptions(merge: true));
  }

  static Future<void> pinMessage({
    required String groupId,
    required String messageId,
    required Map<String, dynamic> message,
  }) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('pinned')
        .doc(messageId)
        .set({
          ...message,
          'pinnedAt': FieldValue.serverTimestamp(),
          'pinnedBy': uid,
        });
  }

  static Future<void> setTyping(String groupId, bool typing) async {
    final profile = await _profile();
    final ref = _db
        .collection('groups')
        .doc(groupId)
        .collection('typing')
        .doc(uid);

    if (typing) {
      await ref.set({
        'uid': uid,
        'name': profile['name'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  static Future<void> sendAiNutritionTip(String groupId) async {
    await sendMessage(
      groupId: groupId,
      isAiTip: true,
      text:
          'AI Tip: Balance your plate with protein, fiber-rich carbs, healthy fats, and water. For Malaysian meals, reduce oily sides and add eggs, tofu, chicken, or fish for better macros.',
    );
  }
}
