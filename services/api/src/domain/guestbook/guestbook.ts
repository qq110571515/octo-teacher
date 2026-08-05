import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";

const challengeVersion = 1;
const challengeDifficulty = 20;
const challengeDelayMs = 2_500;
const challengeLifetimeMs = 10 * 60 * 1_000;

export type GuestbookErrorCode =
  | "challenge_expired"
  | "challenge_invalid"
  | "challenge_too_fast"
  | "guestbook_duplicate"
  | "guestbook_rate_limited"
  | "message_invalid"
  | "message_too_long"
  | "message_too_many_links"
  | "message_too_short"
  | "name_too_long";

export class GuestbookError extends Error {
  constructor(readonly code: GuestbookErrorCode) {
    super(code);
    this.name = "GuestbookError";
  }
}

export type GuestbookSubmission = {
  displayName: string;
  message: string;
  challengeToken: string;
  proof: number;
};

export type GuestbookChallenge = {
  token: string;
  salt: string;
  difficulty: number;
  notBeforeAt: string;
  expiresAt: string;
};

type ChallengePayload = {
  version: number;
  salt: string;
  difficulty: number;
  issuedAt: number;
  notBefore: number;
  expiresAt: number;
  ipHash: string;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function normalizeGuestbookName(value: string): string {
  return value.trim().replace(/\s+/g, " ") || "Anonymous";
}

export function normalizeGuestbookMessage(value: string): string {
  return value.replace(/\r\n?/g, "\n").trim();
}

export function parseGuestbookSubmission(input: unknown): GuestbookSubmission {
  if (!isRecord(input)) throw new GuestbookError("message_invalid");
  const website = typeof input.website === "string" ? input.website.trim() : "";
  if (website) throw new GuestbookError("challenge_invalid");

  const displayName = normalizeGuestbookName(typeof input.displayName === "string" ? input.displayName : "");
  const message = normalizeGuestbookMessage(typeof input.message === "string" ? input.message : "");
  const challengeToken = typeof input.challengeToken === "string" ? input.challengeToken : "";
  const proof = typeof input.proof === "number" ? input.proof : Number.NaN;

  if (displayName.length > 40) throw new GuestbookError("name_too_long");
  if (message.length < 10) throw new GuestbookError("message_too_short");
  if (message.length > 600) throw new GuestbookError("message_too_long");
  if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(message)) {
    throw new GuestbookError("message_invalid");
  }
  if ((message.match(/(?:https?:\/\/|www\.)/gi) ?? []).length > 2) {
    throw new GuestbookError("message_too_many_links");
  }
  if (!challengeToken || !Number.isSafeInteger(proof) || proof < 0 || proof > 50_000_000) {
    throw new GuestbookError("challenge_invalid");
  }
  return { displayName, message, challengeToken, proof };
}

function challengeSignature(secret: string, payload: string): Buffer {
  return createHmac("sha256", secret).update(payload).digest();
}

function encodeChallenge(secret: string, payload: ChallengePayload): string {
  const encoded = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return `${encoded}.${challengeSignature(secret, encoded).toString("base64url")}`;
}

function decodeChallenge(secret: string, token: string): ChallengePayload {
  const parts = token.split(".");
  if (parts.length !== 2) throw new GuestbookError("challenge_invalid");
  const [encoded, signature] = parts;
  const actual = Buffer.from(signature, "base64url");
  const expected = challengeSignature(secret, encoded);
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    throw new GuestbookError("challenge_invalid");
  }
  try {
    const parsed = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8")) as unknown;
    if (!isRecord(parsed)) throw new Error("invalid payload");
    return parsed as ChallengePayload;
  } catch {
    throw new GuestbookError("challenge_invalid");
  }
}

export function hashGuestbookIp(secret: string, ipAddress: string): string {
  return createHmac("sha256", secret).update(`guestbook-ip:${ipAddress}`).digest("hex");
}

export function createGuestbookChallenge(
  secret: string,
  ipAddress: string,
  now = Date.now(),
  difficulty = challengeDifficulty,
): GuestbookChallenge {
  if (secret.length < 32) throw new Error("guestbook_challenge_secret_unavailable");
  const payload: ChallengePayload = {
    version: challengeVersion,
    salt: randomBytes(16).toString("base64url"),
    difficulty,
    issuedAt: now,
    notBefore: now + challengeDelayMs,
    expiresAt: now + challengeLifetimeMs,
    ipHash: hashGuestbookIp(secret, ipAddress),
  };
  return {
    token: encodeChallenge(secret, payload),
    salt: payload.salt,
    difficulty: payload.difficulty,
    notBeforeAt: new Date(payload.notBefore).toISOString(),
    expiresAt: new Date(payload.expiresAt).toISOString(),
  };
}

export function fnv1a32(value: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash;
}

export function verifyGuestbookChallenge(input: {
  secret: string;
  ipAddress: string;
  submission: GuestbookSubmission;
  now?: number;
}): void {
  const now = input.now ?? Date.now();
  const payload = decodeChallenge(input.secret, input.submission.challengeToken);
  if (
    payload.version !== challengeVersion
    || typeof payload.salt !== "string"
    || payload.salt.length < 16
    || !Number.isInteger(payload.difficulty)
    || payload.difficulty < 8
    || payload.difficulty > 24
    || payload.ipHash !== hashGuestbookIp(input.secret, input.ipAddress)
  ) {
    throw new GuestbookError("challenge_invalid");
  }
  if (now < payload.notBefore) throw new GuestbookError("challenge_too_fast");
  if (now > payload.expiresAt) throw new GuestbookError("challenge_expired");

  const proofInput = `${payload.salt}:${input.submission.displayName}:${input.submission.message}:${input.submission.proof}`;
  const divisor = 2 ** (32 - payload.difficulty);
  if (Math.floor(fnv1a32(proofInput) / divisor) !== 0) {
    throw new GuestbookError("challenge_invalid");
  }
}

export function guestbookContentHash(message: string): string {
  return createHash("sha256").update(normalizeGuestbookMessage(message).toLowerCase()).digest("hex");
}
