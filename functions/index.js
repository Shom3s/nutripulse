const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

async function getUser(uid) {
  const doc = await db.collection("users").doc(uid).get();
  return doc.exists ? doc.data() : {};
}

async function getTokens(uid) {
  const snap = await db.collection("users").doc(uid).collection("fcmTokens").get();

  return snap.docs
    .map((doc) => doc.data().token)
    .filter((token) => typeof token === "string" && token.length > 0);
}

async function communityPushEnabled(uid) {
  const user = await getUser(uid);
  const settings = user.notificationSettings || {};
  return settings.communityPush !== false;
}

async function writeNotification({ uid, title, body, type, data = {} }) {
  await db.collection("users").doc(uid).collection("notifications").add({
    title,
    body,
    type,
    read: false,
    data,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function sendPush({ uid, title, body, type, data = {} }) {
  if (!(await communityPushEnabled(uid))) return;

  await writeNotification({ uid, title, body, type, data });

  const tokens = await getTokens(uid);
  if (tokens.length === 0) return;

  const message = {
    tokens,
    notification: { title, body },
    data: {
      type,
      screen: data.screen || "",
      chatId: data.chatId || "",
      senderId: data.senderId || "",
      postId: data.postId || "",
      requestId: data.requestId || "",
    },
    android: {
      priority: "high",
      notification: {
        channelId: "nutripulse_reminders",
        sound: "default",
      },
    },
    apns: {
      payload: {
        aps: { sound: "default" },
      },
    },
  };

  const response = await admin.messaging().sendEachForMulticast(message);

  const invalidTokens = [];
  response.responses.forEach((res, index) => {
    if (!res.success) {
      const code = res.error && res.error.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        invalidTokens.push(tokens[index]);
      }
    }
  });

  if (invalidTokens.length > 0) {
    const batch = db.batch();

    for (const token of invalidTokens) {
      batch.delete(db.collection("users").doc(uid).collection("fcmTokens").doc(token));
    }

    await batch.commit();
  }
}

exports.onPrivateChatMessageCreated = functions.firestore
  .document("private_chats/{chatId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const chatId = context.params.chatId;

    const senderId = message.senderId;
    const text = message.text || "Sent you a message";

    const chatDoc = await db.collection("private_chats").doc(chatId).get();
    if (!chatDoc.exists) return;

    const chat = chatDoc.data();
    const participants = chat.participants || [];
    const receiverId = participants.find((uid) => uid !== senderId);

    if (!receiverId) return;

    const sender = await getUser(senderId);
    const senderName = sender.name || sender.username || sender.displayName || "Friend";

    await sendPush({
      uid: receiverId,
      title: `New message from ${senderName} 💬`,
      body: text.length > 90 ? text.substring(0, 87) + "..." : text,
      type: "chat",
      data: {
        screen: "private_chat",
        chatId,
        senderId,
      },
    });
  });

exports.onFriendRequestCreated = functions.firestore
  .document("friend_requests/{requestId}")
  .onCreate(async (snap, context) => {
    const request = snap.data();

    const toUid = request.toUid;
    const fromUid = request.fromUid;

    if (!toUid || !fromUid || toUid === fromUid) return;

    const fromName = request.fromName || "Someone";

    await sendPush({
      uid: toUid,
      title: "New friend request 👋",
      body: `${fromName} sent you a friend request.`,
      type: "friend_request",
      data: {
        screen: "friends",
        requestId: context.params.requestId,
        senderId: fromUid,
      },
    });
  });

exports.onFriendRequestUpdated = functions.firestore
  .document("friend_requests/{requestId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (before.status === after.status) return;
    if (after.status !== "accepted") return;

    const fromUid = after.fromUid;
    const toName = after.toName || "Someone";

    if (!fromUid) return;

    await sendPush({
      uid: fromUid,
      title: "Friend request accepted ✅",
      body: `${toName} accepted your friend request.`,
      type: "friend_accept",
      data: {
        screen: "friends",
        requestId: context.params.requestId,
      },
    });
  });

exports.onPostLikeCreated = functions.firestore
  .document("posts/{postId}/likes/{likeId}")
  .onCreate(async (snap, context) => {
    const like = snap.data();
    const postId = context.params.postId;

    const likerUid = like.uid || context.params.likeId;

    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) return;

    const post = postDoc.data();
    const ownerUid = post.uid;

    if (!ownerUid || ownerUid === likerUid) return;

    const liker = await getUser(likerUid);
    const likerName = liker.name || liker.username || liker.displayName || "Someone";

    await sendPush({
      uid: ownerUid,
      title: "New like ❤️",
      body: `${likerName} liked your post.`,
      type: "like",
      data: {
        screen: "post",
        postId,
        senderId: likerUid,
      },
    });
  });

exports.onPostCommentCreated = functions.firestore
  .document("posts/{postId}/comments/{commentId}")
  .onCreate(async (snap, context) => {
    const comment = snap.data();
    const postId = context.params.postId;

    const commenterUid = comment.uid;
    const text = comment.text || "Commented on your post";

    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) return;

    const post = postDoc.data();
    const ownerUid = post.uid;

    if (!ownerUid || ownerUid === commenterUid) return;

    const commenter = await getUser(commenterUid);
    const commenterName = commenter.name || commenter.username || commenter.displayName || "Someone";

    await sendPush({
      uid: ownerUid,
      title: "New comment 💬",
      body: `${commenterName}: ${text.length > 75 ? text.substring(0, 72) + "..." : text}`,
      type: "comment",
      data: {
        screen: "post",
        postId,
        senderId: commenterUid,
      },
    });
  });
