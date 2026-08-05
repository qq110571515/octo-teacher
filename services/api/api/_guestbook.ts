import { requestHeader, writeJson, type ApiRequest, type ApiResponse } from "./_http.js";
import { isPortalOrigin } from "../src/security/portal-cors.js";

export function guestbookSecret(): string {
  const secret = process.env.GUESTBOOK_CHALLENGE_SECRET;
  if (!secret || secret.length < 32) throw new Error("guestbook_challenge_secret_unavailable");
  return secret;
}

export function guestbookRequestIp(req: ApiRequest): string {
  const forwarded = requestHeader(req, "x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || requestHeader(req, "x-real-ip")?.trim() || "unknown";
}

export function requireGuestbookPortalOrigin(req: ApiRequest, res: ApiResponse): boolean {
  if (isPortalOrigin(requestHeader(req, "origin"))) return true;
  writeJson(res, 403, { error: "origin_not_allowed" });
  return false;
}
