import { listGuardianFamilyChanges, loadGuardianFamilySnapshot } from "../../../../src/domain/family/postgres-family-control.js";
import { requireGuardianSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requireGet(req, res)) return;
  try {
    const context = await requireGuardianSession(req, res); if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    if (!familyId) throw new Error("invalid_json");
    const delta = await listGuardianFamilyChanges(context, familyId, req.query?.cursor);
    writeJson(res, 200, { ...delta,
      ...(req.query?.snapshot === "true" ? { snapshot: await loadGuardianFamilySnapshot(context, familyId) } : {}) });
  } catch (error) { writeFamilyError(res, error, "family_sync_unavailable"); }
}
