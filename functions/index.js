const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { setGlobalOptions } = require("firebase-functions/v2");

admin.initializeApp();

// Set region
setGlobalOptions({ region: "us-central1" });

/**
 * Helper to create a DATA-ONLY FCM payload.
 * Data-only messages (no 'notification' field) ensure that only our
 * app's background handler displays the notification, preventing duplicates.
 */
function createDataMessage(target, title, body, data, topic = null) {
  const message = {
    // DO NOT include 'notification' field here to avoid OS automatic display
    data: {
      ...data,
      title: title,
      body: body,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    android: {
      priority: "high",
    },
    apns: {
      payload: {
        aps: {
          contentAvailable: true,
        },
      },
    },
  };

  if (topic) {
    message.topic = topic;
  } else if (target) {
    message.token = target;
  }

  return message;
}

/**
 * 1. MESSAGE: Triggered when a new message is created.
 */
exports.onMessageCreated = onDocumentCreated(
  "messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const messageData = snapshot.data();

    const senderName = messageData.sender_name || "User";
    const content = messageData.content || "New message";

    console.log(`New message from ${senderName}`);

    const payload = createDataMessage(
      null,
      "📨 New Message",
      `${senderName}: ${content}`,
      {
        type: "MESSAGE",
        sender_id: messageData.sender_id || "",
        message_id: event.params.messageId,
      },
      "verified_users"
    );

    return admin.messaging().send(payload);
  }
);

/**
 * 2. NEW REQUEST: Triggered when a new user signs up.
 */
exports.onUserCreated = onDocumentCreated("users/{userId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const user = snapshot.data();

  const userName = user.displayName || user.name || "New User";

  const payload = createDataMessage(
    null,
    "📋 New Request",
    `New request from ${userName}`,
    {
      type: "NEW_REQUEST",
      user_id: event.params.userId,
    },
    "admins"
  );

  return admin.messaging().send(payload);
});

/**
 * 3 & 4. STATUS & ACCESS: Triggered when user document is updated.
 */
exports.onUserUpdated = onDocumentUpdated("users/{userId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  const userName = after.displayName || after.name || "User";

  // 3. Request Status Change
  if (before.status !== after.status) {
    const statusEmoji =
      after.status === "verified" || after.status === "approved"
        ? "✅"
        : after.status === "rejected"
        ? "❌"
        : "⏳";

    if (after.fcm_token) {
      const payload = createDataMessage(
        after.fcm_token,
        "📋 Request Status Update",
        `${statusEmoji} ${userName} - ${after.status}`,
        {
          type: "STATUS",
          status: after.status,
        }
      );
      await admin.messaging().send(payload);
    }
  }

  // 4. Message Access Change
  if (before.can_send_messages !== after.can_send_messages) {
    const isGranted = after.can_send_messages === true;
    const status = isGranted ? "GRANTED" : "REVOKED";

    const payload = createDataMessage(
      null,
      `🔐 Message Access ${status}`,
      `Access ${status.toLowerCase()} for ${userName}`,
      {
        type: "ACCESS",
        access: status,
      },
      "non_admins"
    );

    await admin.messaging().send(payload);
  }
});
