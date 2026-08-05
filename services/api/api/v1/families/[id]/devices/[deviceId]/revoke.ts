import { revokeFamilyDevice } from "../../../../../../src/domain/family/postgres-family-cloud.js";
import { requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../../../_http.js";
import { requireGuardianSession } from "../../../../../_family-auth.js";
import { writeFamilyError } from "../../../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    const deviceId = Array.isArray(req.query?.deviceId) ? req.query?.deviceId[0] : req.query?.deviceId;
    if (!familyId || !deviceId) {
      writeJson(res, 400, { error: "device_revoke_fields_required" });
      return;
    }
    writeJson(res, 200, { family: await revokeFamilyDevice({ context, familyId, deviceId }) });
  } catch (error) {
    writeFamilyError(res, error, "device_revoke_unavailable");
  }
}
