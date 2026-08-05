import { bearerToken, writeJson, type ApiRequest, type ApiResponse } from "./_http.js";
import { verifySupabaseAccountToken, type SupabaseAccountIdentity } from "../src/auth/supabase-account-identity.js";

export async function requirePlatformIdentity(
  req: ApiRequest,
  res: ApiResponse,
): Promise<SupabaseAccountIdentity | undefined> {
  try {
    const identity = await verifySupabaseAccountToken(bearerToken(req));
    if (!identity) {
      res.setHeader("www-authenticate", "Bearer");
      writeJson(res, 401, { error: "verified_account_identity_required" });
    }
    return identity;
  } catch {
    writeJson(res, 503, { error: "account_identity_verification_unavailable" });
    return undefined;
  }
}

export async function requireOwnerApprover(
  req: ApiRequest,
  res: ApiResponse,
): Promise<SupabaseAccountIdentity | undefined> {
  const identity = await requirePlatformIdentity(req, res);
  if (!identity) return undefined;
  if (!identity.isOwnerApprover) {
    writeJson(res, 403, { error: "owner_approval_required" });
    return undefined;
  }
  return identity;
}
