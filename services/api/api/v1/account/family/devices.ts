import { revokeLinkedFamilyDevice } from "../../../../src/domain/family/postgres-family-portal.js";
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
    const deviceId = body && typeof body === "object" && !Array.isArray(body)
      ? (body as Record<string, unknown>).deviceId
      : undefined;
    if (typeof deviceId !== "string" || !deviceId) throw new Error("invalid_json");
    writeJson(res, 200, await revokeLinkedFamilyDevice(identity, deviceId));
  } catch (error) {
    writeFamilyError(res, error, "family_device_revoke_unavailable");
  }
}
