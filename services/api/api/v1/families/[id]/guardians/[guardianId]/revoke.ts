import { revokeFamilyGuardian } from "../../../../../../src/domain/family/postgres-family-control.js";
import { requireGuardianSession } from "../../../../../_family-auth.js";
import { writeFamilyError } from "../../../../../_family-errors.js";
import { requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const context = await requireGuardianSession(req, res); if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    const guardianId = Array.isArray(req.query?.guardianId) ? req.query?.guardianId[0] : req.query?.guardianId;
    if (!familyId || !guardianId) throw new Error("invalid_json");
    writeJson(res, 200, await revokeFamilyGuardian({ context, familyId, guardianId }));
  } catch (error) { writeFamilyError(res, error, "guardian_revoke_unavailable"); }
}
