import { verifyAppleIdentityToken } from "../../../../src/auth/apple-identity.js";
import { createGuardianSession } from "../../../../src/domain/family/postgres-family-cloud.js";
import { readJsonBody, requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";
import { writeFamilyError } from "../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const raw = readJsonBody(req);
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("invalid_json");
    const body = raw as Record<string, unknown>;
    if (typeof body.identityToken !== "string" || typeof body.nonce !== "string" ||
        typeof body.devicePublicRef !== "string" || typeof body.deviceName !== "string") {
      writeJson(res, 400, { error: "apple_session_fields_required" });
      return;
    }
    const identity = await verifyAppleIdentityToken(body.identityToken, body.nonce);
    const session = await createGuardianSession({
      identity,
      rawNonce: body.nonce,
      devicePublicRef: body.devicePublicRef,
      deviceName: body.deviceName,
      ...(typeof body.displayName === "string" ? { displayName: body.displayName } : {}),
    });
    writeJson(res, 201, session);
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("apple_")) {
      writeJson(res, error.message === "apple_sign_in_not_configured" ? 503 : 401, { error: error.message });
      return;
    }
    writeFamilyError(res, error, "apple_session_unavailable");
  }
}
