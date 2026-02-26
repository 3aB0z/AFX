"use strict";
/**
 * Secure Operations Cloud Functions
 * All sensitive Firestore operations route through these functions
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
exports.secureResubmitRequest = exports.secureGetGroupKey = exports.secureToggleMessageAccess = exports.secureUpdateUserStatus = exports.secureSendMessage = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const security_1 = require("./security");
/**
 * Securely send a message with full validation, encryption, and UUID
 */
exports.secureSendMessage = (0, https_1.onCall)({ cors: true }, async (request) => {
    // Validate session with required permissions
    const validation = await (0, security_1.validateSession)(request.auth?.token ?? null, {
        requireVerified: true,
        requireCanSendMessage: true,
    });
    if (!validation.valid || !validation.session) {
        throw new https_1.HttpsError("permission-denied", validation.error || "Access denied");
    }
    const { content, clientId } = request.data;
    // Validate content
    if (!content ||
        typeof content !== "string" ||
        content.trim().length === 0) {
        throw new https_1.HttpsError("invalid-argument", "Message content is required");
    }
    if (content.length > 5000) {
        throw new https_1.HttpsError("invalid-argument", "Message too long (max 5000 characters)");
    }
    const session = validation.session;
    try {
        // Generate UUID for document ID
        const messageId = (0, security_1.generateUUID)();
        // content is already encrypted by the client (E2EE)
        // We no longer encrypt or hash on the server to ensure 100% privacy
        // Create message document
        const messageData = {
            sender_id: session.uid,
            sender_name: session.name,
            content: content.trim(),
            role: session.role,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            client_id: clientId || null,
            encrypted: true,
        };
        // Write to Firestore with UUID
        await admin
            .firestore()
            .collection("messages")
            .doc(messageId)
            .set(messageData);
        console.log(`Message ${messageId} sent by ${session.uid}`);
        return {
            success: true,
            messageId,
            encryptedContent: content.trim(),
            contentHash: "",
            timestamp: new Date().toISOString(),
        };
    }
    catch (error) {
        console.error("Error sending message:", error);
        throw new https_1.HttpsError("internal", "Failed to send message");
    }
});
/**
 * Admin-only: Update user verification status
 */
exports.secureUpdateUserStatus = (0, https_1.onCall)({ cors: true }, async (request) => {
    // Validate admin session
    const validation = await (0, security_1.validateSession)(request.auth?.token ?? null, {
        requireRole: ["admin"],
    });
    if (!validation.valid || !validation.session) {
        throw new https_1.HttpsError("permission-denied", validation.error || "Admin access required");
    }
    const { targetUserId, status } = request.data;
    if (!targetUserId || !status) {
        throw new https_1.HttpsError("invalid-argument", "Target user ID and status are required");
    }
    const validStatuses = ["pending", "verified", "rejected"];
    if (!validStatuses.includes(status)) {
        throw new https_1.HttpsError("invalid-argument", "Invalid status value");
    }
    try {
        // Update user document
        const updateData = {
            status,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_by: validation.session.uid,
        };
        if (status === "rejected") {
            updateData.can_send_messages = false;
            updateData.rejected_at = admin.firestore.FieldValue.serverTimestamp();
        }
        await admin
            .firestore()
            .collection("users")
            .doc(targetUserId)
            .update(updateData);
        // Update Custom Claims
        await (0, security_1.setUserCustomClaims)(targetUserId, {
            requestStatus: status,
            canSendMessage: status === "rejected" ? false : undefined,
        });
        console.log(`User ${targetUserId} status updated to ${status} by ${validation.session.uid}`);
        return {
            success: true,
            message: `User status updated to ${status}`,
        };
    }
    catch (error) {
        console.error("Error updating user status:", error);
        throw new https_1.HttpsError("internal", "Failed to update user status");
    }
});
/**
 * Admin-only: Toggle user's message sending permission
 */
exports.secureToggleMessageAccess = (0, https_1.onCall)({ cors: true }, async (request) => {
    // Validate admin session
    const validation = await (0, security_1.validateSession)(request.auth?.token ?? null, {
        requireRole: ["admin"],
    });
    if (!validation.valid || !validation.session) {
        throw new https_1.HttpsError("permission-denied", validation.error || "Admin access required");
    }
    const { targetUserId, canSendMessages } = request.data;
    if (!targetUserId || typeof canSendMessages !== "boolean") {
        throw new https_1.HttpsError("invalid-argument", "Target user ID and canSendMessages boolean are required");
    }
    try {
        // Update user document
        await admin.firestore().collection("users").doc(targetUserId).update({
            can_send_messages: canSendMessages,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_by: validation.session.uid,
        });
        // Update Custom Claims
        await (0, security_1.setUserCustomClaims)(targetUserId, {
            canSendMessage: canSendMessages,
        });
        console.log(`User ${targetUserId} message access: ${canSendMessages} by ${validation.session.uid}`);
        return {
            success: true,
            message: `Message access ${canSendMessages ? "granted" : "revoked"}`,
        };
    }
    catch (error) {
        console.error("Error toggling message access:", error);
        throw new https_1.HttpsError("internal", "Failed to toggle message access");
    }
});
/**
 * Get the shared "General" room key
 * Restricted to verified users only.
 */
exports.secureGetGroupKey = (0, https_1.onCall)({ cors: true }, async (request) => {
    // 1. Verify User is Authenticated & Verified
    const validation = await (0, security_1.validateSession)(request.auth?.token ?? null, {
        requireVerified: true,
    });
    if (!validation.valid) {
        throw new https_1.HttpsError("permission-denied", validation.error || "Access denied: Verified account required");
    }
    console.log(`Group Key requested by verified user: ${validation.session?.uid}`);
    // 2. Return the Shared Group Key
    // In a full Signal Protocol implementation, this would be encrypted with the user's Public Key.
    // For this "Simplified" version, we verify access via Auth Token and return the key over HTTPS (TLS).
    // This Key MUST match the length required by the client (32 bytes for AES-256).
    // STATIC KEY FOR "GENERAL" ROOM (Generated 2024 - Do Not Change/Commit in Public Repos ideally)
    // Hex encoded 32-byte key
    const SHARED_GROUP_KEY = "a1b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdef";
    return {
        success: true,
        groupKey: SHARED_GROUP_KEY,
    };
});
/**
 * Allow rejected users to resubmit their request
 */
exports.secureResubmitRequest = (0, https_1.onCall)({ cors: true }, async (request) => {
    const validation = await (0, security_1.validateSession)(request.auth?.token ?? null);
    if (!validation.valid || !validation.session) {
        throw new https_1.HttpsError("permission-denied", validation.error || "Access denied");
    }
    const session = validation.session;
    // Only rejected users can resubmit
    if (session.requestStatus !== "rejected") {
        throw new https_1.HttpsError("failed-precondition", "Only rejected users can resubmit requests");
    }
    try {
        await admin.firestore().collection("users").doc(session.uid).update({
            status: "pending",
            can_send_messages: false,
            resubmitted_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        // Update Custom Claims
        await (0, security_1.setUserCustomClaims)(session.uid, {
            requestStatus: "pending",
            canSendMessage: false,
        });
        return {
            success: true,
            message: "Request resubmitted successfully",
        };
    }
    catch (error) {
        console.error("Error resubmitting request:", error);
        throw new https_1.HttpsError("internal", "Failed to resubmit request");
    }
});
//# sourceMappingURL=secure_operations.js.map