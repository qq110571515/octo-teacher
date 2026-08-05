import { archiveFamilyChild } from "../../../../../../src/domain/family/postgres-family-control.js";
import { requireGuardianSession } from "../../../../../_family-auth.js";
import { writeFamilyError } from "../../../../../_family-errors.js";
import { requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const context = await requireGuardianSession(req, res); if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    const childProfileId = Array.isArray(req.query?.childId) ? req.query?.childId[0] : req.query?.childId;
    if (!familyId || !childProfileId) throw new Error("invalid_json");
    writeJson(res, 200, await archiveFamilyChild({ context, familyId, childProfileId }));
  } catch (error) { writeFamilyError(res, error, "child_archive_unavailable"); }
}
