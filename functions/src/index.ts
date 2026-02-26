/**
 * Main Cloud Functions Entry Point
 * Exports all secure operations and notification triggers
 */

import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions/v2";

// Initialize Firebase Admin
admin.initializeApp();

// Set region
setGlobalOptions({ region: "us-central1" });

// Re-export secure operations
export {
  secureSendMessage,
  secureUpdateUserStatus,
  secureToggleMessageAccess,
  secureResubmitRequest,
  secureGetGroupKey,
} from "./secure_operations";

// Re-export security utilities for Custom Claims setup
export { setUserCustomClaims } from "./security";

// ============================================================================
// HELPER: Create DATA-ONLY FCM payload
// ============================================================================

interface FCMData {
  [key: string]: string;
}

interface BaseMessageConfig {
  data: { [key: string]: string };
  android: admin.messaging.AndroidConfig;
  apns: admin.messaging.ApnsConfig;
}

function createDataMessage(
  target: string | null,
  title: string,
  body: string,
  data: FCMData,
  topic: string | null = null
): admin.messaging.Message {
  const baseConfig: BaseMessageConfig = {
    data: {
      ...data,
      title,
      body,
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
    return { ...baseConfig, topic };
  } else if (target) {
    return { ...baseConfig, token: target };
  }

  // Default to topic if neither specified
  return { ...baseConfig, topic: "all_users" };
}

// ============================================================================
// NOTIFICATION TRIGGERS
// ============================================================================

/**
 * Triggered when a new message is created
 * Note: Messages are now created via Cloud Functions, so this still fires
 */
export const onMessageCreated = onDocumentCreated(
  "messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const messageData = snapshot.data();

    const senderName = messageData.sender_name || "User";
    // Content might be encrypted, show generic message
    const isEncrypted = messageData.encrypted === true;
    const displayContent = isEncrypted
      ? "New encrypted message"
      : messageData.content || "New message";

    console.log(`New message from ${senderName} (encrypted: ${isEncrypted})`);

    const payload = createDataMessage(
      null,
      "📨 New Message",
      `${senderName}: ${displayContent}`,
      {
        type: "MESSAGE",
        sender_id: messageData.sender_id || "",
        message_id: event.params.messageId,
        encrypted: String(isEncrypted),
      },
      "verified_users"
    );

    return admin.messaging().send(payload);
  }
);

/**
 * Triggered when a new user signs up
 * Also sets initial Custom Claims
 */
export const onUserCreated = onDocumentCreated(
  "users/{userId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const user = snapshot.data();
    const userId = event.params.userId;

    const userName = user.displayName || user.name || "New User";

    // Set initial Custom Claims
    try {
      await admin.auth().setCustomUserClaims(userId, {
        role: user.role || "user",
        canSendMessage: user.can_send_messages || false,
        requestStatus: user.status || "pending",
      });
      console.log(`Set initial claims for user ${userId}`);
    } catch (error) {
      console.error(`Failed to set claims for ${userId}:`, error);
    }

    const payload = createDataMessage(
      null,
      "📋 New Request",
      `New request from ${userName}`,
      {
        type: "NEW_REQUEST",
        user_id: userId,
      },
      "admins"
    );

    return admin.messaging().send(payload);
  }
);

/**
 * Triggered when user document is updated
 * Handles status and access notifications
 */
export const onUserUpdated = onDocumentUpdated(
  "users/{userId}",
  async (event) => {
    if (!event.data) return;
    const before = event.data.before.data();
    const after = event.data.after.data();
    const userId = event.params.userId;

    const userName = after.displayName || after.name || "User";

    // Sync Custom Claims on any relevant change
    if (
      before.status !== after.status ||
      before.can_send_messages !== after.can_send_messages ||
      before.role !== after.role
    ) {
      try {
        await admin.auth().setCustomUserClaims(userId, {
          role: after.role || "user",
          canSendMessage: after.can_send_messages || false,
          requestStatus: after.status || "pending",
        });
        console.log(`Updated claims for user ${userId}`);
      } catch (error) {
        console.error(`Failed to update claims for ${userId}:`, error);
      }
    }

    // Request Status Change notification
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

    // Message Access Change notification
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
  }
);
