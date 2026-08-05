import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

const KEY_BYTES = 32;
const IV_BYTES = 12;
const TAG_BYTES = 16;

function vaultKey(raw = process.env.FAMILY_AI_VAULT_KEY): Buffer {
  if (!raw) throw new Error("family_ai_vault_not_configured");
  const key = Buffer.from(raw, "base64");
  if (key.length !== KEY_BYTES) throw new Error("family_ai_vault_invalid");
  return key;
}

export function encryptFamilyAISecret(secret: string): string {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv("aes-256-gcm", vaultKey(), iv);
  const encrypted = Buffer.concat([cipher.update(secret, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [iv, tag, encrypted].map((value) => value.toString("base64url")).join(".");
}

export function decryptFamilyAISecret(value: string): string {
  const parts = value.split(".");
  if (parts.length !== 3) throw new Error("family_ai_secret_invalid");
  const [iv, tag, encrypted] = parts.map((part) => Buffer.from(part, "base64url"));
  if (iv.length !== IV_BYTES || tag.length !== TAG_BYTES || encrypted.length === 0) {
    throw new Error("family_ai_secret_invalid");
  }
  const decipher = createDecipheriv("aes-256-gcm", vaultKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString("utf8");
}
