import { listFamilyMembers } from "../../../../src/domain/family/postgres-family-control.js";
import { requireGuardianSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requireGet(req, res)) return;
  try {
    const context = await requireGuardianSession(req, res); if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    if (!familyId) throw new Error("invalid_json");
    writeJson(res, 200, await listFamilyMembers({ context, familyId,
      includeRevoked: req.query?.includeRevoked === "true" }));
  } catch (error) { writeFamilyError(res, error, "family_members_unavailable"); }
}
