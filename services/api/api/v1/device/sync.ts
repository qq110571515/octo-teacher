import { listChildFamilyChanges, loadChildFamilySnapshot } from "../../../src/domain/family/postgres-family-control.js";
import { requireChildDeviceSession } from "../../_family-auth.js";
import { writeFamilyError } from "../../_family-errors.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requireGet(req, res)) return;
  try {
    const context = await requireChildDeviceSession(req, res); if (!context) return;
    const delta = await listChildFamilyChanges(context, req.query?.cursor);
    writeJson(res, 200, { ...delta,
      ...(req.query?.snapshot === "true" ? { snapshot: await loadChildFamilySnapshot(context) } : {}) });
  } catch (error) { writeFamilyError(res, error, "family_sync_unavailable"); }
}
