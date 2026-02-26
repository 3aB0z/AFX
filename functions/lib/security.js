"use strict";
/**
 * Security Utilities for Cloud Functions
 * Provides encryption, hashing, UUID generation, and session validation
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
exports.generateUUID = generateUUID;
exports.hashSHA256 = hashSHA256;
exports.hashWithSalt = hashWithSalt;
exports.encryptAES256 = encryptAES256;
exports.decryptAES256 = decryptAES256;
exports.validateSession = validateSession;
exports.setUserCustomClaims = setUserCustomClaims;
const crypto = __importStar(require("crypto"));
const uuid_1 = require("uuid");
const secret_manager_1 = require("@google-cloud/secret-manager");
const admin = __importStar(require("firebase-admin"));
// Secret Manager client (lazy initialization)
let secretClient = null;
let cachedEncryptionKey = null;
const ENCRYPTION_KEY_SECRET_NAME = "projects/451371205080/secrets/afx-encryption-key/versions/latest";
// ============================================================================
// UUID GENERATION
// ============================================================================
/**
 * Generate a UUID v4 for document IDs
 */
function generateUUID() {
    return (0, uuid_1.v4)();
}
// ============================================================================
// HASHING (SHA-256)
// ============================================================================
/**
 * Create SHA-256 hash of sensitive data
 */
function hashSHA256(data) {
    return crypto.createHash("sha256").update(data).digest("hex");
}
/**
 * Create a secure hash with salt for identifiers
 */
function hashWithSalt(data, salt) {
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
async function getEncryptionKey() {
    if (cachedEncryptionKey) {
        return cachedEncryptionKey;
    }
    if (!secretClient) {
        secretClient = new secret_manager_1.SecretManagerServiceClient();
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
        const keyString = typeof payload === "string" ? payload : payload.toString();
        cachedEncryptionKey = Buffer.from(keyString, "hex");
        if (cachedEncryptionKey.length !== 32) {
            throw new Error("Encryption key must be 32 bytes (64 hex characters)");
        }
        return cachedEncryptionKey;
    }
    catch (error) {
        console.error("Failed to retrieve encryption key:", error);
        throw new Error("Encryption key unavailable");
    }
}
/**
 * Encrypt data using AES-256-GCM
 * Returns: iv:authTag:encryptedData (all hex encoded)
 */
async function encryptAES256(plaintext) {
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
async function decryptAES256(ciphertext) {
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
/**
 * Validate user session and fetch Source of Truth from Firestore
 * This is the core of Zero-Trust: never trust client data
 */
async function validateSession(auth, requiredPermissions) {
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
        const userData = userDoc.data();
        const session = {
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
            if (requiredPermissions.requireVerified &&
                session.requestStatus !== "verified") {
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
            if (requiredPermissions.requireRole &&
                !requiredPermissions.requireRole.includes(session.role)) {
                return {
                    valid: false,
                    error: "Insufficient role permissions",
                    session,
                };
            }
        }
        return { valid: true, session };
    }
    catch (error) {
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
async function setUserCustomClaims(uid, claims) {
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
//# sourceMappingURL=security.js.map