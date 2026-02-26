"use strict";
/**
 * Main Cloud Functions Entry Point
 * Exports all secure operations and notification triggers
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onUserUpdated = exports.onUserCreated = exports.onMessageCreated = exports.setUserCustomClaims = exports.secureGetGroupKey = exports.secureResubmitRequest = exports.secureToggleMessageAccess = exports.secureUpdateUserStatus = exports.secureSendMessage = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const v2_1 = require("firebase-functions/v2");
// Initialize Firebase Admin
admin.initializeApp();
// Set region
(0, v2_1.setGlobalOptions)({ region: "us-central1" });
// Re-export secure operations
var secure_operations_1 = require("./secure_operations");
Object.defineProperty(exports, "secureSendMessage", { enumerable: true, get: function () { return secure_operations_1.secureSendMessage; } });
Object.defineProperty(exports, "secureUpdateUserStatus", { enumerable: true, get: function () { return secure_operations_1.secureUpdateUserStatus; } });
Object.defineProperty(exports, "secureToggleMessageAccess", { enumerable: true, get: function () { return secure_operations_1.secureToggleMessageAccess; } });
Object.defineProperty(exports, "secureResubmitRequest", { enumerable: true, get: function () { return secure_operations_1.secureResubmitRequest; } });
Object.defineProperty(exports, "secureGetGroupKey", { enumerable: true, get: function () { return secure_operations_1.secureGetGroupKey; } });
// Re-export security utilities for Custom Claims setup
var security_1 = require("./security");
Object.defineProperty(exports, "setUserCustomClaims", { enumerable: true, get: function () { return security_1.setUserCustomClaims; } });
function createDataMessage(target, title, body, data, topic = null) {
    const baseConfig = {
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
    }
    else if (target) {
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
exports.onMessageCreated = (0, firestore_1.onDocumentCreated)("messages/{messageId}", async (event) => {
    const snapshot = event.data;
    if (!snapshot)
        return;
    const messageData = snapshot.data();
    const senderName = messageData.sender_name || "User";
    // Content might be encrypted, show generic message
    const isEncrypted = messageData.encrypted === true;
    const displayContent = isEncrypted
        ? "New encrypted message"
        : messageData.content || "New message";
    console.log(`New message from ${senderName} (encrypted: ${isEncrypted})`);
    const payload = createDataMessage(null, "📨 New Message", `${senderName}: ${displayContent}`, {
        type: "MESSAGE",
        sender_id: messageData.sender_id || "",
        message_id: event.params.messageId,
        encrypted: String(isEncrypted),
    }, "verified_users");
    return admin.messaging().send(payload);
});
/**
 * Triggered when a new user signs up
 * Also sets initial Custom Claims
 */
exports.onUserCreated = (0, firestore_1.onDocumentCreated)("users/{userId}", async (event) => {
    const snapshot = event.data;
    if (!snapshot)
        return;
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
    }
    catch (error) {
        console.error(`Failed to set claims for ${userId}:`, error);
    }
    const payload = createDataMessage(null, "📋 New Request", `New request from ${userName}`, {
        type: "NEW_REQUEST",
        user_id: userId,
    }, "admins");
    return admin.messaging().send(payload);
});
/**
 * Triggered when user document is updated
 * Handles status and access notifications
 */
exports.onUserUpdated = (0, firestore_1.onDocumentUpdated)("users/{userId}", async (event) => {
    if (!event.data)
        return;
    const before = event.data.before.data();
    const after = event.data.after.data();
    const userId = event.params.userId;
    const userName = after.displayName || after.name || "User";
    // Sync Custom Claims on any relevant change
    if (before.status !== after.status ||
        before.can_send_messages !== after.can_send_messages ||
        before.role !== after.role) {
        try {
            await admin.auth().setCustomUserClaims(userId, {
                role: after.role || "user",
                canSendMessage: after.can_send_messages || false,
                requestStatus: after.status || "pending",
            });
            console.log(`Updated claims for user ${userId}`);
        }
        catch (error) {
            console.error(`Failed to update claims for ${userId}:`, error);
        }
    }
    // Request Status Change notification
    if (before.status !== after.status) {
        const statusEmoji = after.status === "verified" || after.status === "approved"
            ? "✅"
            : after.status === "rejected"
                ? "❌"
                : "⏳";
        if (after.fcm_token) {
            const payload = createDataMessage(after.fcm_token, "📋 Request Status Update", `${statusEmoji} ${userName} - ${after.status}`, {
                type: "STATUS",
                status: after.status,
            });
            await admin.messaging().send(payload);
        }
    }
    // Message Access Change notification
    if (before.can_send_messages !== after.can_send_messages) {
        const isGranted = after.can_send_messages === true;
        const status = isGranted ? "GRANTED" : "REVOKED";
        const payload = createDataMessage(null, `🔐 Message Access ${status}`, `Access ${status.toLowerCase()} for ${userName}`, {
            type: "ACCESS",
            access: status,
        }, "non_admins");
        await admin.messaging().send(payload);
    }
});
//# sourceMappingURL=index.js.map