import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PrivateChatService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String get currentUid {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }
    return user.uid;
  }

  static String chatIdFor(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  static DocumentReference<Map<String, dynamic>> chatRef(String friendUid) {
    return _db
        .collection('private_chats')
        .doc(chatIdFor(currentUid, friendUid.trim()));
  }

  static CollectionReference<Map<String, dynamic>> messagesRef(
    String friendUid,
  ) {
    return chatRef(friendUid).collection('messages');
  }

  static Future<Map<String, dynamic>> _myProfile() async {
    final user = _auth.currentUser;
    final doc = await _db.collection('users').doc(currentUid).get();
    final data = doc.data() ?? {};

    return {
      'uid': currentUid,
      'name':
          (data['name'] ??
                  data['username'] ??
                  user?.displayName ??
                  'NutriPulse User')
              .toString(),
      'photoBase64': (data['photoBase64'] ?? data['userImageBase64'] ?? '')
          .toString(),
    };
  }

  static Future<void> ensureChat({
    required String friendUid,
    required String friendName,
    String friendPhotoBase64 = '',
  }) async {
    final cleanedFriendUid = friendUid.trim();
    if (cleanedFriendUid.isEmpty) {
      throw Exception(
        'Friend UID is missing. Pass the Firebase UID of the user.',
      );
    }

    if (cleanedFriendUid == currentUid) {
      throw Exception('You cannot start a private chat with yourself.');
    }

    final ref = chatRef(cleanedFriendUid);
    final me = await _myProfile();
    final now = FieldValue.serverTimestamp();

    // IMPORTANT FIX:
    // Do not read the friend user document or ref.get() before creating the chat.
    // Some Firestore rules only allow users to read their own user document, and
    // your private_chats read rule checks resource.data.participants. If the chat
    // document does not exist yet, that read becomes permission-denied. A merge
    // set can create the chat when missing and update it when it already exists.
    await ref.set({
      'participants': [currentUid, cleanedFriendUid],
      'participantInfo': {
        currentUid: me,
        cleanedFriendUid: {
          'uid': cleanedFriendUid,
          'name': friendName,
          'photoBase64': friendPhotoBase64,
        },
      },
      'lastMessage': '',
      'lastMessageAt': now,
      'lastSenderId': '',
      'unreadCounts': {currentUid: 0, cleanedFriendUid: 0},
      'updatedAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> chatsStream() {
    return _db
        .collection('private_chats')
        .where('participants', arrayContains: currentUid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> chatStream(
    String friendUid,
  ) {
    return chatRef(friendUid).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(
    String friendUid,
  ) {
    return messagesRef(
      friendUid,
    ).orderBy('createdAt', descending: false).limit(150).snapshots();
  }

  static Future<void> sendTextMessage({
    required String friendUid,
    required String friendName,
    String friendPhotoBase64 = '',
    required String text,
  }) async {
    final cleanText = text.trim();
    final cleanedFriendUid = friendUid.trim();

    if (cleanText.isEmpty) return;
    if (cleanedFriendUid.isEmpty) {
      throw Exception(
        'Friend UID is missing. Pass the Firebase UID of the user.',
      );
    }

    await ensureChat(
      friendUid: cleanedFriendUid,
      friendName: friendName,
      friendPhotoBase64: friendPhotoBase64,
    );

    final me = await _myProfile();
    final chat = chatRef(cleanedFriendUid);
    final message = messagesRef(cleanedFriendUid).doc();
    final chatId = chat.id;
    final now = FieldValue.serverTimestamp();

    final notification = _db
        .collection('users')
        .doc(cleanedFriendUid)
        .collection('notifications')
        .doc('private_message_${chatId}_${message.id}');

    final batch = _db.batch();

    batch.set(message, {
      'id': message.id,
      'senderId': currentUid,
      'receiverId': cleanedFriendUid,
      'text': cleanText,
      'type': 'text',
      'createdAt': now,
      'seenBy': [currentUid],
    });

    batch.update(chat, {
      'lastMessage': cleanText,
      'lastMessageAt': now,
      'lastSenderId': currentUid,
      'updatedAt': now,
      'unreadCounts.$currentUid': 0,
      'unreadCounts.$cleanedFriendUid': FieldValue.increment(1),
    });

    // This writes to the receiver's notification center. The rules require
    // senderId and receiverId, so do not remove these fields.
    batch.set(notification, {
      'type': 'private_message',
      'title': '${me['name']} sent you a message',
      'body': cleanText,
      'actorUid': currentUid,
      'actorName': me['name'],
      'actorImageBase64': me['photoBase64'],
      'senderId': currentUid,
      'receiverId': cleanedFriendUid,
      'chatId': chatId,
      'chatRoomId': chatId,
      'messageId': message.id,
      'friendUid': currentUid,
      'friendName': me['name'],
      'friendPhotoBase64': me['photoBase64'],
      'read': false,
      'createdAt': now,
      'screen': 'private_chat',
    }, SetOptions(merge: true));

    await batch.commit();
  }

  static Future<void> markAsRead(String friendUid) async {
    final ref = chatRef(friendUid.trim());

    // Do not do ref.get() here. The same read rule can fail if the chat is
    // still being created. update() is enough after ensureChat() succeeds.
    try {
      await ref.update({
        'unreadCounts.$currentUid': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') rethrow;
    }
  }

  static Future<void> clearChatForEveryone(String friendUid) async {
    final chat = chatRef(friendUid);
    final messages = await messagesRef(friendUid).limit(100).get();

    final batch = _db.batch();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }

    batch.set(chat, {
      'lastMessage': '',
      'lastSenderId': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadCounts': {currentUid: 0, friendUid: 0},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  static String otherNameFromChat(Map<String, dynamic> chat, String friendUid) {
    final info = chat['participantInfo'];
    if (info is Map && info[friendUid] is Map) {
      return (info[friendUid]['name'] ?? 'Friend').toString();
    }
    return 'Friend';
  }

  static String otherPhotoFromChat(
    Map<String, dynamic> chat,
    String friendUid,
  ) {
    final info = chat['participantInfo'];
    if (info is Map && info[friendUid] is Map) {
      return (info[friendUid]['photoBase64'] ?? '').toString();
    }
    return '';
  }

  static int unreadForMe(Map<String, dynamic> chat) {
    final unread = chat['unreadCounts'];
    if (unread is Map && unread[currentUid] is num) {
      return (unread[currentUid] as num).toInt();
    }
    return 0;
  }
}
