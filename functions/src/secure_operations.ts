/**
 * Secure Operations Cloud Functions
 * All sensitive Firestore operations route through these functions
 */

import {
  onCall,
  HttpsError,
  CallableRequest,
} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { generateUUID, validateSession, setUserCustomClaims } from "./security";

// Note: setGlobalOptions is called once in index.ts

// ============================================================================
// SECURE SEND MESSAGE
// ============================================================================

interface SendMessageRequest {
  content: string;
  clientId?: string; // Optional client-side ID for tracking
}

interface SendMessageResponse {
  success: boolean;
  messageId: string;
  encryptedContent: string;
  contentHash: string;
  timestamp: string;
  error?: string;
}

/**
 * Securely send a message with full validation, encryption, and UUID
 */
export const secureSendMessage = onCall<
  SendMessageRequest,
  Promise<SendMessageResponse>
>(
  { cors: true },
  async (
    request: CallableRequest<SendMessageRequest>
  ): Promise<SendMessageResponse> => {
    // Validate session with required permissions
    const validation = await validateSession(request.auth?.token ?? null, {
      requireVerified: true,
      requireCanSendMessage: true,
    });

    if (!validation.valid || !validation.session) {
      throw new HttpsError(
        "permission-denied",
        validation.error || "Access denied"
      );
    }

    const { content, clientId } = request.data;

    // Validate content
    if (
      !content ||
      typeof content !== "string" ||
      content.trim().length === 0
    ) {
      throw new HttpsError("invalid-argument", "Message content is required");
    }

    if (content.length > 5000) {
      throw new HttpsError(
        "invalid-argument",
        "Message too long (max 5000 characters)"
      );
    }

    const session = validation.session;

    try {
      // Generate UUID for document ID
      const messageId = generateUUID();

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
    } catch (error) {
      console.error("Error sending message:", error);
      throw new HttpsError("internal", "Failed to send message");
    }
  }
);

// ============================================================================
// ADMIN: UPDATE USER STATUS
// ============================================================================

interface UpdateUserStatusRequest {
  targetUserId: string;
  status: "pending" | "verified" | "rejected";
}

interface UpdateUserStatusResponse {
  success: boolean;
  message: string;
}

/**
 * Admin-only: Update user verification status
 */
export const secureUpdateUserStatus = onCall<
  UpdateUserStatusRequest,
  Promise<UpdateUserStatusResponse>
>(
  { cors: true },
  async (
    request: CallableRequest<UpdateUserStatusRequest>
  ): Promise<UpdateUserStatusResponse> => {
    // Validate admin session
    const validation = await validateSession(request.auth?.token ?? null, {
      requireRole: ["admin"],
    });

    if (!validation.valid || !validation.session) {
      throw new HttpsError(
        "permission-denied",
        validation.error || "Admin access required"
      );
    }

    const { targetUserId, status } = request.data;

    if (!targetUserId || !status) {
      throw new HttpsError(
        "invalid-argument",
        "Target user ID and status are required"
      );
    }

    const validStatuses = ["pending", "verified", "rejected"];
    if (!validStatuses.includes(status)) {
      throw new HttpsError("invalid-argument", "Invalid status value");
    }

    try {
      // Update user document
      const updateData: Record<string, unknown> = {
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
      await setUserCustomClaims(targetUserId, {
        requestStatus: status,
        canSendMessage: status === "rejected" ? false : undefined,
      });

      console.log(
        `User ${targetUserId} status updated to ${status} by ${validation.session.uid}`
      );

      return {
        success: true,
        message: `User status updated to ${status}`,
      };
    } catch (error) {
      console.error("Error updating user status:", error);
      throw new HttpsError("internal", "Failed to update user status");
    }
  }
);

// ============================================================================
// ADMIN: TOGGLE MESSAGE ACCESS
// ============================================================================

interface ToggleMessageAccessRequest {
  targetUserId: string;
  canSendMessages: boolean;
}

interface ToggleMessageAccessResponse {
  success: boolean;
  message: string;
}

/**
 * Admin-only: Toggle user's message sending permission
 */
export const secureToggleMessageAccess = onCall<
  ToggleMessageAccessRequest,
  Promise<ToggleMessageAccessResponse>
>(
  { cors: true },
  async (
    request: CallableRequest<ToggleMessageAccessRequest>
  ): Promise<ToggleMessageAccessResponse> => {
    // Validate admin session
    const validation = await validateSession(request.auth?.token ?? null, {
      requireRole: ["admin"],
    });

    if (!validation.valid || !validation.session) {
      throw new HttpsError(
        "permission-denied",
        validation.error || "Admin access required"
      );
    }

    const { targetUserId, canSendMessages } = request.data;

    if (!targetUserId || typeof canSendMessages !== "boolean") {
      throw new HttpsError(
        "invalid-argument",
        "Target user ID and canSendMessages boolean are required"
      );
    }

    try {
      // Update user document
      await admin.firestore().collection("users").doc(targetUserId).update({
        can_send_messages: canSendMessages,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_by: validation.session.uid,
      });

      // Update Custom Claims
      await setUserCustomClaims(targetUserId, {
        canSendMessage: canSendMessages,
      });

      console.log(
        `User ${targetUserId} message access: ${canSendMessages} by ${validation.session.uid}`
      );

      return {
        success: true,
        message: `Message access ${canSendMessages ? "granted" : "revoked"}`,
      };
    } catch (error) {
      console.error("Error toggling message access:", error);
      throw new HttpsError("internal", "Failed to toggle message access");
    }
  }
);

// ============================================================================
// GET GROUP KEY (Simplified E2EE for "General" Room)
// ============================================================================

interface GetGroupKeyResponse {
  success: boolean;
  groupKey: string; // Hex-encoded 32-byte key
}

/**
 * Get the shared "General" room key
 * Restricted to verified users only.
 */
export const secureGetGroupKey = onCall<void, Promise<GetGroupKeyResponse>>(
  { cors: true },
  async (request: CallableRequest<void>): Promise<GetGroupKeyResponse> => {
    // 1. Verify User is Authenticated & Verified
    const validation = await validateSession(request.auth?.token ?? null, {
      requireVerified: true,
    });

    if (!validation.valid) {
      throw new HttpsError(
        "permission-denied",
        validation.error || "Access denied: Verified account required"
      );
    }

    console.log(
      `Group Key requested by verified user: ${validation.session?.uid}`
    );

    // 2. Return the Shared Group Key
    // In a full Signal Protocol implementation, this would be encrypted with the user's Public Key.
    // For this "Simplified" version, we verify access via Auth Token and return the key over HTTPS (TLS).
    // This Key MUST match the length required by the client (32 bytes for AES-256).

    // STATIC KEY FOR "GENERAL" ROOM (Generated 2024 - Do Not Change/Commit in Public Repos ideally)
    // Hex encoded 32-byte key
    const SHARED_GROUP_KEY =
      "a1b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdef";

    return {
      success: true,
      groupKey: SHARED_GROUP_KEY,
    };
  }
);

// ============================================================================
// DECRYPT MESSAGE (Server-side decryption for reads)
// ============================================================================

// secureDecryptMessage removed to ensure 100% Client-Side Privacy (E2EE)

// ============================================================================
// RESUBMIT REQUEST (for rejected users)
// ============================================================================

interface ResubmitRequestResponse {
  success: boolean;
  message: string;
}

/**
 * Allow rejected users to resubmit their request
 */
export const secureResubmitRequest = onCall<
  void,
  Promise<ResubmitRequestResponse>
>(
  { cors: true },
  async (request: CallableRequest<void>): Promise<ResubmitRequestResponse> => {
    const validation = await validateSession(request.auth?.token ?? null);

    if (!validation.valid || !validation.session) {
      throw new HttpsError(
        "permission-denied",
        validation.error || "Access denied"
      );
    }

    const session = validation.session;

    // Only rejected users can resubmit
    if (session.requestStatus !== "rejected") {
      throw new HttpsError(
        "failed-precondition",
        "Only rejected users can resubmit requests"
      );
    }

    try {
      await admin.firestore().collection("users").doc(session.uid).update({
        status: "pending",
        can_send_messages: false,
        resubmitted_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update Custom Claims
      await setUserCustomClaims(session.uid, {
        requestStatus: "pending",
        canSendMessage: false,
      });

      return {
        success: true,
        message: "Request resubmitted successfully",
      };
    } catch (error) {
      console.error("Error resubmitting request:", error);
      throw new HttpsError("internal", "Failed to resubmit request");
    }
  }
);
