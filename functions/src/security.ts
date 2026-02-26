/**
 * Security Utilities for Cloud Functions
 * Provides encryption, hashing, UUID generation, and session validation
 */

import * as crypto from "crypto";
import { v4 as uuidv4 } from "uuid";
import { SecretManagerServiceClient } from "@google-cloud/secret-manager";
import * as admin from "firebase-admin";

// Secret Manager client (lazy initialization)
let secretClient: SecretManagerServiceClient | null = null;
let cachedEncryptionKey: Buffer | null = null;
const ENCRYPTION_KEY_SECRET_NAME =
  "projects/451371205080/secrets/afx-encryption-key/versions/latest";

// ============================================================================
// UUID GENERATION
// ============================================================================

/**
 * Generate a UUID v4 for document IDs
 */
export function generateUUID(): string {
  return uuidv4();
}

// ============================================================================
// HASHING (SHA-256)
// ============================================================================

/**
 * Create SHA-256 hash of sensitive data
 */
export function hashSHA256(data: string): string {
  return crypto.createHash("sha256").update(data).digest("hex");
}

/**
 * Create a secure hash with salt for identifiers
 */
export function hashWithSalt(data: string, salt: string): string {
  return crypto
    .createHash("sha256")
    .update(data + salt)
    .digest("hex");
}

// ============================================================================
// ENCRYPTION (AES-256-GCM)
// ============================================================================

/**
 * Get encryption key from Google Cloud Secret Manager
 */
async function getEncryptionKey(): Promise<Buffer> {
  if (cachedEncryptionKey) {
    return cachedEncryptionKey;
  }

  if (!secretClient) {
    secretClient = new SecretManagerServiceClient();
  }

  try {
    const [version] = await secretClient.accessSecretVersion({
      name: ENCRYPTION_KEY_SECRET_NAME,
    });

    const payload = version.payload?.data;
    if (!payload) {
      throw new Error("Secret payload is empty");
    }

    // Key should be 32 bytes (256 bits) for AES-256
    const keyString =
      typeof payload === "string" ? payload : payload.toString();
    cachedEncryptionKey = Buffer.from(keyString, "hex");

    if (cachedEncryptionKey.length !== 32) {
      throw new Error("Encryption key must be 32 bytes (64 hex characters)");
    }

    return cachedEncryptionKey;
  } catch (error) {
    console.error("Failed to retrieve encryption key:", error);
    throw new Error("Encryption key unavailable");
  }
}

/**
 * Encrypt data using AES-256-GCM
 * Returns: iv:authTag:encryptedData (all hex encoded)
 */
export async function encryptAES256(plaintext: string): Promise<string> {
  const key = await getEncryptionKey();
  const iv = crypto.randomBytes(12); // 96-bit IV for GCM

  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  let encrypted = cipher.update(plaintext, "utf8", "hex");
  encrypted += cipher.final("hex");

  const authTag = cipher.getAuthTag();

  // Format: iv:authTag:encryptedData
  return `${iv.toString("hex")}:${authTag.toString("hex")}:${encrypted}`;
}

/**
 * Decrypt data using AES-256-GCM
 * Input format: iv:authTag:encryptedData (all hex encoded)
 */
export async function decryptAES256(ciphertext: string): Promise<string> {
  const key = await getEncryptionKey();
  const parts = ciphertext.split(":");

  if (parts.length !== 3) {
    throw new Error("Invalid ciphertext format");
  }

  const iv = Buffer.from(parts[0], "hex");
  const authTag = Buffer.from(parts[1], "hex");
  const encrypted = parts[2];

  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(authTag);

  let decrypted = decipher.update(encrypted, "hex", "utf8");
  decrypted += decipher.final("utf8");

  return decrypted;
}

// ============================================================================
// SESSION VALIDATION
// ============================================================================

export interface UserSession {
  uid: string;
  role: string;
  canSendMessage: boolean;
  requestStatus: string;
  email: string;
  name: string;
}

export interface ValidationResult {
  valid: boolean;
  session?: UserSession;
  error?: string;
}

/**
 * Validate user session and fetch Source of Truth from Firestore
 * This is the core of Zero-Trust: never trust client data
 */
export async function validateSession(
  auth: admin.auth.DecodedIdToken | null,
  requiredPermissions?: {
    requireVerified?: boolean;
    requireCanSendMessage?: boolean;
    requireRole?: string[];
  }
): Promise<ValidationResult> {
  if (!auth) {
    return { valid: false, error: "Not authenticated" };
  }

  try {
    // Fetch user data from Firestore (Source of Truth)
    const userDoc = await admin
      .firestore()
      .collection("users")
      .doc(auth.uid)
      .get();

    if (!userDoc.exists) {
      return { valid: false, error: "User not found in database" };
    }

    const userData = userDoc.data()!;

    const session: UserSession = {
      uid: auth.uid,
      role: userData.role || "user",
      canSendMessage: userData.can_send_messages || false,
      requestStatus: userData.status || "pending",
      email: userData.email || auth.email || "",
      name: userData.name || "User",
    };

    // Validate permissions if specified
    if (requiredPermissions) {
      // Check verified status
      if (
        requiredPermissions.requireVerified &&
        session.requestStatus !== "verified"
      ) {
        return { valid: false, error: "Account not verified", session };
      }

      // Check message sending permission
      if (requiredPermissions.requireCanSendMessage) {
        // Admins always can send
        if (session.role !== "admin" && !session.canSendMessage) {
          return {
            valid: false,
            error: "Message sending not permitted",
            session,
          };
        }
      }

      // Check role
      if (
        requiredPermissions.requireRole &&
        !requiredPermissions.requireRole.includes(session.role)
      ) {
        return {
          valid: false,
          error: "Insufficient role permissions",
          session,
        };
      }
    }

    return { valid: true, session };
  } catch (error) {
    console.error("Session validation error:", error);
    return { valid: false, error: "Session validation failed" };
  }
}

// ============================================================================
// CUSTOM CLAIMS MANAGEMENT
// ============================================================================

/**
 * Set Custom Claims for a user
 * Should be called when user status or permissions change
 */
export async function setUserCustomClaims(
  uid: string,
  claims: {
    role?: string;
    canSendMessage?: boolean;
    requestStatus?: string;
  }
): Promise<void> {
  const currentClaims = (await admin.auth().getUser(uid)).customClaims || {};

  const newClaims = {
    ...currentClaims,
    ...claims,
  };

  await admin.auth().setCustomUserClaims(uid, newClaims);

  // Force token refresh by updating user record
  await admin.firestore().collection("users").doc(uid).update({
    claims_updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`Updated custom claims for ${uid}:`, newClaims);
}
