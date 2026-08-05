import { createHash } from "node:crypto";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { loadPlatformEnv } from "../config/env.js";

export type SupabaseAccountIdentity = {
  subject: string;
  email: string;
  emailHash: string;
  maskedEmail: string;
  isOwnerApprover: boolean;
};

let cachedJwks: ReturnType<typeof createRemoteJWKSet> | undefined;
let cachedIssuer: string | undefined;

function normalizedEmail(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const email = value.trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) ? email : undefined;
}

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function maskEmail(email: string): string {
  const [local, domain] = email.split("@");
  const visible = local.slice(0, Math.min(2, local.length));
  return `${visible}${"*".repeat(Math.max(2, local.length - visible.length))}@${domain}`;
}

export async function verifySupabaseAccountToken(
  token: string | undefined,
): Promise<SupabaseAccountIdentity | undefined> {
  if (!token) return undefined;
  const env = loadPlatformEnv();
  const baseUrl = env.supabaseUrl?.replace(/\/$/, "");
  if (!baseUrl) throw new Error("supabase_auth_unavailable");
  const issuer = `${baseUrl}/auth/v1`;
  if (!cachedJwks || cachedIssuer !== issuer) {
    cachedIssuer = issuer;
    cachedJwks = createRemoteJWKSet(new URL(`${issuer}/.well-known/jwks.json`));
  }
  const { payload } = await jwtVerify(token, cachedJwks, {
    issuer,
    audience: "authenticated",
  });
  const email = normalizedEmail(payload.email);
  if (!payload.sub || !email || payload.email_verified === false) return undefined;
  const ownerEmail = normalizedEmail(env.ownerApproverEmail);
  return {
    subject: payload.sub,
    email,
    emailHash: sha256(email),
    maskedEmail: maskEmail(email),
    isOwnerApprover: ownerEmail === email,
  };
}
