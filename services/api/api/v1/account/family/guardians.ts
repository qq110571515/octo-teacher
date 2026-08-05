import { revokeLinkedFamilyGuardian } from "../../../../src/domain/family/postgres-family-portal.js";
import { requirePlatformIdentity } from "../../../_account-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";
import { applyPortalCors, readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (applyPortalCors(req, res)) return;
  if ((req.method ?? "GET") !== "DELETE") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const identity = await requirePlatformIdentity(req, res);
    if (!identity) return;
    const body = readJsonBody(req);
    const guardianId = body && typeof body === "object" && !Array.isArray(body)
      ? (body as Record<string, unknown>).guardianId
      : undefined;
    if (typeof guardianId !== "string" || !guardianId) throw new Error("invalid_json");
    writeJson(res, 200, await revokeLinkedFamilyGuardian(identity, guardianId));
  } catch (error) {
    writeFamilyError(res, error, "family_guardian_revoke_unavailable");
  }
}
