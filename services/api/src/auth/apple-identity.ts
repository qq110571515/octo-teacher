import { createHash } from "node:crypto";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";

const appleKeys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"), {
  cooldownDuration: 30_000,
  cacheMaxAge: 60 * 60 * 1_000,
  timeoutDuration: 5_000,
});

export type VerifiedAppleIdentity = {
  subject: string;
  email?: string;
  emailVerified: boolean;
};

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function base64URLSHA256(value: string): string {
  return createHash("sha256").update(value).digest("base64url");
}

export async function verifyAppleIdentityToken(
  identityToken: string,
  rawNonce: string,
  clientId = process.env.APPLE_SIGN_IN_CLIENT_ID,
): Promise<VerifiedAppleIdentity> {
  if (!clientId) throw new Error("apple_sign_in_not_configured");
  if (!identityToken || identityToken.length > 16_000) throw new Error("apple_identity_token_invalid");

  let payload: JWTPayload;
  try {
    ({ payload } = await jwtVerify(identityToken, appleKeys, {
      algorithms: ["RS256"],
      issuer: "https://appleid.apple.com",
      audience: clientId,
      clockTolerance: 10,
    }));
  } catch {
    throw new Error("apple_identity_token_invalid");
  }
  if (!payload.sub || typeof payload.sub !== "string" || payload.sub.length > 255) {
    throw new Error("apple_identity_subject_invalid");
  }
  if (payload.nonce !== base64URLSHA256(rawNonce)) throw new Error("apple_nonce_mismatch");
  const email = typeof payload.email === "string" ? payload.email : undefined;
  const emailVerified = payload.email_verified === true || payload.email_verified === "true";
  return { subject: payload.sub, ...(email ? { email } : {}), emailVerified };
}
